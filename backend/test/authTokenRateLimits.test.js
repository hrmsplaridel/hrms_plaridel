const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const jwt = require('jsonwebtoken');
const {createAuthTokenLimiters} = require('../src/middleware/rateLimiters');
process.env.JWT_REFRESH_SECRET = 'isolated-refresh-limiter-test-secret';

test('refresh and logout have independent verified-user quotas on the same IP', async t => {
  const app = express();
  app.use(express.json());
  const limits = createAuthTokenLimiters({windowMs: 60000, refreshMax: 1, logoutMax: 1, ipMax: 100});
  app.post('/refresh', ...limits.refresh, (_req, res) => res.json({ok: true}));
  app.post('/logout', ...limits.logout, (_req, res) => res.json({ok: true}));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const send = (id, path = '/refresh', secret = process.env.JWT_REFRESH_SECRET) => fetch(`http://127.0.0.1:${server.address().port}${path}`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({refreshToken: jwt.sign({id,typ: 'refresh'},secret)})});
  assert.equal((await send('employee-a')).status, 200);
  assert.equal((await send('employee-a')).status, 429);
  assert.equal((await send('employee-b')).status, 200);
  assert.equal((await send('employee-a', '/logout')).status, 200);
  assert.equal((await send('employee-a', '/logout')).status, 429);
  assert.equal((await send('forged-a', '/refresh', 'wrong-secret')).status, 200);
  assert.equal((await send('forged-b', '/refresh', 'wrong-secret')).status, 429);
});
