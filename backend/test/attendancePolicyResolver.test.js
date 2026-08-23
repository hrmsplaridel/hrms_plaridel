'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  calculateAttendanceReportDeduction,
  calculateAttendancePolicyPenalties,
  loadAttendancePolicyContext,
  resolveAttendancePolicy,
} = require('../src/services/attendancePolicyResolver');

test('report deduction uses the effective policy denominator and switches', () => {
  const oneHourPolicy = {
    workHoursPerDay: 1,
    useEquivalentDayConversion: true,
    deductLate: true,
    deductUndertime: true,
    absentEqualsFullDayDeduction: true,
    deductionMultiplier: 1,
  };
  const defaultPolicy = {
    ...oneHourPolicy,
    workHoursPerDay: 8,
    deductLate: false,
  };

  assert.deepEqual(
    calculateAttendanceReportDeduction({
      policy: oneHourPolicy,
      lateMinutes: 30,
      undertimeMinutes: 0,
      status: 'late',
      expectedWorkMinutes: 60,
    }),
    {
      late_minutes: 30,
      undertime_minutes: 0,
      absence_minutes: 0,
      total_minutes: 30,
      equivalent_day: 0.5,
    }
  );
  assert.equal(
    calculateAttendanceReportDeduction({
      policy: defaultPolicy,
      lateMinutes: 30,
      undertimeMinutes: 0,
      status: 'late',
      expectedWorkMinutes: 480,
    }).equivalent_day,
    0
  );
});

test('report deduction does not apply an already-processed multiplier twice', () => {
  const deduction = calculateAttendanceReportDeduction({
    policy: {
      workHoursPerDay: 8,
      useEquivalentDayConversion: true,
      deductLate: true,
      deductUndertime: true,
      absentEqualsFullDayDeduction: true,
      deductionMultiplier: 2,
    },
    lateMinutes: 120,
    undertimeMinutes: 0,
    status: 'late',
    expectedWorkMinutes: 480,
  });

  assert.equal(deduction.total_minutes, 120);
  assert.equal(deduction.equivalent_day, 0.25);
});

test('attendance penalties preserve late and undertime as separate source buckets', () => {
  const policy = {
    deductLate: true,
    maxLateMinutesPerMonth: 60,
    deductUndertime: true,
    combineLateAndUndertime: true,
    convertLateToEquivalentDay: false,
    convertUndertimeToEquivalentDay: false,
    workHoursPerDay: 8,
    deductionMultiplier: 1,
  };

  assert.deepEqual(calculateAttendancePolicyPenalties(policy, 90, 15), {
    lateMinutes: 90,
    undertimeMinutes: 15,
  });
});

const employeeId = '11111111-1111-4111-8111-111111111111';
const departmentId = '22222222-2222-4222-8222-222222222222';
const shiftId = '33333333-3333-4333-8333-333333333333';

function policyRow({
  assignmentId,
  policyId,
  employee,
  department,
  shift,
  effectiveFrom = '2026-01-01',
  effectiveTo = null,
  absentDeduction,
}) {
  return {
    policy_assignment_id: assignmentId,
    id: policyId,
    employee_id: employee || null,
    department_id: department || null,
    shift_id: shift || null,
    effective_from: effectiveFrom,
    effective_to: effectiveTo,
    created_at: `${effectiveFrom}T00:00:00.000Z`,
    work_hours_per_day: '8',
    deduct_late: true,
    deduct_undertime: true,
    absent_equals_full_day_deduction: absentDeduction,
    deduction_multiplier: '1',
  };
}

test('batch policy context preserves employee, department, shift, and default precedence', async () => {
  const queries = [];
  const db = {
    async query(sql, params) {
      queries.push({ sql: String(sql), params });
      if (String(sql).includes('FROM policy_assignments')) {
        return {
          rows: [
            policyRow({
              assignmentId: 'pa-shift',
              policyId: 'policy-shift',
              shift: shiftId,
              absentDeduction: false,
            }),
            policyRow({
              assignmentId: 'pa-department',
              policyId: 'policy-department',
              department: departmentId,
              absentDeduction: true,
            }),
            policyRow({
              assignmentId: 'pa-employee',
              policyId: 'policy-employee',
              employee: employeeId,
              effectiveFrom: '2026-06-15',
              absentDeduction: false,
            }),
          ],
        };
      }
      return {
        rows: [policyRow({ policyId: 'policy-default', absentDeduction: true })],
      };
    },
  };
  const assignments = new Map([
    [employeeId, [{ departmentId, shiftId }]],
  ]);

  const context = await loadAttendancePolicyContext(
    db,
    [employeeId],
    '2026-06-01',
    '2026-06-30',
    assignments
  );

  assert.equal(queries.length, 2);
  assert.equal(
    resolveAttendancePolicy(context, employeeId, '2026-06-10', assignments.get(employeeId)[0]).id,
    'policy-department'
  );
  assert.equal(
    resolveAttendancePolicy(context, employeeId, '2026-06-20', assignments.get(employeeId)[0]).id,
    'policy-employee'
  );
  assert.equal(
    resolveAttendancePolicy(context, 'unassigned', '2026-06-20', null).id,
    'policy-default'
  );
});

test('batch policy query receives all range targets in one call', async () => {
  let assignedParams;
  const secondEmployeeId = '44444444-4444-4444-8444-444444444444';
  const db = {
    async query(sql, params) {
      if (String(sql).includes('FROM policy_assignments')) assignedParams = params;
      return { rows: [] };
    },
  };
  const assignments = new Map([
    [employeeId, [{ departmentId, shiftId }]],
    [secondEmployeeId, [{ departmentId, shiftId }]],
  ]);

  await loadAttendancePolicyContext(
    db,
    [employeeId, secondEmployeeId],
    '2026-08-01',
    '2026-08-31',
    assignments
  );

  assert.deepEqual(assignedParams, [
    [employeeId, secondEmployeeId],
    [departmentId],
    [shiftId],
    '2026-08-01',
    '2026-08-31',
  ]);
});
