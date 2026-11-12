const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

test('retired Mayor seed endpoint cannot create or reset accounts', async (t) => {
  const queries = [];
  const routePath = '../src/routes/mayorEndorsements';
  const restores = [
    withMockedModule('../src/config/db', {
      pool: {
        async query(sql) {
          queries.push(sql);
          return { rows: [], rowCount: 1 };
        },
      },
    }),
    withMockedModule('../src/middleware/auth', {
      authMiddleware(req, res, next) {
        if (!req.user) return res.status(401).json({ error: 'Authentication required' });
        next();
      },
    }),
  ];
  clearModule(routePath);

  const app = express();
  app.use((req, _res, next) => {
    const role = req.headers['x-test-role'];
    if (role) req.user = { id: 'test-actor', role };
    next();
  });
  app.use('/api/mayor/endorsements', require(routePath));
  app.use((_req, res) => res.status(404).json({ error: 'Not found' }));
  const server = app.listen(0, '127.0.0.1');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
    clearModule(routePath);
    restores.reverse().forEach((restore) => restore());
  });
  await new Promise((resolve, reject) => {
    server.once('listening', resolve);
    server.once('error', reject);
  });

  for (const role of ['admin', 'hr', 'super_admin', 'mayor', 'mayor_office_staff', 'employee', null]) {
    await t.test(`rejects ${role || 'unauthenticated'} requests without database access`, async () => {
      queries.length = 0;
      const response = await fetch(
        `http://127.0.0.1:${server.address().port}/api/mayor/endorsements/seed-account`,
        { method: 'POST', headers: role ? { 'x-test-role': role } : {} },
      );
      await response.text();
      assert.equal(response.status, 404);
      assert.deepEqual(queries, [], 'The retired endpoint must never touch account records');
    });
  }
});
