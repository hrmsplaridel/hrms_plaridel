const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('form credits are limited to reviewers of that request and VL/SL', async () => {
  const seen = [];
  const query = async (sql, params = []) => {
    const statement = String(sql).replace(/\s+/g, ' ').trim();
    if (statement.includes('FROM leave_requests lr') && statement.includes('AS employee_id')) {
      seen.push({ statement, params });
      if (params[0] === 'missing') return { rows: [] };
      return { rows: [{ employee_id: 'employee', can_view: ['employee', 'head', 'former-head', 'hr'].includes(params[2]) || params[1] === true }] };
    }
    if (statement.includes('FROM leave_balances lb')) {
      seen.push({ statement, params });
      return { rows: [
        { id: 'vl', user_id: 'employee', leave_type: 'vacationLeave', earned_days: '6.25', used_days: '3', pending_days: '0', adjusted_days: '0' },
        { id: 'sl', user_id: 'employee', leave_type: 'sickLeave', earned_days: '21.25', used_days: '2', pending_days: '0', adjusted_days: '0' },
      ] };
    }
    return { rows: [] };
  };
  const pool = { query, connect: async () => ({ query, release() {} }) };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  clearModule('../src/routes/leaveRoutes');
  try {
    const router = require('../src/routes/leaveRoutes');
    const handler = (path) => router.stack.find(
      (entry) => entry.route?.path === path && entry.route.methods.get
    ).route.stack.at(-1).handle;
    const run = async (id, userId, role = 'employee') => {
      const res = { statusCode: 200, body: null,
        status(code) { this.statusCode = code; return this; },
        json(body) { this.body = body; return this; } };
      await handler('/:id/form-credits')({ params: { id }, user: { id: userId, role } }, res);
      return res;
    };
    assert.equal((await run('missing', 'head')).statusCode, 404);
    const denied = await run('request', 'stranger');
    assert.equal(denied.statusCode, 403);
    assert.equal(seen.filter((item) => item.statement.includes('FROM leave_balances lb')).length, 0);
    for (const [userId, role] of [['employee', 'employee'], ['head', 'employee'], ['former-head', 'employee'], ['hr', 'hr']]) {
      const allowed = await run('request', userId, role);
      assert.equal(allowed.statusCode, 200);
      assert.deepEqual(allowed.body.map((row) => row.leave_type), ['vacationLeave', 'sickLeave']);
      assert.equal(allowed.body[0].earned_days, 6.25);
    }
    assert.match(seen[0].statement, /lr\.status = 'pending_department_head'/);
    assert.match(seen[0].statement, /lr\.assigned_department_head_id = \$3::uuid/);
    assert.match(seen[0].statement, /h\.acted_by = \$3::uuid/);
    assert.match(seen[0].statement, /department_head_approved/);
    assert.match(seen.at(-1).statement, /lb\.leave_type IN \('vacationLeave', 'sickLeave'\)/);
    assert.deepEqual(seen.at(-1).params, ['employee']);

    const general = { statusCode: 200,
      status(code) { this.statusCode = code; return this; }, json() { return this; } };
    await handler('/balances/:userId')({
      params: { userId: 'employee' }, user: { id: 'head', role: 'employee' },
    }, general);
    assert.equal(general.statusCode, 403);
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
});
