const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createAttendanceResetRouter } = require('../src/routes/attendanceReset');

test('employee search, preview and reset are exclusively super-admin operations', async () => {
  const calls = [];
  const app = express(); app.use(express.json());
  app.use(createAttendanceResetRouter({
    employees: async () => ({ items: [], official_date: '2026-11-08' }),
    preview: async (...args) => { calls.push(args); return { can_reset: true }; },
    apply: async (...args) => { calls.push(args); return { punches_deleted: 1 }; },
  }, (req, res, next) => {
    if (!req.headers.authorization) return res.sendStatus(401);
    req.user = { id: 'actor', role: req.headers.authorization }; next();
  }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    for (const [method, path] of [['GET', '/employees'], ['POST', '/preview'], ['POST', '/apply']]) {
      for (const role of [null, 'admin', 'hr', 'employee', 'supervisor', 'mayor', 'mayor_office_staff']) {
        const response = await fetch(url + path, { method, headers: role ? { authorization: role } : {} });
        assert.equal(response.status, role ? 403 : 401);
      }
      const response = await fetch(url + path, { method, headers: { authorization: 'super_admin' } });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('cache-control'), 'no-store');
    }
    assert.equal(calls.length, 2);
    assert.equal(calls[1][1], 'actor');
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

test('preview errors keep their validation status but unexpected errors are redacted', async () => {
  const router = createAttendanceResetRouter({ preview: async () => { throw Object.assign(new Error('Preview changed'), { status: 409 }); } }, (_req, _res, next) => next());
  const handle = router.stack.find(l => l.route?.path === '/preview').route.stack.at(-1).handle;
  const res = { status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
  await handle({ body: {}, user: { id: 'actor' } }, res);
  assert.equal(res.code, 409);
  assert.equal(res.body.error, 'Preview changed');
  const failingRouter = createAttendanceResetRouter({ preview: async () => { throw new Error('private database detail'); } }, (_req, _res, next) => next());
  const failingHandle = failingRouter.stack.find(l => l.route?.path === '/preview').route.stack.at(-1).handle;
  await failingHandle({ body: {}, user: { id: 'actor' } }, res);
  assert.equal(res.code, 503);
  assert.equal(res.body.error.includes('private database detail'), false);
});
