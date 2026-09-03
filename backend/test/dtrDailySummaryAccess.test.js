const test = require('node:test');
const assert = require('node:assert/strict');
const {
  resolveDtrDailySummaryScope,
} = require('../src/services/dtrDailySummaryAccess');

test('employee DTR scope ignores another employee id', () => {
  const scope = resolveDtrDailySummaryScope(
    { id: 'employee-self', role: 'employee' },
    { employee_id: 'employee-other' }
  );

  assert.deepEqual(scope, {
    privileged: false,
    employeeId: 'employee-self',
    departmentId: null,
  });
});

test('employee DTR scope ignores department and unfiltered synthetic requests', () => {
  const withDepartment = resolveDtrDailySummaryScope(
    { id: 'employee-self', role: 'employee' },
    { department_id: 'department-other' }
  );
  const withoutFilters = resolveDtrDailySummaryScope(
    { id: 'employee-self', role: 'employee' },
    {}
  );

  assert.equal(withDepartment.employeeId, 'employee-self');
  assert.equal(withDepartment.departmentId, null);
  assert.equal(withoutFilters.employeeId, 'employee-self');
  assert.equal(withoutFilters.departmentId, null);
});

test('employee DTR scope fails closed when the authenticated id is missing', () => {
  const scope = resolveDtrDailySummaryScope(
    { role: 'employee' },
    { employee_id: 'employee-other', department_id: 'department-other' }
  );

  assert.deepEqual(scope, {
    privileged: false,
    employeeId: null,
    departmentId: null,
  });
});

test('privileged DTR scope preserves employee and department filters', () => {
  for (const role of ['admin', 'hr', 'supervisor']) {
    const scope = resolveDtrDailySummaryScope(
      { id: `${role}-user`, role },
      {
        employee_id: 'employee-selected',
        department_id: 'department-selected',
      }
    );

    assert.deepEqual(scope, {
      privileged: true,
      employeeId: 'employee-selected',
      departmentId: 'department-selected',
    });
  }
});
