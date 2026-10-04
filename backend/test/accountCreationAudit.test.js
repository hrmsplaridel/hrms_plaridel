const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

for (const role of ['employee', 'admin']) {
  for (const failAudit of [false, true]) {
    test(`creating ${role}: ${failAudit ? 'audit failure rolls back without email' : 'audits creator and role before commit'}`, async (t) => {
      const actorId = '11111111-1111-4111-8111-111111111111';
      const targetId = '22222222-2222-4222-8222-222222222222';
      const calls = [];
      let releases = 0, emails = 0;
      const client = {
        async query(sql, params) {
          calls.push({ sql, params });
          if (sql.includes('nextval')) return { rows: [{ n: 123 }] };
          if (sql.includes('SELECT 1 FROM users')) return { rows: [], rowCount: 0 };
          if (sql.includes('INSERT INTO users')) return { rows: [{ id: targetId, role, email: 'new@test.local', full_name: 'New Account', is_active: true }] };
          if (sql.includes('INSERT INTO audit_logs') && failAudit) throw new Error('audit write failed');
          return { rows: [], rowCount: 1 };
        },
        release() { releases++; },
      };
      const restores = [
        withMockedModule('../src/config/db', { pool: { connect: async () => client, query: async () => { throw new Error('Must use transaction client'); } } }),
        withMockedModule('../src/utils/smtpMail', { isSmtpConfigured: () => true, sendSmtpMail: async () => {
          assert.equal(calls.at(-1).sql, 'COMMIT');
          emails++;
        } }),
      ];
      t.mock.method(console, 'error', () => {});
      const routePath = '../src/routes/employees';
      clearModule(routePath);
      try {
        const handler = require(routePath).stack.find(e => e.route?.path === '/' && e.route.methods.post).route.stack.at(-1).handle;
        const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json(body) { this.body = body; } };
        await handler({ user: { id: actorId, role: 'super_admin' }, body: {
          email: 'new@test.local', password: 'SecretExample123!', role,
          first_name: 'New', last_name: 'Account', full_name: 'New Account', date_hired: '2026-01-01',
        } }, res);
        const audits = calls.filter(c => c.sql.includes('INSERT INTO audit_logs'));
        assert.equal(audits.length, 1);
        assert.match(audits[0].sql, /'account_created', 'user'/);
        assert.deepEqual(audits[0].params, [actorId, targetId, JSON.stringify({ role })]);
        assert.equal(res.statusCode, failAudit ? 500 : 201);
        assert.equal(calls.at(-1).sql, failAudit ? 'ROLLBACK' : 'COMMIT');
        assert.equal(calls.some(c => c.sql === 'COMMIT'), !failAudit);
        assert.equal(emails, failAudit ? 0 : 1);
        assert.equal(releases, 1);
      } finally {
        clearModule(routePath);
        restores.reverse().forEach(restore => restore());
      }
    });
  }
}
