const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');

const {
  createPublicIpLimiter,
  createApplicantWorkflowLimiter,
  createPublicLookupLimiter,
  createApiRateLimits,
} = require('../src/middleware/rateLimiters');

function requestJson(server, path, method = 'POST') {
  const address = server.address();
  return new Promise((resolve, reject) => {
    const request = http.request(
      {
        host: '127.0.0.1',
        port: address.port,
        method,
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
    request.end(method === 'GET' ? undefined : '{}');
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

test('status polling preserves the failed lookup quota across both lookup routes', async (t) => {
  const app = express();
  const lookupLimiter = createPublicLookupLimiter({ windowMs: 60_000, limit: 2 });
  app.get(['/by-email', '/by-applicant-number'], lookupLimiter, (req, res) => {
    res.status(req.query.missing ? 404 : 200).json({ ok: !req.query.missing });
  });
  const server = await listen(app, t);

  // More than a full window of the landing page's 30-second polling.
  for (let i = 0; i < 35; i++) {
    const path = i % 2 ? '/by-email' : '/by-applicant-number';
    assert.equal((await requestJson(server, path, 'GET')).status, 200);
  }
  assert.equal((await requestJson(server, '/by-email?missing=1', 'GET')).status, 404);
  assert.equal((await requestJson(server, '/by-applicant-number', 'GET')).status, 200);
  assert.equal((await requestJson(server, '/by-applicant-number?missing=1', 'GET')).status, 404);
  const blocked = await requestJson(server, '/by-email?missing=1', 'GET');
  assert.equal(blocked.status, 429);
  assert.match(blocked.json.error, /Too many lookup requests/);
});

test('successful public polling remains subject to the API IP flood limit', async (t) => {
  const app = express();
  app.use(createApiRateLimits({ ipReadMax: 3, readMax: 10 }));
  app.get('/by-email', createPublicLookupLimiter({ limit: 2 }), (_req, res) => res.json({ ok: true }));
  const server = await listen(app, t);
  for (let i = 0; i < 3; i++) {
    assert.equal((await requestJson(server, '/by-email', 'GET')).status, 200);
  }
  const blocked = await requestJson(server, '/by-email', 'GET');
  assert.equal(blocked.status, 429);
  assert.equal(blocked.json.rateLimitScope, 'network_read');
});
