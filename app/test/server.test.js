'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildApp } = require('../src/server');

test('GET /health returns shallow 200 OK and X-Served-By-Region header', async () => {
  const { app } = buildApp({ region: 'us-east-1', logger: false });
  const res = await app.inject({ method: 'GET', url: '/health' });

  assert.equal(res.statusCode, 200);
  assert.equal(res.headers['x-served-by-region'], 'us-east-1');
  const body = res.json();
  assert.equal(body.status, 'ok');
  assert.equal(body.check_type, 'shallow');
  assert.equal(body.region, 'us-east-1');
  await app.close();
});

test('GET /health/deep returns 200 when DB is reachable and 503 when DB fails', async () => {
  const { app } = buildApp({ region: 'ap-south-1', logger: false });
  const okRes = await app.inject({ method: 'GET', url: '/health/deep' });
  assert.equal(okRes.statusCode, 200);
  assert.equal(okRes.headers['x-served-by-region'], 'ap-south-1');
  assert.equal(okRes.json().db_reachable, true);
  await app.close();

  // Simulate DB outage
  const failingRepo = {
    async checkDeepHealth() {
      throw new Error('Database connection timeout after 1500ms');
    },
    async close() {}
  };
  const { app: brokenApp } = buildApp({ region: 'us-east-1', repository: failingRepo, logger: false });
  const failRes = await brokenApp.inject({ method: 'GET', url: '/health/deep' });
  assert.equal(failRes.statusCode, 503);
  assert.equal(failRes.json().status, 'unhealthy');
  assert.equal(failRes.json().db_reachable, false);
  await brokenApp.close();
});

test('POST /notes and GET /notes track monotonic seq_no for RPO measurement', async () => {
  const { app } = buildApp({ region: 'us-east-1', logger: false });

  const post1 = await app.inject({
    method: 'POST',
    url: '/notes',
    payload: {
      seq_no: 101,
      title: 'Note 101',
      content: 'Primary write 101'
    }
  });
  assert.equal(post1.statusCode, 201);
  assert.equal(post1.json().seq_no, 101);
  assert.equal(post1.json().written_region, 'us-east-1');

  // Duplicate seq_no must return 409 Conflict
  const dup = await app.inject({
    method: 'POST',
    url: '/notes',
    payload: {
      seq_no: 101,
      title: 'Duplicate 101',
      content: 'Should conflict'
    }
  });
  assert.equal(dup.statusCode, 409);
  assert.equal(dup.json().error.code, 'DUPLICATE_SEQ_NO');

  // List notes verifies max_seq_no
  const listRes = await app.inject({ method: 'GET', url: '/notes' });
  assert.equal(listRes.statusCode, 200);
  const listBody = listRes.json();
  assert.equal(listBody.stats.total_count, 1);
  assert.equal(listBody.stats.max_seq_no, 101);

  await app.close();
});

test('POST /notes returns 503 READ_ONLY_REPLICA on SQLSTATE 25006', async () => {
  const readOnlyRepo = {
    async createNote() {
      const err = new Error('cannot execute INSERT in a read-only transaction');
      err.code = '25006';
      throw err;
    },
    async close() {}
  };

  const { app } = buildApp({ region: 'ap-south-1', repository: readOnlyRepo, logger: false });
  const res = await app.inject({
    method: 'POST',
    url: '/notes',
    payload: {
      seq_no: 200,
      title: 'Standby write attempt',
      content: 'Before Aurora promotion'
    }
  });

  assert.equal(res.statusCode, 503);
  assert.equal(res.json().error.code, 'READ_ONLY_REPLICA');
  assert.equal(res.headers['x-served-by-region'], 'ap-south-1');
  await app.close();
});
