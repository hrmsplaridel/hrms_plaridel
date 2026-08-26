const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const EMPLOYEE_ID = '00000000-0000-4000-8000-000000000401';
const SECOND_EMPLOYEE_ID = '00000000-0000-4000-8000-000000000405';
const ASSIGNMENT_ID = '00000000-0000-4000-8000-000000000402';
const DEPARTMENT_ID = '00000000-0000-4000-8000-000000000403';
const SHIFT_ID = '00000000-0000-4000-8000-000000000404';

function response() {
  return {
    statusCode: 200,
    payload: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.payload = body; return this; },
  };
}

function route(router, method, path) {
  const layer = router.stack.find(
    (item) => item.route?.path === path && item.route.methods?.[method]
  );
  assert.ok(layer, `${method.toUpperCase()} ${path} route not found`);
  return layer.route.stack.map((item) => item.handle);
}

test('bulk DTR report returns batched records and assignment timelines', async () => {
  const queries = [];
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query(sql, params = []) {
        const text = String(sql);
        queries.push({ sql: text, params });
        if (/SELECT id, full_name\s+FROM users\s+WHERE id = ANY/i.test(text)) {
          return {
            rowCount: 2,
            rows: [
              { id: EMPLOYEE_ID, full_name: 'Report Employee' },
              { id: SECOND_EMPLOYEE_ID, full_name: 'Second Employee' },
            ],
          };
        }
        if (
          /FROM assignments a/i.test(text) &&
          /LEFT JOIN departments d ON d\.id = a\.department_id/i.test(text)
        ) {
          return {
            rowCount: 2,
            rows: [EMPLOYEE_ID, SECOND_EMPLOYEE_ID].map((employeeId, index) => ({
              id: index === 0
                ? ASSIGNMENT_ID
                : '00000000-0000-4000-8000-000000000406',
              employee_id: employeeId,
              department_id: DEPARTMENT_ID,
              department_name: 'Human Resources',
              position_name: 'Staff',
              shift_id: SHIFT_ID,
              shift_name: 'Regular',
              effective_from: '2026-01-01',
              effective_to: null,
              start_time: '08:00:00',
              end_time: '17:00:00',
              break_end: '13:00:00',
              punch_mode: 'full_day',
              grace_period_minutes: 0,
              working_days: [1, 2, 3, 4, 5],
            })),
          };
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
  const handlers = route(router, 'post', '/bulk-report');
  const res = response();

  await handlers[handlers.length - 1](
    {
      user: { id: '00000000-0000-4000-8000-000000000001', role: 'admin' },
      body: {
        employee_ids: [EMPLOYEE_ID, SECOND_EMPLOYEE_ID],
        start_date: '2026-06-01',
        end_date: '2026-06-01',
      },
    },
    res
  );

  assert.equal(res.statusCode, 200);
  assert.equal(res.payload.batch_limit, 100);
  assert.equal(res.payload.errors.length, 0);
  assert.equal(res.payload.employees.length, 2);
  assert.equal(res.payload.employees[0].employee_id, EMPLOYEE_ID);
  assert.equal(res.payload.employees[0].records.length, 1);
  assert.equal(res.payload.employees[0].records[0].status, 'absent');
  assert.equal(res.payload.employees[0].assignments.length, 1);
  assert.equal(
    res.payload.employees[0].assignments[0].department_name,
    'Human Resources'
  );
  assert.equal(res.payload.employees[1].employee_id, SECOND_EMPLOYEE_ID);
  assert.equal(res.payload.employees[1].records[0].status, 'absent');

  const dtrQueries = queries.filter(({ sql }) => /FROM dtr_daily_summary d/i.test(sql));
  const assignmentQueries = queries.filter(
    ({ sql }) =>
      /FROM assignments a/i.test(sql) &&
      /LEFT JOIN departments d ON d\.id = a\.department_id/i.test(sql)
  );
  assert.equal(dtrQueries.length, 1);
  assert.match(dtrQueries[0].sql, /d\.employee_id = ANY\(\$\d+::uuid\[\]\)/i);
  assert.equal(assignmentQueries.length, 1);

  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});

test('bulk DTR report rejects more than 100 employees', async () => {
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query() {
        throw new Error('database should not be queried');
      },
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');
  const handlers = route(router, 'post', '/bulk-report');
  const res = response();
  const employeeIds = Array.from(
    { length: 101 },
    (_, index) => `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`
  );

  await handlers[handlers.length - 1](
    {
      user: { id: '00000000-0000-4000-8000-000000000001', role: 'admin' },
      body: {
        employee_ids: employeeIds,
        start_date: '2026-06-01',
        end_date: '2026-06-30',
      },
    },
    res
  );

  assert.equal(res.statusCode, 400);
  assert.match(res.payload.error, /at most 100 employees/i);

  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});

test('bulk DTR report keeps valid employees and reports missing employees separately', async () => {
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query(sql) {
        const text = String(sql);
        if (/SELECT id, full_name\s+FROM users\s+WHERE id = ANY/i.test(text)) {
          return {
            rowCount: 1,
            rows: [{ id: EMPLOYEE_ID, full_name: 'Available Employee' }],
          };
        }
        if (
          /FROM assignments a/i.test(text) &&
          /LEFT JOIN departments d ON d\.id = a\.department_id/i.test(text)
        ) {
          return {
            rowCount: 1,
            rows: [{
              id: ASSIGNMENT_ID,
              employee_id: EMPLOYEE_ID,
              department_id: DEPARTMENT_ID,
              department_name: 'Human Resources',
              position_name: 'Staff',
              shift_id: SHIFT_ID,
              shift_name: 'Regular',
              effective_from: '2026-01-01',
              effective_to: null,
              start_time: '08:00:00',
              end_time: '17:00:00',
              break_end: '13:00:00',
              punch_mode: 'full_day',
              grace_period_minutes: 0,
              working_days: [1, 2, 3, 4, 5],
            }],
          };
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
  const handlers = route(router, 'post', '/bulk-report');
  const res = response();

  await handlers[handlers.length - 1](
    {
      user: { id: '00000000-0000-4000-8000-000000000001', role: 'admin' },
      body: {
        employee_ids: [EMPLOYEE_ID, SECOND_EMPLOYEE_ID],
        start_date: '2026-06-01',
        end_date: '2026-06-01',
      },
    },
    res
  );

  assert.equal(res.statusCode, 200);
  assert.equal(res.payload.employees.length, 1);
  assert.equal(res.payload.employees[0].employee_id, EMPLOYEE_ID);
  assert.deepEqual(res.payload.errors, [{
    employee_id: SECOND_EMPLOYEE_ID,
    error: 'Employee was not found',
  }]);

  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});
