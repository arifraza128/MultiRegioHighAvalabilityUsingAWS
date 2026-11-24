'use strict';

const { Pool } = require('pg');

const MIGRATION_SQL = `
CREATE TABLE IF NOT EXISTS notes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seq_no          BIGINT NOT NULL UNIQUE,
    title           VARCHAR(255) NOT NULL,
    content         TEXT NOT NULL,
    written_region  VARCHAR(32) NOT NULL,
    client_sent_at  TIMESTAMPTZ NOT NULL,
    db_committed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS idx_notes_seq_no_desc ON notes (seq_no DESC);
CREATE INDEX IF NOT EXISTS idx_notes_committed_at ON notes (db_committed_at DESC);
`;

/**
 * Creates a database repository backed either by PostgreSQL (when DB_HOST is set)
 * or an in-memory store (for Phase 2/3 smoke tests before Aurora Global is enabled).
 */
function createRepository(config = {}) {
  const region = config.region || process.env.AWS_REGION || 'us-east-1';
  const dbHost = config.dbHost !== undefined ? config.dbHost : (process.env.DB_HOST || '');

  // In-memory fallback mode when Aurora Global DB is disabled (Phase 2 & 3)
  if (!dbHost) {
    const memoryNotes = [];
    return {
      mode: 'memory',
      async init() {
        return { initialized: true, mode: 'memory' };
      },
      async checkDeepHealth() {
        const start = Date.now();
        return {
          db_reachable: true,
          db_role: 'memory-standby',
          db_latency_ms: Date.now() - start
        };
      },
      async createNote({ seq_no, title, content, client_sent_at }) {
        if (memoryNotes.some((n) => n.seq_no === Number(seq_no))) {
          const err = new Error(`Note with seq_no ${seq_no} already exists`);
          err.code = '23505';
          throw err;
        }
        const note = {
          id: `mem-${seq_no}-${Date.now()}`,
          seq_no: Number(seq_no),
          title,
          content,
          written_region: region,
          client_sent_at: client_sent_at || new Date().toISOString(),
          db_committed_at: new Date().toISOString()
        };
        memoryNotes.unshift(note);
        return note;
      },
      async listNotes(limit = 20) {
        const sliced = memoryNotes.slice(0, limit);
        const maxSeq = memoryNotes.reduce((max, n) => (n.seq_no > max ? n.seq_no : max), 0);
        return {
          db_role: 'memory-standby',
          stats: {
            total_count: memoryNotes.length,
            max_seq_no: maxSeq,
            latest_committed_at: memoryNotes[0]?.db_committed_at || null
          },
          notes: sliced
        };
      },
      async close() {}
    };
  }

  // PostgreSQL (Aurora Global Database) mode
  const pool = config.pool || new Pool({
    host: dbHost,
    port: Number(config.dbPort || process.env.DB_PORT || 5432),
    database: config.dbName || process.env.DB_NAME || 'notesdb',
    user: config.dbUser || process.env.DB_USER || 'notes_admin',
    password: config.dbPassword || process.env.DB_PASSWORD || '',
    max: 10,
    connectionTimeoutMillis: 1500,
    idleTimeoutMillis: 10000,
    statement_timeout: 2000,
    ssl: (config.dbSsl || process.env.DB_SSL) === 'true'
      ? { rejectUnauthorized: false }
      : false
  });

  return {
    mode: 'postgres',

    async init() {
      const client = await pool.connect();
      try {
        const recoveryRes = await client.query('SELECT pg_is_in_recovery() AS is_replica;');
        const isReplica = Boolean(recoveryRes.rows[0]?.is_replica);
        if (!isReplica) {
          await client.query(MIGRATION_SQL);
        }
        return { initialized: true, mode: 'postgres', db_role: isReplica ? 'replica' : 'writer' };
      } finally {
        client.release();
      }
    },

    async checkDeepHealth() {
      const start = Date.now();
      const client = await pool.connect();
      try {
        const res = await client.query('SELECT pg_is_in_recovery() AS is_replica, NOW() AS db_time;');
        const isReplica = Boolean(res.rows[0]?.is_replica);
        return {
          db_reachable: true,
          db_role: isReplica ? 'replica' : 'writer',
          db_latency_ms: Date.now() - start
        };
      } finally {
        client.release();
      }
    },

    async createNote({ seq_no, title, content, client_sent_at }) {
      const client = await pool.connect();
      let discardConnection = false;
      try {
        const insertSql = `
          INSERT INTO notes (seq_no, title, content, written_region, client_sent_at)
          VALUES ($1, $2, $3, $4, $5)
          RETURNING id, seq_no, title, content, written_region, client_sent_at, db_committed_at;
        `;
        const sentAt = client_sent_at || new Date().toISOString();
        const res = await client.query(insertSql, [seq_no, title, content, region, sentAt]);
        const row = res.rows[0];
        return {
          ...row,
          seq_no: Number(row.seq_no)
        };
      } catch (err) {
        // SQLSTATE 25006: read_only_sql_transaction — force pool to evict stale socket upon promotion
        if (err.code === '25006') {
          discardConnection = true;
        }
        throw err;
      } finally {
        client.release(discardConnection);
      }
    },

    async listNotes(limit = 20) {
      const client = await pool.connect();
      try {
        const roleRes = await client.query('SELECT pg_is_in_recovery() AS is_replica;');
        const isReplica = Boolean(roleRes.rows[0]?.is_replica);

        const statsRes = await client.query(`
          SELECT
            COUNT(*)::INT AS total_count,
            COALESCE(MAX(seq_no), 0)::BIGINT AS max_seq_no,
            MAX(db_committed_at) AS latest_committed_at
          FROM notes;
        `);

        const notesRes = await client.query(
          `SELECT id, seq_no, title, content, written_region, client_sent_at, db_committed_at
           FROM notes
           ORDER BY seq_no DESC
           LIMIT $1;`,
          [limit]
        );

        const statsRow = statsRes.rows[0];
        return {
          db_role: isReplica ? 'replica' : 'writer',
          stats: {
            total_count: Number(statsRow.total_count),
            max_seq_no: Number(statsRow.max_seq_no),
            latest_committed_at: statsRow.latest_committed_at
          },
          notes: notesRes.rows.map((r) => ({ ...r, seq_no: Number(r.seq_no) }))
        };
      } finally {
        client.release();
      }
    },

    async close() {
      await pool.end();
    }
  };
}

module.exports = { createRepository };
