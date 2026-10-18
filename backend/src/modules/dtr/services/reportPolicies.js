'use strict';
module.exports = function createDtrComponent({
  attendancePolicyPayload,
  calculateAttendanceReportDeduction,
  getExpectedWorkMinutes,
  getShiftInfoForDateFromAssignments,
  resolveAttendancePolicy,
}) {
  async function attachReportPolicies({
    assignmentsByEmployee,
    attendancePolicyContext,
    rows,
    savedShiftsByDate,
  }) {
    for (const row of rows) {
      const rowDateStr = String(row.record_date || '').slice(0, 10);
      if (!rowDateStr) continue;
      const shiftInfo =
        savedShiftsByDate.get(`${row.user_id}|${rowDateStr}`) ||
        getShiftInfoForDateFromAssignments(assignmentsByEmployee, row.user_id, rowDateStr);
      const policyForDay = resolveAttendancePolicy(
        attendancePolicyContext,
        row.user_id,
        rowDateStr,
        shiftInfo
      );
      row.combine_late_and_undertime = policyForDay.combineLateAndUndertime;
      row.attendance_policy = attendancePolicyPayload(policyForDay);
      row.report_deduction = calculateAttendanceReportDeduction({
        policy: policyForDay,
        lateMinutes: row.late_minutes,
        undertimeMinutes: row.undertime_minutes,
        status: row.status,
        expectedWorkMinutes: shiftInfo ? getExpectedWorkMinutes(shiftInfo) : 0,
        holidayCoverage: row.coverage,
      });
    }
  }
  return { attachReportPolicies };
};
