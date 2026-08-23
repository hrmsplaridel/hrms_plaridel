const test = require('node:test');
const assert = require('node:assert/strict');
const {
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

test('privileged roles can view a selected employee assignment', () => {
  for (const role of ['admin', 'hr', 'supervisor']) {
    const access = resolveAssignmentEmployeeAccess(
      { id: `${role}-user`, role },
      'employee-selected'
    );

    assert.equal(access.allowed, true);
    assert.equal(access.employeeId, 'employee-selected');
  }
});
