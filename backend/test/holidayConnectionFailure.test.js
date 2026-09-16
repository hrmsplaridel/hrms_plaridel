'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const routePath = '../src/routes/holidays';

function routeHandler(router, method, path) {
  const layer = router.stack.find(
    (entry) => entry.route?.path === path && entry.route.methods[method]
  );
  assert.ok(layer, `${method.toUpperCase()} ${path} route is registered`);
  return layer.route.stack.at(-1).handle;
}

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
    send(payload) { this.body = payload; return this; },
  };
}

async function withHolidayRoute(pool, callback) {
  const restores = [
    withMockedModule('../src/config/db', { pool }),
    withMockedModule('../src/services/dtrMonthEndReconciliation', {
      enqueueHolidayReconciliation: async () => {},
    }),
    withMockedModule('../src/websockets/biometricStream', {
      broadcastBiometricUpdate: () => {},
    }),
  ];
  clearModule(routePath);
  const originalError = console.error;
  console.error = () => {};
  try {
    await callback(require(routePath));
  } finally {
    console.error = originalError;
    clearModule(routePath);
    restores.reverse().forEach((restore) => restore());
  }
}

const validCreateBody = {
  date_from: '2026-09-09',
  date_to: '2026-09-09',
  name: 'Connection test holiday',
  holiday_type: 'regular',
  is_active: true,
  recurring: false,
  coverage: 'whole_day',
};

test('holiday mutations return 503 when database acquisition fails', async (t) => {
  const cases = [
    { name: 'default import', method: 'post', path: '/ph-defaults/import', body: { year: 2026 } },
    { name: 'create', method: 'post', path: '/', body: validCreateBody },
    { name: 'update', method: 'put', path: '/:id', body: { name: 'Updated holiday' } },
    { name: 'delete', method: 'delete', path: '/:id', body: {} },
  ];

  for (const item of cases) {
    await t.test(item.name, async () => {
      await withHolidayRoute(
        { connect: async () => { throw new Error('connection refused'); } },
        async (router) => {
          const res = responseRecorder();
          await routeHandler(router, item.method, item.path)(
            { body: item.body, query: {}, params: { id: 'holiday-id' } },
            res
          );
          assert.equal(res.statusCode, 503);
          assert.deepEqual(res.body, { error: 'Database is temporarily unavailable.' });
        }
      );
    });
  }
});

test('holiday creation rolls back and releases after a query failure', async () => {
  const events = [];
  const client = {
    async query(sql) {
      const command = String(sql).trim();
      if (command === 'BEGIN' || command === 'ROLLBACK') {
        events.push(command);
        return { rows: [], rowCount: 0 };
      }
      throw new Error('query failed');
    },
    release() { events.push('RELEASE'); },
  };

  await withHolidayRoute({ connect: async () => client }, async (router) => {
    const res = responseRecorder();
    await routeHandler(router, 'post', '/')(
      { body: validCreateBody, query: {}, params: {} },
      res
    );
    assert.equal(res.statusCode, 500);
    assert.deepEqual(res.body, { error: 'Failed to create holiday' });
    assert.deepEqual(events, ['BEGIN', 'ROLLBACK', 'RELEASE']);
  });
});
