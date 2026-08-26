const test = require('node:test');
const assert = require('node:assert/strict');

const {
  AssignmentTransitionError,
  validateAssignmentSelection,
  createAssignmentTransition,
  updateAssignmentTransition,
  endEmployeeAssignmentsFromDate,
} = require('../src/services/assignmentTransition');

const IDS = {
  employee: '11111111-1111-4111-8111-111111111111',
  current: '22222222-2222-4222-8222-222222222222',
  scheduled: '33333333-3333-4333-8333-333333333333',
  department: '44444444-4444-4444-8444-444444444444',
  position: '55555555-5555-4555-8555-555555555555',
  shift: '66666666-6666-4666-8666-666666666666',
};

function assignmentPayload(overrides = {}) {
  return {
    employeeId: IDS.employee,
    departmentId: IDS.department,
    positionId: IDS.position,
    shiftId: IDS.shift,
    effectiveFrom: '2026-09-01',
    effectiveTo: null,
    isActive: true,
    ...overrides,
  };
}

function validSelectionRow(overrides = {}) {
  return {
    employee_exists: true,
    employee_is_active: true,
    employee_status: 'active',
    department_exists: true,
    department_is_active: true,
    position_exists: true,
    position_is_active: true,
    position_department_id: IDS.department,
    shift_exists: true,
    shift_is_active: true,
    ...overrides,
  };
}

test('primary assignment selection requires department, position, and shift', async () => {
  let queried = false;
  await assert.rejects(
    validateAssignmentSelection(
      { query: async () => { queried = true; } },
      {
        employeeId: IDS.employee,
        departmentId: IDS.department,
        positionId: null,
        shiftId: IDS.shift,
      }
    ),
    /Position is required/
  );
  assert.equal(queried, false);
});

test('assignment selection rejects a position from another department', async () => {
  const db = {
    query: async () => ({
      rowCount: 1,
      rows: [validSelectionRow({ position_department_id: IDS.current })],
    }),
  };
  await assert.rejects(
    validateAssignmentSelection(db, assignmentPayload()),
    /Selected position does not belong to the selected department/
  );
});

test('active assignment selection rejects inactive organizational records', async () => {
  const db = {
    query: async () => ({
      rowCount: 1,
      rows: [validSelectionRow({ shift_is_active: false })],
    }),
  };
  await assert.rejects(
    validateAssignmentSelection(db, assignmentPayload()),
    (error) =>
      error instanceof AssignmentTransitionError &&
      error.statusCode === 409 &&
      error.message === 'Selected shift is inactive'
  );
});

test('future transfer closes the current assignment on the previous day', async () => {
  const calls = [];
  const db = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.includes('AS employee_exists')) {
        return { rowCount: 1, rows: [validSelectionRow()] };
      }
      if (sql.includes('effective_from < $2::date')) {
        return {
          rowCount: 1,
          rows: [{
            id: IDS.current,
            effective_from: '2026-01-01',
            effective_to: null,
          }],
        };
      }
      if (sql.startsWith('UPDATE assignments')) {
        return {
          rowCount: 1,
          rows: [{ id: IDS.current, effective_to: '2026-08-31', is_active: true }],
        };
      }
      if (sql.includes("COALESCE($3::date, 'infinity'::date)")) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('INSERT INTO assignments')) {
        return {
          rowCount: 1,
          rows: [{ id: IDS.scheduled, effective_from: '2026-09-01', is_active: true }],
        };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    },
  };

  const created = await createAssignmentTransition(db, assignmentPayload());
  assert.equal(created.id, IDS.scheduled);
  const predecessorUpdate = calls.find((call) =>
    call.sql.startsWith('UPDATE assignments')
  );
  assert.equal(predecessorUpdate.params[1], '2026-08-31');
  assert.equal(predecessorUpdate.sql.includes('is_active = false'), false);
});

test('same-day or otherwise overlapping assignment is rejected', async () => {
  const calls = [];
  const db = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.includes('AS employee_exists')) {
        return { rowCount: 1, rows: [validSelectionRow()] };
      }
      if (sql.includes('effective_from < $2::date')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes("COALESCE($3::date, 'infinity'::date)")) {
        return {
          rowCount: 1,
          rows: [{
            id: IDS.current,
            effective_from: '2026-09-01',
            effective_to: null,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    },
  };

  await assert.rejects(
    createAssignmentTransition(db, assignmentPayload()),
    (error) =>
      error instanceof AssignmentTransitionError &&
      error.statusCode === 409 &&
      error.message.includes('overlap')
  );
  assert.equal(calls.some((call) => call.sql.includes('INSERT INTO assignments')), false);
});

test('updating an assignment rejects coverage that reaches a scheduled assignment', async () => {
  const db = {
    async query(sql) {
      if (sql.includes('WHERE id = $1::uuid') && sql.includes('FOR UPDATE')) {
        return {
          rowCount: 1,
          rows: [{
            id: IDS.current,
            employee_id: IDS.employee,
            department_id: IDS.department,
            position_id: IDS.position,
            shift_id: IDS.shift,
            effective_from: '2026-01-01',
            effective_to: '2026-08-31',
            is_active: true,
            remarks: null,
          }],
        };
      }
      if (sql.includes('AS employee_exists')) {
        return { rowCount: 1, rows: [validSelectionRow()] };
      }
      if (sql.includes('effective_from < $2::date')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes("COALESCE($3::date, 'infinity'::date)")) {
        return {
          rowCount: 1,
          rows: [{
            id: IDS.scheduled,
            effective_from: '2026-09-01',
            effective_to: null,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    },
  };

  await assert.rejects(
    updateAssignmentTransition(db, {
      assignmentId: IDS.current,
      changes: { effectiveTo: '2026-09-10' },
    }),
    (error) =>
      error instanceof AssignmentTransitionError && error.statusCode === 409
  );
});

test('clearing setup cancels future rows and ends current coverage the previous day', async () => {
  const calls = [];
  const db = {
    async query(sql, params) {
      calls.push({ sql, params });
      return { rowCount: 1, rows: [] };
    },
  };

  await endEmployeeAssignmentsFromDate(db, {
    employeeId: IDS.employee,
    effectiveFrom: '2026-09-01',
  });

  assert.equal(calls.length, 3);
  assert.equal(calls[1].sql.includes('is_active = false'), true);
  assert.equal(calls[2].params[2], '2026-08-31');
});
