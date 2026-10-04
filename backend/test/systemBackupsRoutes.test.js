const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createSystemBackupsRouter } = require('../src/routes/systemBackups');
test('all backup endpoints require superadmin and redact unexpected errors', async () => {
  const app = express(); app.use(express.json());
  let calls = 0;
  app.use(createSystemBackupsRouter({
    snapshot: async () => ({ health: 'missing' }),
    request: async () => { calls++; return { id: 'new', status: 'running' }; },
    configure: async () => { throw new Error('postgres://SECRET'); },
  }, (req, res, next) => {
    if (!req.headers.authorization) return res.sendStatus(401);
    req.user = { id: null, role: req.headers.authorization }; next();
  }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    for (const [method, route] of [['GET', '/'], ['POST', '/'], ['PUT', '/settings']]) {
      assert.equal((await fetch(url + route, { method })).status, 401);
      for (const role of ['admin', 'hr', 'employee']) assert.equal((await fetch(url + route, { method, headers: { authorization: role } })).status, 403);
    }
    assert.equal((await fetch(url, { method: 'POST', headers: { authorization: 'super_admin' } })).status, 202);
    assert.equal(calls, 1);
    const response = await fetch(url + '/settings', { method: 'PUT', headers: { authorization: 'super_admin' } });
    assert.equal(response.status, 503); assert.ok(!(await response.text()).includes('SECRET'));
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});
