const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('leave details bind every SQL parameter, including the Mayor access flag', async () => {
  const calls = [];
  const query = async (sql, params = []) => {
    if (!sql.includes('WHERE lr.id = $1')) return { rows: [] };
    const parameterCount = Math.max(...Array.from(sql.matchAll(/\$(\d+)/g), (match) => Number(match[1])));
    assert.equal(params.length, parameterCount, 'all PostgreSQL placeholders need a bound value');
    calls.push(params);
    // Model the existing owner/admin/Mayor scope without granting an unrelated employee access.
    const allowed = params[1] || params[2] === 'owner' || params[3];
    return { rows: allowed ? [{ id: params[0], user_id: 'owner', status: 'pending_hr' }] : [] };
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query, connect: async () => ({ query, release() {} }) },
  });
  clearModule('../src/routes/leaveRoutes');
  try {
    const router = require('../src/routes/leaveRoutes');
    const handler = router.stack.find((entry) =>
      entry.route?.path === '/:id' && entry.route.methods.get).route.stack.at(-1).handle;
    for (const [id, role, expectedStatus, isAdmin, isMayor] of [
      ['owner', 'employee', 200, false, false],
      ['administrator', 'admin', 200, true, false],
      ['hr-reviewer', 'hr', 200, true, false],
      ['mayor-reviewer', 'mayor', 200, false, true],
      ['unrelated', 'employee', 404, false, false],
    ]) {
      const res = {
        statusCode: 200, body: null,
        status(code) { this.statusCode = code; return this; },
        json(body) { this.body = body; return this; },
      };
      await handler({ params: { id: 'request' }, user: { id, role } }, res);
      assert.equal(res.statusCode, expectedStatus, `${role}: ${JSON.stringify(res.body)}`);
      assert.deepEqual(calls.at(-1), ['request', isAdmin, id, isMayor]);
      if (expectedStatus === 200) assert.equal(res.body.id, 'request');
    }
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
});
