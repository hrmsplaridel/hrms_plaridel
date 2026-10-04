const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

test('second stale tab cannot overwrite the first save, including first-time grants', async () => {
  let saved = null;
  let updates = 0;
  let audits = 0;
  const client = {
    async query(sql, params) {
      if (sql.includes('FROM users WHERE id')) {
        assert.match(sql, /FOR UPDATE/);
        return { rows: [{ role: 'admin' }] };
      }
      if (sql.includes('FROM dtr_admin_access WHERE')) return { rows: saved ? [saved] : [] };
      if (sql.includes('INSERT INTO dtr_admin_access')) {
        updates++;
        saved = { reports_allowed: params[1], manage_allowed: params[2], revision: `r${updates}` };
        return { rows: [{ revision: saved.revision }] };
      }
      if (sql.includes('INSERT INTO audit_logs')) audits++;
      return { rows: [] };
    },
    release() {},
  };
  const restore = withMockedModule('../src/config/db', { pool: { connect: async () => client } });
  const path = '../src/routes/dtrAccess';
  clearModule(path);
  try {
    const handler = require(path).stack.find(e => e.route?.methods.put).route.stack.at(-1).handle;
    async function save(revision, reports, manage) {
      const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json(data) { this.body = data; return this; } };
      await handler({ params: { adminId: '00000000-0000-4000-8000-000000000001' }, user: { id: 'test' },
        body: { expected_revision: revision, reports_allowed: reports, manage_allowed: manage } }, res);
      return res;
    }
    assert.equal((await save(undefined, true, false)).statusCode, 400);
    assert.equal(updates, 0);
    assert.equal((await save('none', true, false)).body.revision, 'r1');
    const stale = await save('none', false, true);
    assert.equal(stale.statusCode, 409);
    assert.equal(stale.body.code, 'DTR_ACCESS_CONFLICT');
    assert.equal(saved.reports_allowed, true);
    assert.equal(saved.manage_allowed, false);
    assert.equal(updates, 1);
    assert.equal(audits, 1);
    assert.equal((await save('r1', true, true)).body.revision, 'r2');
    assert.equal((await save('r1', false, false)).statusCode, 409);
    assert.equal(updates, 2);
  } finally { clearModule(path); restore(); }
});
