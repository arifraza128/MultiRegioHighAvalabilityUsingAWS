'use strict';

const { buildApp } = require('./server');

const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';

async function start() {
  const { app, repository } = buildApp();

  try {
    const initResult = await repository.init();
    app.log.info({ initResult }, 'Database repository initialized');
  } catch (err) {
    // Log error but still boot the server so /health (shallow) passes and /health/deep reports 503 cleanly
    app.log.error({ err: err.message }, 'Initial database connection failed on startup; continuing in degraded mode');
  }

  try {
    await app.listen({ port: PORT, host: HOST });
  } catch (err) {
    app.log.fatal({ err: err.message }, 'Failed to bind HTTP server');
    process.exit(1);
  }
}

start();
