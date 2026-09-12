const test = require('node:test');
const assert = require('node:assert/strict');
const {
  filterAssignmentRowsForAccess,
  resolveAssignmentEmployeeAccess,
} = require('../src/services/assignmentAccess');

test('employee can view their own assignment', () => {
  const access = resolveAssignmentEmployeeAccess(
    { id: 'employee-self', role: 'employee' },
    'employee-self'
  );

  assert.equal(access.allowed, true);
  assert.equal(access.employeeId, 'employee-self');
});

test('employee cannot view another employee assignment', () => {
  const access = resolveAssignmentEmployeeAccess(
    { id: 'employee-self', role: 'employee' },
    'employee-other'
  );

  assert.equal(access.allowed, false);
  assert.equal(access.statusCode, 403);
  assert.equal(access.employeeId, null);
});

test('assignment access fails closed without an authenticated employee id', () => {
  const access = resolveAssignmentEmployeeAccess(
    { role: 'employee' },
    'employee-other'
  );

  assert.equal(access.allowed, false);
  assert.equal(access.statusCode, 401);
});

test('admin and HR can view a selected employee assignment organization-wide', () => {
  for (const role of ['admin', 'hr']) {
    const access = resolveAssignmentEmployeeAccess(
      { id: `${role}-user`, role },
      'employee-selected'
    );

    assert.equal(access.allowed, true);
    assert.equal(access.employeeId, 'employee-selected');
    assert.equal(access.scope, 'organization');
  }
});

test('supervisor assignment access is scoped instead of organization-wide', () => {
  const access = resolveAssignmentEmployeeAccess(
    { id: 'supervisor-user', role: 'supervisor' },
    'employee-selected'
  );

  assert.equal(access.allowed, true);
  assert.equal(access.employeeId, 'employee-selected');
  assert.equal(access.scope, 'supervised_departments');
});

test('employee cannot perform an assignment directory search', () => {
  const access = resolveAssignmentEmployeeAccess(
    { id: 'employee-self', role: 'employee' },
    null,
    { allowDirectorySearch: true }
  );

  assert.equal(access.allowed, false);
  assert.equal(access.statusCode, 403);
});

test('supervisor sees only records overlapping their department assignment period', async () => {
  const access = resolveAssignmentEmployeeAccess(
    { id: 'supervisor-user', role: 'supervisor' },
    'employee-selected'
  );
  const db = {
    async query() {
      return {
        rows: [{
          employee_id: 'supervisor-user',
          department_id: 'department-a',
          effective_from: '2026-05-01',
          effective_to: '2026-07-31',
        }],
      };
    },
  };
  const rows = [
    {
      id: 'same-department-and-date',
      employee_id: 'employee-selected',
      department_id: 'department-a',
      effective_from: '2026-06-01',
      effective_to: '2026-06-30',
    },
    {
      id: 'different-department',
      employee_id: 'employee-selected',
      department_id: 'department-b',
      effective_from: '2026-06-01',
      effective_to: '2026-06-30',
    },
    {
      id: 'same-department-wrong-date',
      employee_id: 'employee-selected',
      department_id: 'department-a',
      effective_from: '2026-03-01',
      effective_to: '2026-04-30',
    },
  ];

  const visible = await filterAssignmentRowsForAccess(db, access, rows);

  assert.deepEqual(visible.map((row) => row.id), ['same-department-and-date']);
});

test('supervisor role alone does not grant department assignment access', async () => {
  const access = resolveAssignmentEmployeeAccess(
    { id: 'supervisor-user', role: 'supervisor' },
    'employee-selected'
  );
  const db = { async query() { return { rows: [] }; } };
  const rows = [{
    id: 'coworker-assignment',
    employee_id: 'employee-selected',
    department_id: 'department-a',
    effective_from: '2026-06-01',
    effective_to: null,
  }];

  const visible = await filterAssignmentRowsForAccess(db, access, rows);

  assert.deepEqual(visible, []);
});

test('supervisor policy access resolves the employee department for undepartmentalized rows', async () => {
  const access = resolveAssignmentEmployeeAccess(
    { id: 'supervisor-user', role: 'supervisor' },
    'employee-selected'
  );
  const db = {
    async query(_sql, params) {
      const ids = params[0];
      if (ids.includes('supervisor-user')) {
        return {
          rows: [{
            employee_id: 'supervisor-user',
            department_id: 'department-a',
            effective_from: '2026-01-01',
            effective_to: null,
          }],
        };
      }
      return {
        rows: [{
          employee_id: 'employee-selected',
          department_id: 'department-a',
          effective_from: '2026-06-01',
          effective_to: '2026-06-30',
        }],
      };
    },
  };
  const rows = [{
    id: 'employee-policy',
    employee_id: 'employee-selected',
    department_id: null,
    effective_from: '2026-06-01',
    effective_to: '2026-06-30',
  }];

  const visible = await filterAssignmentRowsForAccess(db, access, rows);

  assert.deepEqual(visible.map((row) => row.id), ['employee-policy']);
});
