'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getAttendancePolicyCache,
  invalidateAttendancePolicyCache,
  setAttendancePolicyCache,
} = require('../src/services/attendancePolicyCache');

test.beforeEach(() => invalidateAttendancePolicyCache());

test('employee invalidation clears matching DTR and biometric cache entries', () => {
  setAttendancePolicyCache('dtr', 'employee-1|2026-09-09', { id: 'policy-a' }, {
    employeeId: 'employee-1',
    date: '2026-09-09',
  });
  setAttendancePolicyCache('biometric', 'employee-1|2026-09-09', { id: 'policy-a' }, {
    employeeId: 'employee-1',
    date: '2026-09-09',
  });
  setAttendancePolicyCache('dtr', 'employee-2|2026-09-09', { id: 'policy-b' }, {
    employeeId: 'employee-2',
    date: '2026-09-09',
  });

  const removed = invalidateAttendancePolicyCache({ employeeId: 'employee-1' });

  assert.equal(removed, 2);
  assert.equal(
    getAttendancePolicyCache('dtr', 'employee-1|2026-09-09').found,
    false
  );
  assert.equal(
    getAttendancePolicyCache('biometric', 'employee-1|2026-09-09').found,
    false
  );
  assert.equal(
    getAttendancePolicyCache('dtr', 'employee-2|2026-09-09').found,
    true
  );
});

test('date-range invalidation preserves cache entries outside the changed period', () => {
  for (const date of ['2026-08-31', '2026-09-01', '2026-09-30', '2026-10-01']) {
    setAttendancePolicyCache('dtr', `employee-1|${date}`, { date }, {
      employeeId: 'employee-1',
      date,
    });
  }

  invalidateAttendancePolicyCache({
    employeeId: 'employee-1',
    dateFrom: '2026-09-01',
    dateTo: '2026-09-30',
  });

  assert.equal(getAttendancePolicyCache('dtr', 'employee-1|2026-08-31').found, true);
  assert.equal(getAttendancePolicyCache('dtr', 'employee-1|2026-09-01').found, false);
  assert.equal(getAttendancePolicyCache('dtr', 'employee-1|2026-09-30').found, false);
  assert.equal(getAttendancePolicyCache('dtr', 'employee-1|2026-10-01').found, true);
});

test('global policy invalidation also clears cached default policies', () => {
  setAttendancePolicyCache('dtr', 'default', { id: 'default-a' }, {
    isDefault: true,
  });
  setAttendancePolicyCache('biometric', 'default', { id: 'default-a' }, {
    isDefault: true,
  });

  invalidateAttendancePolicyCache();

  assert.equal(getAttendancePolicyCache('dtr', 'default').found, false);
  assert.equal(getAttendancePolicyCache('biometric', 'default').found, false);
});
