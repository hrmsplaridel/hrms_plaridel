const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const {createAuthLoginLimiters} = require('../src/middleware/rateLimiters');

async function setup(t, ipMax = 100) {
  const app = express();
  app.use(express.json());
  app.post('/login', ...createAuthLoginLimiters({windowMs: 60000, accountMax: 2, ipMax}),
    (req, res) => res.status(req.body.password === 'correct' ? 200 : 401).json({ok: true}));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  return (email, password = 'wrong') => fetch(`http://127.0.0.1:${server.address().port}/login`, {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password}),
  });
}

test('failed login quota isolates accounts sharing an IP and normalizes email', async t => {
  const send = await setup(t);
  assert.equal((await send('employee-a@example.com')).status, 401);
  assert.equal((await send(' EMPLOYEE-A@example.com ')).status, 401);
  const blocked = await send('employee-a@example.com', 'correct');
  assert.equal(blocked.status, 429);
  assert.equal((await blocked.json()).rateLimitScope, 'auth_login');
  assert.ok(Number(blocked.headers.get('retry-after')) > 0);
  assert.equal((await send('employee-b@example.com', 'correct')).status, 200);
});

test('successful logins do not consume the account quota', async t => {
  const send = await setup(t);
  for (let i = 0; i < 3; i++) {
    assert.equal((await send('employee-a@example.com', 'correct')).status, 200);
  }
  assert.equal((await send('employee-a@example.com')).status, 401);
});

test('IP flood limit still blocks attempts across different accounts', async t => {
  const send = await setup(t, 2);
  assert.equal((await send('employee-a@example.com')).status, 401);
  assert.equal((await send('employee-b@example.com')).status, 401);
  const blocked = await send('employee-c@example.com');
  assert.equal(blocked.status, 429);
  assert.equal((await blocked.json()).rateLimitScope, 'network_login');
});
