const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const primary = require('../src/services/assignmentTransition');
const additional = require('../src/services/additionalPositionTransition');
const policy = require('../src/services/employeePolicyAssignment');
const access = require('../src/services/assignmentAccess');

const ID = '11111111-1111-4111-8111-111111111111';
const routes = [
  { name: 'primary create', file: '../src/routes/assignments', method: 'post', path: '/', create: true },
  { name: 'primary update', file: '../src/routes/assignments', method: 'put', path: '/:id' },
  { name: 'policy upsert', file: '../src/routes/policyAssignments', method: 'post', path: '/employee-upsert', create: true },
  { name: 'additional create', file: '../src/routes/employeeOtherPositions', method: 'post', path: '/', create: true },
  { name: 'additional update', file: '../src/routes/employeeOtherPositions', method: 'put', path: '/:id' },
];

async function invoke(route, changes, query = {}) {
  const calls = { sql: [], transitions: [], tracking: [], connections: 0 };
  const before = { id: ID, employee_id: ID, effective_from: '2026-01-01', effective_to: null, is_active: true };
  const client = {
    query: async (sql) => {
      calls.sql.push(sql);
      return { rowCount: 1, rows: sql.includes('FROM assignments') ? [before] : [] };
    },
    release() {},
  };
  const boundary = ErrorType => async (_db, input) => {
    calls.transitions.push(input);
    throw new ErrorType('Validated transition boundary', 418);
  };
  const restores = [
    withMockedModule('../src/config/db', { pool: {
      connect: async () => { calls.connections++; return client; }, query: client.query,
    } }),
    withMockedModule('../src/services/assignmentTransition', {
      ...primary,
      createAssignmentTransition: boundary(primary.AssignmentTransitionError),
      updateAssignmentTransition: boundary(primary.AssignmentTransitionError),
    }),
    withMockedModule('../src/services/additionalPositionTransition', {
      ...additional,
      createAdditionalPositionTransition: boundary(additional.AdditionalPositionTransitionError),
      updateAdditionalPositionTransition: boundary(additional.AdditionalPositionTransitionError),
    }),
    withMockedModule('../src/services/employeePolicyAssignment', {
      ...policy, upsertEmployeePolicyAssignment: boundary(policy.EmployeePolicyAssignmentError),
    }),
    withMockedModule('../src/services/employeeAttendanceTracking', {
      updateEmployeeTrackingStart: async (...args) => { calls.tracking.push(args); return { changed: false }; },
    }),
    withMockedModule('../src/services/assignmentAccess', {
      ...access, resolveAssignmentEmployeeAccess: () => ({ allowed: true, employeeId: ID }),
      filterAssignmentRowsForAccess: async (_db, _access, rows) => rows,
      assignmentAccessDeniedForRows: () => false,
    }),
  ];
  clearModule(route.file);
  try {
    const router = require(route.file);
    const handler = router.stack.find(l => l.route?.path === route.path && l.route.methods[route.method]).route.stack.at(-1).handle;
    const res = {
      code: 200,
      status(code) { this.code = code; return this; },
      json(body) { this.body = body; return this; },
    };
    const body = route.create
      ? { employee_id: ID, attendance_policy_id: ID, effective_from: '2026-01-01', ...changes }
      : { remarks: 'Updated note', ...changes };
    await handler({ params: { id: ID }, user: { id: ID, role: 'admin' }, body, query }, res);
    return { res, calls };
  } finally {
    clearModule(route.file);
    restores.reverse().forEach(restore => restore());
  }
}

const invalidDates = [
  '2026-02-30', '2025-02-29', '2026-04-31', '2026-00-10', '2026-13-01',
  '0000-01-01', '2026-01-00', '2026-01-01T00:00:00Z', '01/01/2026',
  ' 2026-01-01 ', ['2026-01-01'], 1767225600000, true, {},
];

for (const route of routes) {
  for (const value of ['true', 'false', 0, 1, null, [], {}, '']) {
    test(`${route.name} rejects nonboolean active ${JSON.stringify(value)} before DB access`, async () => {
      const { res, calls } = await invoke(route, { is_active: value });
      assert.equal(res.code, 400);
      assert.match(res.body.error, /is_active.*boolean/i);
      assert.deepEqual(calls, { sql: [], transitions: [], tracking: [], connections: 0 });
    });
  }
  for (const field of ['effective_from', 'effective_to']) {
    for (const value of invalidDates) {
      test(`${route.name} rejects ${field}=${JSON.stringify(value)} before DB access`, async () => {
        const { res, calls } = await invoke(route, { [field]: value });
        assert.equal(res.code, 400);
        assert.match(res.body.error, new RegExp(field));
        assert.deepEqual(calls, { sql: [], transitions: [], tracking: [], connections: 0 });
      });
    }
  }
  for (const value of [true, false]) {
    test(`${route.name} preserves boolean ${value} and a real leap date`, async () => {
      const { res, calls } = await invoke(route, {
        is_active: value, effective_from: '2024-02-29', effective_to: '2026-12-31',
        change_reason: 'HR verified the assignment correction',
      });
      assert.equal(res.code, 418, 'Valid input must reach the mocked transition unchanged');
      const input = calls.transitions[0].changes || calls.transitions[0];
      assert.equal(input.isActive, value);
      assert.equal(input.effectiveFrom, '2024-02-29');
      assert.equal(input.effectiveTo, '2026-12-31');
    });
  }
  for (const value of [null, '']) {
    test(`${route.name} preserves an explicitly open-ended end date ${JSON.stringify(value)}`, async () => {
      const { res, calls } = await invoke(route, { effective_to: value });
      assert.equal(res.code, 418);
      const input = calls.transitions[0].changes || calls.transitions[0];
      assert.ok(input.effectiveTo === null || input.effectiveTo === '', 'Open-ended date stays open-ended');
    });
  }
  test(`${route.name} preserves omitted activation and optional dates`, async () => {
    const { res, calls } = await invoke(route, {});
    assert.equal(res.code, 418);
    const input = calls.transitions[0].changes || calls.transitions[0];
    assert.equal(input.isActive, route.create ? true : undefined);
    assert.equal(input.effectiveFrom, route.create ? '2026-01-01' : undefined);
  });
}

test('real primary-assignment deactivation still requires a reason before transition', async () => {
  const { res, calls } = await invoke(routes[1], { is_active: false });
  assert.equal(res.code, 400);
  assert.match(res.body.error, /reason.*required/i);
  assert.deepEqual(calls.transitions, []);
  assert.equal(calls.sql.at(-1), 'ROLLBACK');
});

for (const field of ['start_date', 'end_date']) {
  for (const value of invalidDates) {
    test(`assignment history rejects invalid ${field}=${JSON.stringify(value)} before querying`, async () => {
      const { res, calls } = await invoke({ ...routes[0], method: 'get', path: '/' }, {}, {
        employee_id: ID, start_date: '2026-01-01', end_date: '2026-12-31', [field]: value,
      });
      assert.equal(res.code, 400);
      assert.match(res.body.error, /YYYY-MM-DD/);
      assert.deepEqual(calls.sql, []);
    });
  }
}
