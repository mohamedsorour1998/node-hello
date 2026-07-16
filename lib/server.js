'use strict';

const http = require('http');
const { log } = require('./logger');

/**
 * Build the HTTP server. Kept separate from `listen()` so tests can bind it
 * to an ephemeral port without side effects.
 *
 * Routes:
 *   GET /            -> "Hello Node!" (the original app behaviour)
 *   GET /health(z)   -> JSON health probe used by the container HEALTHCHECK
 */
function createServer() {
  return http.createServer((req, res) => {
    const start = Date.now();

    res.on('finish', () => {
      log('info', 'request_handled', {
        method: req.method,
        path: req.url,
        status: res.statusCode,
        durationMs: Date.now() - start,
      });
    });

    if (req.url === '/health' || req.url === '/healthz') {
      const body = JSON.stringify({
        status: 'ok',
        uptime: process.uptime(),
      });
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(body);
      return;
    }

    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Hello Node!\n');
  });
}

module.exports = { createServer };
