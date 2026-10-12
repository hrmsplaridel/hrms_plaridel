const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

for (const scenario of [
  { actor: 'admin', expected: 403 },
  { actor: 'super_admin', expected: 201 },
  { actor: 'super_admin', duplicate: true, expected: 409 },
]) {
  test(`Mayor creation: ${JSON.stringify(scenario)}`, async () => {
    const calls = [];
    const client = {
      query: async (sql, params) => {
        calls.push({ sql, params });
        if (sql.includes('nextval')) return { rows: [{ n: 123 }] };
        if (sql.includes('INSERT INTO users')) {
          if (scenario.duplicate) throw Object.assign(new Error('duplicate'), { code: '23505', constraint: 'users_single_active_mayor_idx' });
          return { rows: [{ id: 'new-user', email: 'mayor@example.test', role: params[2], is_active: true, full_name: 'New Mayor' }] };
        }
        return { rows: [], rowCount: 0 };
      }, release() {},
    };
    const restore = withMockedModule('../src/config/db', { pool: { connect: async () => client } });
    const mail = withMockedModule('../src/utils/smtpMail', { isSmtpConfigured: () => false });
    clearModule('../src/routes/employees');
    try {
      const router = require('../src/routes/employees');
      const handler = router.stack.find(l => l.route?.path === '/' && l.route.methods.post).route.stack.at(-1).handle;
      const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json(body) { this.body = body; } };
      await handler({ user: { id: 'creator', role: scenario.actor }, body: {
        email: 'mayor@example.test', role: 'mayor', first_name: 'New', last_name: 'Mayor', full_name: 'New Mayor', date_hired: '2026-10-08',
      } }, res);
      assert.equal(res.statusCode, scenario.expected);
      if (scenario.expected === 403) assert.equal(calls.length, 0);
      if (scenario.expected === 201) {
        assert.equal(res.body.role, 'mayor');
        assert.equal(calls.at(-1).sql, 'COMMIT');
        assert.ok(calls.some(c => c.sql.includes('INSERT INTO audit_logs')));
      }
      if (scenario.duplicate) {
        assert.equal(calls.at(-1).sql, 'ROLLBACK');
        assert.match(res.body.error, /active Mayor/);
      }
    } finally { clearModule('../src/routes/employees'); mail(); restore(); }
  });
}

test('fresh and upgraded databases enforce one active Mayor while allowing inactive history', () => {
  for (const filename of ['scripts/init-schema.sql', 'scripts/migrations/20261008_single_active_mayor.sql']) {
    const sql = fs.readFileSync(path.join(__dirname, '..', filename), 'utf8');
    assert.match(sql, /CREATE UNIQUE INDEX IF NOT EXISTS users_single_active_mayor_idx\s+ON users\s*\(role\)\s+WHERE role = 'mayor' AND is_active = true/i);
  }
});

test('Employee Profiles can filter Mayor accounts', async () => {
  const queries = [];
  const restore = withMockedModule('../src/config/db', { pool: {
    query: async (sql, params = []) => {
      queries.push({ sql, params });
      return { rows: sql.includes('COUNT(*)') ? [{ total: 0 }] : [] };
    },
  } });
  clearModule('../src/routes/employees');
  try {
    const handler = require('../src/routes/employees').stack.find(l => l.route?.path === '/' && l.route.methods.get).route.stack.at(-1).handle;
    const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json(body) { this.body = body; } };
    await handler({ user: { id: 'admin', role: 'admin' }, query: { role: 'Mayor', status: 'All' } }, res);
    assert.equal(res.statusCode, 200);
    assert.ok(queries.some(q => q.params.includes('mayor') && /u\.role = \$\d+/.test(q.sql)));
  } finally { clearModule('../src/routes/employees'); restore(); }
});
