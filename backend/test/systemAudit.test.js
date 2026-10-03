const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

function response() {
  return {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('system audit is super-admin-only and returns bounded filtered pages', async () => {
  const queries = [];
  const restore = withMockedModule('../src/config/db', {
    pool: {
      async query(sql, params) {
        queries.push({ sql, params });
        return sql.includes('COUNT(*)')
          ? { rows: [{ total: 1 }] }
          : { rows: [{ id: 'entry-1', action: 'dtr_time_entry_adjusted' }] };
      },
    },
  });
  const path = '../src/routes/systemAudit';
  clearModule(path);
  try {
    const router = require(path);
    const route = router.stack.find(entry => entry.route?.methods.get).route;
    const denied = response();
    route.stack[1].handle({ user: { role: 'employee' } }, denied, () => {});
    assert.equal(denied.statusCode, 403);
    const adminDenied = response();
    route.stack[1].handle({ user: { role: 'admin' } }, adminDenied, () => {});
    assert.equal(adminDenied.statusCode, 403);

    const allowed = response();
    route.stack[1].handle({ user: { role: 'super_admin' } }, allowed, () => {});
    assert.equal(allowed.statusCode, 200);
    await route.stack[2].handle({ user: { id: 'admin-id' }, query: { page: '2', limit: '25', action: 'dtr', actor: 'Earl' } }, allowed);
    assert.equal(allowed.body.total, 1);
    assert.equal(allowed.body.entries[0].action, 'dtr_time_entry_adjusted');
    assert.match(queries[0].sql, /audit_log_viewed/);
    assert.deepEqual(queries[2].params, ['dtr', 'Earl', 25, 25]);

    const invalid = response();
    await route.stack[2].handle({ query: { limit: '1000' } }, invalid);
    assert.equal(invalid.statusCode, 400);
    assert.equal(queries.length, 3);
  } finally {
    clearModule(path);
    restore();
  }
});
