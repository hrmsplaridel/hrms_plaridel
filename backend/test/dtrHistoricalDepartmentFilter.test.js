const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const DEPARTMENT_ID = '00000000-0000-4000-8000-000000000201';

function response() {
  return {
    statusCode: 200,
    payload: null,
    headers: {},
    status(code) { this.statusCode = code; return this; },
    json(body) { this.payload = body; return this; },
    send(body) { this.payload = body; return this; },
    setHeader(name, value) { this.headers[name] = value; },
  };
}

function route(router, method, path) {
  const layer = router.stack.find(
    (item) => item.route?.path === path && item.route.methods?.[method]
  );
  assert.ok(layer, `${method.toUpperCase()} ${path} route not found`);
  return layer.route.stack.map((item) => item.handle);
}

test('DTR department filter resolves the latest assignment on each attendance date', async () => {
  const queries = [];
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query(sql, params = []) {
        const text = String(sql);
        queries.push({ sql: text, params });
        if (/SELECT coverage FROM holidays LIMIT 1/i.test(text)) {
          return { rowCount: 0, rows: [] };
        }
        return { rowCount: 0, rows: [] };
      },
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');
  const handlers = route(router, 'get', '/');
  const res = response();

  await handlers[handlers.length - 1](
    {
      user: { id: '00000000-0000-4000-8000-000000000001', role: 'admin' },
      query: { department_id: DEPARTMENT_ID },
    },
    res
  );

  assert.equal(res.statusCode, 200);
  const listQuery = queries.find(({ sql }) => /FROM dtr_daily_summary d/i.test(sql));
  assert.ok(listQuery, 'DTR list query was not issued');
  assert.match(listQuery.sql, /a\.effective_from <= d\.attendance_date/i);
  assert.match(listQuery.sql, /a\.effective_to >= d\.attendance_date/i);
  assert.match(
    listQuery.sql,
    /ORDER BY a\.effective_from DESC, a\.created_at DESC, a\.id DESC/i
  );
  assert.match(listQuery.sql, /\) = \$1::uuid/i);
  assert.equal(listQuery.params[0], DEPARTMENT_ID);

  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});

test('employee department filter uses authoritative assignments across the selected month', async () => {
  const queries = [];
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query(sql, params = []) {
        const text = String(sql);
        queries.push({ sql: text, params });
        return { rowCount: 0, rows: [] };
      },
    },
  });
  clearModule('../src/routes/employees');
  const router = require('../src/routes/employees');
  const handlers = route(router, 'get', '/');
  const res = response();

  await handlers[handlers.length - 1](
    {
      user: { id: '00000000-0000-4000-8000-000000000001', role: 'admin' },
      query: {
        status: 'Active',
        role: 'User',
        department_id: DEPARTMENT_ID,
        start_date: '2026-06-01',
        end_date: '2026-06-30',
      },
    },
    res
  );

  assert.equal(res.statusCode, 200);
  const listQuery = queries.find(
    ({ sql }) => /SELECT u\.id, u\.employee_number/i.test(sql)
  );
  assert.ok(listQuery, 'employee list query was not issued');
  assert.match(listQuery.sql, /FROM generate_series/i);
  assert.match(listQuery.sql, /historical_assignment\.department_id = \$2::uuid/i);
  assert.match(
    listQuery.sql,
    /ORDER BY a\.effective_from DESC, a\.created_at DESC, a\.id DESC/i
  );
  assert.equal(listQuery.params[0], 'employee');
  assert.equal(listQuery.params[1], DEPARTMENT_ID);
  assert.equal(listQuery.params[2], '2026-06-01');
  assert.equal(listQuery.params[3], '2026-06-30');

  restoreDb();
  clearModule('../src/routes/employees');
});
