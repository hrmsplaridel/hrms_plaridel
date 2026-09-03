const test = require('node:test');
const assert = require('node:assert/strict');

const {
  EmployeeSetupValidationError,
  normalizeEmployeeSetup,
  applyEmployeeSetup,
} = require('../src/services/employeeSetupTransaction');

const IDS = {
  employee: '11111111-1111-4111-8111-111111111111',
  department: '22222222-2222-4222-8222-222222222222',
  position: '33333333-3333-4333-8333-333333333333',
  shift: '44444444-4444-4444-8444-444444444444',
  policy: '55555555-5555-4555-8555-555555555555',
};

function completePayload(overrides = {}) {
  return {
    effective_from: '2026-08-25',
    assignment: {
      department_id: IDS.department,
      position_id: IDS.position,
      shift_id: IDS.shift,
    },
    policy_assignment: {
      attendance_policy_id: IDS.policy,
    },
    ...overrides,
  };
}

test('omitted optional setup remains unassigned', () => {
  assert.equal(
    normalizeEmployeeSetup(undefined, { effectiveFrom: '2026-08-25' }),
    null
  );
});

test('selected assignment must be complete', () => {
  assert.throws(
    () =>
      normalizeEmployeeSetup({
        effective_from: '2026-08-25',
        assignment: { department_id: IDS.department },
      }),
    (error) =>
      error instanceof EmployeeSetupValidationError &&
      error.message === 'Position is required'
  );
});

test('normalizes complete assignment and policy setup', () => {
  const setup = normalizeEmployeeSetup(completePayload());
  assert.deepEqual(setup, {
    hasAssignmentChange: true,
    assignment: {
      departmentId: IDS.department,
      positionId: IDS.position,
      shiftId: IDS.shift,
    },
    hasPolicyChange: true,
    policyAssignment: { attendancePolicyId: IDS.policy },
    effectiveFrom: '2026-08-25',
    effectiveTo: null,
    isActive: true,
  });
});

test('null setup parts explicitly close the current assignment and policy', () => {
  const setup = normalizeEmployeeSetup({
    effective_from: '2026-08-25',
    assignment: null,
    policy_assignment: null,
  });
  assert.equal(setup.hasAssignmentChange, true);
  assert.equal(setup.assignment, null);
  assert.equal(setup.hasPolicyChange, true);
  assert.equal(setup.policyAssignment, null);
});

test('applies selected assignment and policy through the provided transaction client', async () => {
  const calls = [];
  const db = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.includes('AS employee_exists')) {
        return {
          rowCount: 1,
          rows: [{
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
          }],
        };
      }
      if (sql.includes('FROM attendance_policies')) {
        return { rowCount: 1, rows: [{ id: IDS.policy }] };
      }
      if (sql.includes('FROM assignments')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('INSERT INTO assignments')) {
        return { rowCount: 1, rows: [{ id: 'assignment-id' }] };
      }
      if (sql.includes('INSERT INTO policy_assignments')) {
        return { rowCount: 1, rows: [{ id: 'policy-assignment-id' }] };
      }
      return { rowCount: 1, rows: [] };
    },
  };

  const result = await applyEmployeeSetup(db, {
    employeeId: IDS.employee,
    setup: normalizeEmployeeSetup(completePayload()),
    remarks: 'Initial assignment from employee setup',
  });

  assert.equal(result.assignment.id, 'assignment-id');
  assert.equal(result.policyAssignment.id, 'policy-assignment-id');
  assert.equal(calls.filter((call) => call.sql.includes('INSERT INTO assignments')).length, 1);
  assert.equal(calls.filter((call) => call.sql.includes('SELECT pg_advisory_xact_lock')).length, 1);
  assert.equal(calls.filter((call) => call.sql.includes('SELECT id, attendance_policy_id')).length, 1);
  assert.equal(calls.filter((call) => call.sql.includes('UPDATE policy_assignments')).length, 0);
  assert.equal(calls.filter((call) => call.sql.includes('INSERT INTO policy_assignments')).length, 1);
});

test('invalid assignment references fail before existing setup is changed', async () => {
  const calls = [];
  const db = {
    async query(sql, params) {
      calls.push({ sql, params });
      return {
        rowCount: 1,
        rows: [{
          employee_exists: true,
          employee_is_active: true,
          employee_status: 'active',
          department_exists: true,
          department_is_active: true,
          position_exists: true,
          position_is_active: true,
          position_department_id: IDS.shift,
          shift_exists: true,
          shift_is_active: true,
        }],
      };
    },
  };

  const assignmentOnlyPayload = completePayload();
  delete assignmentOnlyPayload.policy_assignment;

  await assert.rejects(
    applyEmployeeSetup(db, {
      employeeId: IDS.employee,
      setup: normalizeEmployeeSetup(assignmentOnlyPayload),
    }),
    /Selected position does not belong to the selected department/
  );
  assert.equal(calls.length, 1);
  assert.equal(calls.some((call) => call.sql.includes('UPDATE assignments')), false);
});

test('inactive assignment selection returns a setup conflict instead of a server error', async () => {
  const db = {
    async query() {
      return {
        rowCount: 1,
        rows: [{
          employee_exists: true,
          employee_is_active: true,
          employee_status: 'active',
          department_exists: true,
          department_is_active: true,
          position_exists: true,
          position_is_active: true,
          position_department_id: IDS.department,
          shift_exists: true,
          shift_is_active: false,
        }],
      };
    },
  };
  const assignmentOnlyPayload = completePayload();
  delete assignmentOnlyPayload.policy_assignment;

  await assert.rejects(
    applyEmployeeSetup(db, {
      employeeId: IDS.employee,
      setup: normalizeEmployeeSetup(assignmentOnlyPayload),
    }),
    (error) =>
      error instanceof EmployeeSetupValidationError &&
      error.statusCode === 409 &&
      error.message === 'Selected shift is inactive'
  );
});
