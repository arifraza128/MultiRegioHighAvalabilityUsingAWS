'use strict';

const Fastify = require('fastify');
const crypto = require('crypto');
const { createRepository } = require('./db');

const TASK_ID = process.env.ECS_TASK_ID || crypto.randomBytes(4).toString('hex');

function buildApp(options = {}) {
  const region = options.region || process.env.AWS_REGION || 'us-east-1';
  const repository = options.repository || createRepository({ region });

  const app = Fastify({
    logger: options.logger !== undefined ? options.logger : true
  });

  // Inject mandatory observability and region headers on every response (API.md Section 1)
  app.addHook('onSend', async (_request, reply, payload) => {
    reply.header('X-Served-By-Region', region);
    reply.header('X-Container-Task-Id', TASK_ID);
    reply.header('Cache-Control', 'no-store');
    return payload;
  });

  // 1. Shallow Liveness Health Check (never touches DB so container won't crash-loop on DB outage)
  app.get('/health', async () => {
    return {
      status: 'ok',
      check_type: 'shallow',
      region,
      uptime_seconds: Number(process.uptime().toFixed(2)),
      timestamp: new Date().toISOString()
    };
  });

  // 2. Deep Readiness & Database Role Health Check (ALB Target Group & Failover Probe)
  app.get('/health/deep', async (_request, reply) => {
    try {
      const dbStatus = await repository.checkDeepHealth();
      return {
        status: 'healthy',
        check_type: 'deep',
        region,
        ...dbStatus,
        timestamp: new Date().toISOString()
      };
    } catch (err) {
      reply.code(503);
      return {
        status: 'unhealthy',
        check_type: 'deep',
        region,
        db_reachable: false,
        db_role: 'unknown',
        error: err.message || 'Database connection failed',
        timestamp: new Date().toISOString()
      };
    }
  });

  // 3. Create Note & RPO Monotonic Sequence Record (POST /notes)
  app.post(
    '/notes',
    {
      schema: {
        body: {
          type: 'object',
          required: ['seq_no', 'title', 'content'],
          properties: {
            seq_no: { type: 'integer', minimum: 1 },
            title: { type: 'string', minLength: 1, maxLength: 255 },
            content: { type: 'string', minLength: 1, maxLength: 4000 },
            client_sent_at: { type: 'string' }
          }
        }
      }
    },
    async (request, reply) => {
      try {
        const note = await repository.createNote(request.body);
        reply.code(201);
        return note;
      } catch (err) {
        if (err.code === '23505') {
          reply.code(409);
          return {
            error: {
              code: 'DUPLICATE_SEQ_NO',
              message: `Sequence number ${request.body.seq_no} already exists.`,
              region,
              timestamp: new Date().toISOString()
            }
          };
        }

        if (err.code === '25006') {
          reply.code(503);
          return {
            error: {
              code: 'READ_ONLY_REPLICA',
              message: 'Database is currently a read-only standby replica; promotion in progress.',
              region,
              timestamp: new Date().toISOString()
            }
          };
        }

        reply.code(503);
        return {
          error: {
            code: 'DB_UNAVAILABLE',
            message: err.message || 'Database write failed.',
            region,
            timestamp: new Date().toISOString()
          }
        };
      }
    }
  );

  // 4. List Notes & RPO Summary Stats (GET /notes)
  app.get('/notes', async (request, reply) => {
    const rawLimit = Number(request.query?.limit || 20);
    const limit = Math.min(Math.max(1, Number.isNaN(rawLimit) ? 20 : rawLimit), 100);

    try {
      const result = await repository.listNotes(limit);
      return {
        served_by_region: region,
        ...result
      };
    } catch (err) {
      reply.code(503);
      return {
        error: {
          code: 'DB_UNAVAILABLE',
          message: err.message || 'Database query failed.',
          region,
          timestamp: new Date().toISOString()
        }
      };
    }
  });

  app.addHook('onClose', async () => {
    await repository.close();
  });

  return { app, repository };
}

module.exports = { buildApp };
