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

test('audit query can hide page views and resolves the affected user', async () => {
  const queries = [];
  const restore = withMockedModule('../src/config/db', {
    pool: { async query(sql, params) {
      queries.push({ sql, params });
      return sql.includes('COUNT(*)') ? { rows: [{ total: 0 }] } : { rows: [] };
    } },
  });
  const path = '../src/routes/systemAudit';
  clearModule(path);
  try {
    const route = require(path).stack.find(entry => entry.route?.methods.get).route;
    await route.stack[2].handle({ user: { id: 'admin-id' }, query: { hide_views: '1' } }, response());
    assert.match(queries[1].sql, /a\.action <> 'audit_log_viewed'/);
    assert.match(queries[2].sql, /a\.target_snapshot->>'name' ELSE target\.full_name END AS target_name/);
    assert.match(queries[2].sql, /LEFT JOIN users target ON target\.id = a\.entity_id/);
    queries.length = 0;
    await route.stack[2].handle({ user: { id: 'admin-id' }, query: {} }, response());
    assert.doesNotMatch(queries[1].sql, /a\.action <> 'audit_log_viewed'/);
  } finally {
    clearModule(path);
    restore();
  }
});

test('audit date range applies to count and rows with an exclusive end', async () => {
  const queries = [];
  const restore = withMockedModule('../src/config/db', {
    pool: { async query(sql, params) {
      queries.push({ sql, params });
      return sql.includes('COUNT(*)') ? { rows: [{ total: 0 }] } : { rows: [] };
    } },
  });
  const path = '../src/routes/systemAudit';
  clearModule(path);
  try {
    const route = require(path).stack.find(entry => entry.route?.methods.get).route;
    const from = '2026-10-02T16:00:00.000Z';
    const before = '2026-10-03T16:00:00.000Z';
    await route.stack[2].handle({ user: { id: 'admin-id' }, query: { date_from: from, date_before: before, hide_views: '1' } }, response());
    assert.match(queries[1].sql, /a\.created_at >= \$1::timestamptz/);
    assert.match(queries[1].sql, /a\.created_at < \$2::timestamptz/);
    assert.match(queries[2].sql, /a\.created_at >= \$1::timestamptz/);
    assert.match(queries[2].sql, /a\.created_at < \$2::timestamptz/);
    assert.deepEqual(queries[1].params, [from, before]);
    assert.deepEqual(queries[2].params, [from, before, 50, 0]);
    const logged = JSON.parse(queries[0].params[1]);
    assert.equal(logged.date_from, from);
    assert.equal(logged.date_before, before);
    const originalCount = queries.length;
    for (const query of [
      { date_from: 'not-a-date' },
      { date_from: before, date_before: from },
      { date_from: from, date_before: from },
      { date_before: '2026-02-30T00:00:00.000Z' },
    ]) {
      const result = response();
      await route.stack[2].handle({ user: { id: 'admin-id' }, query }, result);
      assert.equal(result.statusCode, 400);
    }
    assert.equal(queries.length, originalCount);
  } finally {
    clearModule(path);
    restore();
  }
});
