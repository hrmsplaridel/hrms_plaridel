const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const jwt = require('jsonwebtoken');
const { createApiRateLimits } = require('../src/middleware/rateLimiters');
const { createAuthMiddleware } = require('../src/middleware/auth');

process.env.JWT_SECRET = 'isolated-api-rate-limit-test-secret';
const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';

async function fixture(t, overrides = {}) {
  let checks = 0;
  const db = {query: async (_sql, [id]) => {
    checks++;
    return {rows: [{id, role: 'employee', is_active: id !== 'disabled', employment_status: 'active', auth_version: 0}]};
  }};
  const app = express();
  app.set('trust proxy', 1);
  app.use('/api', ...createApiRateLimits({db, windowMs: 60000, readMax: 1, writeMax: 1, heavyMax: 1, ipReadMax: 100, ipWriteMax: 100, ...overrides}));
  app.all('/api/secure', createAuthMiddleware(db), (req, res) => res.json({id: req.user.id}));
  app.use('/api', (_req, res) => res.json({ok: true}));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  return {
    checks: () => checks,
    request: (id, method = 'GET', path = '/api/example', extra = {}) => fetch(`http://127.0.0.1:${server.address().port}${path}`, {
      method, headers: {
        'X-Forwarded-For': '192.0.2.10',
        ...(id ? {Authorization: `Bearer ${jwt.sign({id, typ: 'access'}, process.env.JWT_SECRET)}`} : {}),
        ...extra,
      },
    }),
  };
}

test('same-IP employees have independent reads and writes', async t => {
  const f = await fixture(t);
  assert.equal((await f.request(A)).status, 200);
  const limited = await f.request(A);
  assert.equal(limited.status, 429);
  assert.ok(limited.headers.get('retry-after'));
  assert.equal((await f.request(B)).status, 200);
  assert.equal((await f.request(A, 'POST')).status, 200);
  assert.equal((await f.request(A, 'POST')).status, 429);
  assert.equal((await f.request(B, 'POST')).status, 200);
  assert.equal((await f.request(A, 'GET', '/api/example', {'X-Forwarded-For': '192.0.2.20'})).status, 429);
});

test('report and render quotas do not consume ordinary write quota', async t => {
  const f = await fixture(t);
  assert.equal((await f.request(A, 'POST', '/api/dtr-daily-summary/bulk-report')).status, 200);
  assert.equal((await f.request(A, 'POST', '/api/leave/print/requests/request/render')).status, 429);
  assert.equal((await f.request(A, 'POST')).status, 200);
  assert.equal((await f.request(B, 'POST', '/api/locator-slips/print/types/type/preview')).status, 200);
});

test('unauthenticated callers retain an IP quota', async t => {
  const f = await fixture(t);
  assert.equal((await f.request(null)).status, 200);
  assert.equal((await f.request(null)).status, 429);
  assert.equal((await f.request(A)).status, 200);
});

test('unverified identities cannot select a user quota', async t => {
  const f = await fixture(t);
  assert.equal((await f.request(null, 'GET', '/api/example', {Authorization: 'Bearer forged', 'X-Employee-Id': B})).status, 401);
  assert.equal((await f.request('disabled')).status, 403);
  const refresh = jwt.sign({id: A, typ: 'refresh'}, process.env.JWT_SECRET);
  assert.equal((await f.request(null, 'GET', '/api/example', {Authorization: `Bearer ${refresh}`})).status, 401);
  const stale = jwt.sign({id: A, typ: 'access', auth_version: 99}, process.env.JWT_SECRET);
  assert.equal((await f.request(null, 'GET', '/api/example', {Authorization: `Bearer ${stale}`})).status, 401);
  const expired = jwt.sign({id: A, typ: 'access'}, process.env.JWT_SECRET, {expiresIn: -1});
  assert.equal((await f.request(null, 'GET', '/api/example', {Authorization: `Bearer ${expired}`})).status, 401);
  assert.equal((await f.request(A)).status, 200);
});

test('injected req.user alone cannot bypass authentication or choose a quota', async t => {
  const db = {query: async () => ({rows: []})};
  const app = express();
  app.use((req, _res, next) => {req.user = {id: B}; next();});
  app.use('/api', ...createApiRateLimits({db, windowMs: 60000, readMax: 1}));
  app.use('/api', (_req, res) => res.json({ok: true}));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}/api/test`;
  assert.equal((await fetch(url)).status, 200);
  assert.equal((await fetch(url)).status, 429);
  assert.equal((await fetch(url, {headers: {Authorization: 'Bearer forged'}})).status, 401);
});

test('coarse IP guard rejects floods before database authentication', async t => {
  const f = await fixture(t, {ipReadMax: 1});
  assert.equal((await f.request(A)).status, 200);
  assert.equal((await f.request(B)).status, 429);
  assert.equal(f.checks(), 1);
});

test('route authentication reuses only the account verified on this request', async t => {
  const f = await fixture(t);
  assert.equal((await f.request(A, 'GET', '/api/secure')).status, 200);
  assert.equal(f.checks(), 1);
});
