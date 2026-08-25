const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const EMPLOYEE_ID = '00000000-0000-4000-8000-000000000501';

function response() {
  return {
    statusCode: 200,
    payload: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.payload = body;
      return this;
    },
  };
}

function route(router, method, path) {
  const layer = router.stack.find(
    (item) => item.route?.path === path && item.route.methods?.[method]
  );
  assert.ok(layer, `${method.toUpperCase()} ${path} route not found`);
  return layer.route.stack.map((item) => item.handle);
}

test('report years return the complete historical range', async () => {
  const queries = [];
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query(sql, params) {
        queries.push({ sql: String(sql), params });
        return {
          rows: [{ min_year: 2018, max_year: 2026, current_year: 2026 }],
        };
      },
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');
  const handlers = route(router, 'get', '/report-years');
  const res = response();

  await handlers[handlers.length - 1](
    { user: { id: EMPLOYEE_ID, role: 'admin' }, query: {} },
    res
  );

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.payload.years, [
    2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026,
  ]);
  assert.equal(queries[0].params[0], null);

  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});

test('employee report years are scoped to the authenticated account', async () => {
  let queryParams;
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query(_sql, params) {
        queryParams = params;
        return {
          rows: [{ min_year: 2024, max_year: 2026, current_year: 2026 }],
        };
      },
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');
  const handlers = route(router, 'get', '/report-years');
  const res = response();

  await handlers[handlers.length - 1](
    {
      user: { id: EMPLOYEE_ID, role: 'employee' },
      query: { employee_id: '00000000-0000-4000-8000-000000000999' },
    },
    res
  );

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.payload.years, [2024, 2025, 2026]);
  assert.equal(queryParams[0], EMPLOYEE_ID);

  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});
