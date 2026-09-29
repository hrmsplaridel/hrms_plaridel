const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');

const {
  createPublicIpLimiter,
  createApplicantWorkflowLimiter,
} = require('../src/middleware/rateLimiters');

function requestJson(server, path) {
  const address = server.address();
  return new Promise((resolve, reject) => {
    const request = http.request(
      {
        host: '127.0.0.1',
        port: address.port,
        method: 'POST',
        path,
        headers: { 'Content-Type': 'application/json' },
      },
      (response) => {
        const chunks = [];
        response.on('data', (chunk) => chunks.push(chunk));
        response.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          resolve({
            status: response.statusCode,
            json: text ? JSON.parse(text) : null,
          });
        });
      },
    );
    request.on('error', reject);
    request.end('{}');
  });
}

async function listen(app, t) {
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
  });
  return server;
}

test('public workflow limiters do not share counters', async (t) => {
  const app = express();
  app.use(express.json());
  app.post(
    '/application',
    createPublicIpLimiter({
      windowMs: 60_000,
      limit: 1,
      message: 'Application limited',
    }),
    (_req, res) => res.json({ ok: true }),
  );
  app.post(
    '/contact',
    createPublicIpLimiter({
      windowMs: 60_000,
      limit: 1,
      message: 'Contact limited',
    }),
    (_req, res) => res.json({ ok: true }),
  );
  const server = await listen(app, t);

  assert.equal((await requestJson(server, '/application')).status, 200);
  const blocked = await requestJson(server, '/application');
  assert.equal(blocked.status, 429);
  assert.equal(blocked.json.error, 'Application limited');
  assert.equal((await requestJson(server, '/contact')).status, 200);
});

test('verified applicant workflow limits are isolated by application', async (t) => {
  const app = express();
  app.use(express.json());
  app.post(
    '/applications/:applicationId/upload',
    createApplicantWorkflowLimiter({
      windowMs: 60_000,
      limit: 1,
      message: 'Upload limited',
    }),
    (_req, res) => res.json({ ok: true }),
  );
  const server = await listen(app, t);

  assert.equal((await requestJson(server, '/applications/app-a/upload')).status, 200);
  assert.equal((await requestJson(server, '/applications/app-a/upload')).status, 429);
  assert.equal((await requestJson(server, '/applications/app-b/upload')).status, 200);
});
