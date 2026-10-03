const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

for (const routeName of ['accountCreationAccess', 'dtrAccess']) {
  for (const scenario of ['connect failure', 'statement failure', 'rollback failure', 'success']) {
    test(`${routeName}: ${scenario} is handled and connections are released`, async (t) => {
      const queries = [];
      const releases = [];
      const failure = new Error('database unavailable');
      const rollbackFailure = new Error('rollback unavailable');
      const client = {
        async query(sql) {
          queries.push(sql);
          if (sql === 'ROLLBACK' && scenario === 'rollback failure') throw rollbackFailure;
          if (sql.includes('FROM users WHERE id')) return { rows: [{ role: 'admin' }] };
          if (sql.includes('COALESCE')) return { rows: [{ allowed: false }] };
          if (sql.includes('INSERT INTO')) {
            if (scenario !== 'success') throw failure;
            return { rows: [{ revision: 'r1' }] };
          }
          return { rows: [] };
        },
        release(error) { releases.push(error); },
      };
      const restore = withMockedModule('../src/config/db', { pool: {
        async connect() {
          if (scenario === 'connect failure') throw failure;
          return client;
        },
      } });
      const path = `../src/routes/${routeName}`;
      clearModule(path);
      t.mock.method(console, 'error', () => {});
      try {
        const handler = require(path).stack.find(e => e.route?.methods.put).route.stack.at(-1).handle;
        const res = {
          statusCode: 200,
          status(code) { this.statusCode = code; return this; },
          json(body) { this.body = body; return this; },
        };
        await assert.doesNotReject(() => handler({
          params: { adminId: '00000000-0000-4000-8000-000000000001' },
          user: { id: '00000000-0000-4000-8000-000000000002' },
          body: { allowed: true, reports_allowed: true, manage_allowed: false, expected_revision: 'none' },
        }, res));
        assert.equal(res.statusCode, scenario === 'success' ? 200 : scenario === 'connect failure' ? 503 : 500);
        if (scenario === 'connect failure') {
          assert.deepEqual(queries, []);
          assert.deepEqual(releases, []);
          assert.match(res.body.error, /temporarily unavailable/i);
        } else {
          assert.equal(releases.length, 1);
          assert.equal(releases[0], scenario === 'rollback failure' ? rollbackFailure : undefined);
          assert.equal(queries.includes('COMMIT'), scenario === 'success');
          assert.equal(queries.filter(sql => sql === 'ROLLBACK').length, scenario === 'success' ? 0 : 1);
          if (scenario !== 'success') assert.match(res.body.error, /Failed to update/);
        }
      } finally {
        clearModule(path);
        restore();
      }
    });
  }
}
