'use strict';
const { isBeforeEmployeeTracking, zeroDeduction } = require('../../../services/employeeAttendanceTracking');
module.exports = function createDtrComponent({
  attendancePolicyPayload,
  calculateAttendanceReportDeduction,
  getExpectedWorkMinutes,
  getShiftInfoForDateFromAssignments,
  resolveAttendancePolicy,
}) {
  async function attachReportPolicies({
    trackingStarts = new Map(),
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
      row.attendance_tracking_start_date = trackingStarts.get(String(row.user_id))?.start || null;
      if (row.status === 'not_tracked') {
        // Partial locator overlays must not relabel missing historical days.
        row.attendance_remark = 'Not tracked';
        row.late_minutes = 0;
        row.undertime_minutes = 0;
      }
      row.report_deduction = row.status === 'not_tracked' ||
          isBeforeEmployeeTracking(row.user_id, rowDateStr, trackingStarts)
        ? zeroDeduction()
        : calculateAttendanceReportDeduction({
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
