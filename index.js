'use strict';

// The New Relic agent must be the very first module loaded so it can
// instrument Node's core libraries. It is loaded only when a license key is
// present, which keeps local development and CI (lint/test) dependency-light
// and avoids noisy "no license key" warnings.
if (process.env.NEW_RELIC_LICENSE_KEY) {
  require('newrelic');
}

const { createServer } = require('./lib/server');
const { log } = require('./lib/logger');

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '0.0.0.0';
const SHUTDOWN_TIMEOUT_MS = Number(process.env.SHUTDOWN_TIMEOUT_MS) || 10000;

const server = createServer();

server.listen(PORT, HOST, () => {
  log('info', 'server_started', { host: HOST, port: PORT });
});

/**
 * Gracefully stop accepting new connections, let in-flight requests finish,
 * then exit. Containers send SIGTERM on `stop`, so honouring it avoids
 * dropped requests during deploys/restarts.
 */
function shutdown(signal) {
  log('info', 'shutdown_initiated', { signal });

  server.close((err) => {
    if (err) {
      log('error', 'shutdown_error', { error: err.message });
      process.exit(1);
    }
    log('info', 'shutdown_complete', {});
    process.exit(0);
  });

  // Safety net: force exit if connections do not drain in time.
  setTimeout(() => {
    log('error', 'shutdown_forced', { timeoutMs: SHUTDOWN_TIMEOUT_MS });
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS).unref();
}

for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => shutdown(signal));
}

module.exports = server;
