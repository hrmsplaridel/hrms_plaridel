const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('app event socket rejects a token issued before password reset', async () => {
  const secret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = 'socket-test-secret';
  const restore = withMockedModule('../src/config/db', { pool: { query: async () => ({ rows: [{ id: 'user', role: 'admin', is_active: true, employment_status: 'active', auth_version: 1 }] }) } });
  clearModule('../src/websockets/appEvents');
  let server;
  try {
    server = require('../src/websockets/appEvents').initAppEventsWebSocket();
    let closed = false, sent = false;
    const ws = { readyState: 1, close() { closed = true; }, send() { sent = true; }, on() {} };
    const token = jwt.sign({ id: 'user', role: 'admin', auth_version: 0 }, process.env.JWT_SECRET);
    await server.listeners('connection')[0](ws, { url: `/ws/app?token=${token}` });
    assert.equal(closed, true);
    assert.equal(sent, false);
    const validToken = jwt.sign({ id: 'user', role: 'admin', auth_version: 1 }, process.env.JWT_SECRET);
    closed = false;
    await server.listeners('connection')[0](ws, { url: `/ws/app?token=${validToken}` });
    assert.equal(sent, true);
    server.clients.add(ws);
    require('../src/websockets/appEvents').disconnectUserSessions('user');
    assert.equal(closed, true);
    server.clients.delete(ws);
  } finally { if (server) server.close(); clearModule('../src/websockets/appEvents'); restore(); process.env.JWT_SECRET = secret; }
});

test('RSP admin shortcut verifies live session state', async () => {
  const secret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = 'rsp-test-secret';
  let checked = false;
  const restore = withMockedModule('../src/middleware/auth', { authMiddleware: async (_req, res) => { checked = true; res.status(401).json({ error: 'revoked' }); } });
  clearModule('../src/routes/rspApplications');
  try {
    const router = require('../src/routes/rspApplications');
    const guard = router.stack.flatMap(e => e.route?.stack || []).find(e => e.name === 'requireApplicantProof').handle;
    const token = jwt.sign({ id: 'user', role: 'admin' }, process.env.JWT_SECRET);
    const req = { get: () => `Bearer ${token}`, headers: { authorization: `Bearer ${token}` }, params: {}, body: {} };
    const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json() {} };
    let next = false;
    await guard(req, res, () => { next = true; });
    assert.equal(checked, true);
    assert.equal(next, false);
    assert.equal(res.statusCode, 401);
  } finally { clearModule('../src/routes/rspApplications'); restore(); process.env.JWT_SECRET = secret; }
});
