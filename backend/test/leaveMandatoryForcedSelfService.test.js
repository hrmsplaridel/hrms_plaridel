'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getRule,
  isEmployeeFileable,
  validateEmployeeLeaveRequest,
} = require('../src/routes/leaveTypeRules');

test('Mandatory/Forced Leave is available through employee self-service', () => {
  const rule = getRule('mandatoryForcedLeave');

  assert.equal(rule.employee_can_file, true);
  assert.equal(rule.admin_only, false);
  assert.equal(isEmployeeFileable('mandatoryForcedLeave'), true);
  assert.deepEqual(
    validateEmployeeLeaveRequest({
      leaveType: 'mandatoryForcedLeave',
      startDateStr: '2026-10-01',
      endDateStr: '2026-10-01',
      numberOfDays: 1,
    }),
    { valid: true }
  );
});
