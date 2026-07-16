'use strict';

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const { createServer } = require('../lib/server');

function listen(server) {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

function get(port, path) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { host: '127.0.0.1', port, path, method: 'GET' },
      (res) => {
        let data = '';
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () =>
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: data,
          }),
        );
      },
    );
    req.on('error', reject);
    req.end();
  });
}

test('GET / returns 200 with the greeting', async (t) => {
  const server = createServer();
  const port = await listen(server);
  t.after(() => server.close());

  const res = await get(port, '/');
  assert.strictEqual(res.status, 200);
  assert.match(res.body, /Hello Node!/);
});

test('GET /health returns 200 with ok status', async (t) => {
  const server = createServer();
  const port = await listen(server);
  t.after(() => server.close());

  const res = await get(port, '/health');
  assert.strictEqual(res.status, 200);

  const payload = JSON.parse(res.body);
  assert.strictEqual(payload.status, 'ok');
  assert.strictEqual(typeof payload.uptime, 'number');
});
