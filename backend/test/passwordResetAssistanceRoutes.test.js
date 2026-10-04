const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('assistance HTTP routes enforce authentication, super-admin access and public rate limiting', async () => {
  let calls = 0;
  const restores = [
    withMockedModule('../src/middleware/auth', { authMiddleware(req, res, next) {
      if (!req.headers.authorization) return res.status(401).json({ error: 'unauthorized' });
      req.user = { id: 'actor', role: req.headers.authorization }; next();
    } }),
    withMockedModule('../src/services/passwordResetAssistance', { createPasswordResetAssistance: () => ({
      request: async () => { calls++; return { message: 'generic' }; },
      list: async () => ({ requests: [] }),
      send: async (_id, _actor, verified) => {
        if (verified !== true) throw Object.assign(new Error('Verify requester'), { status: 400 });
        return { message: 'sent' };
      },
      close: async () => ({ message: 'closed' }),
    }) }),
  ];
  clearModule('../src/routes/passwordResetAssistance');
  const app = express(); app.use(express.json());
  const { publicRouter, adminRouter } = require('../src/routes/passwordResetAssistance');
  app.use('/public', publicRouter); app.use('/admin', adminRouter);
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    for (const endpoint of ['/admin', '/admin/id/send', '/admin/id/close']) {
      const method = endpoint === '/admin' ? 'GET' : 'POST';
      assert.equal((await fetch(base + endpoint, { method })).status, 401);
      assert.equal((await fetch(base + endpoint, { method, headers: { authorization: 'admin' } })).status, 403);
      assert.equal((await fetch(base + endpoint, { method, headers: { authorization: 'employee' } })).status, 403);
    }
    assert.equal((await fetch(base + '/admin', { headers: { authorization: 'super_admin' } })).status, 200);
    assert.equal((await fetch(base + '/admin/id/send', { method: 'POST', headers: { authorization: 'super_admin' } })).status, 400);
    const responses = [];
    for (let i = 0; i < 4; i++) responses.push((await fetch(base + '/public', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'test@test.local' }) })).status);
    assert.deepEqual(responses, [200, 200, 200, 429]);
    assert.equal(calls, 3);
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    clearModule('../src/routes/passwordResetAssistance'); restores.reverse().forEach(r => r());
  }
});
