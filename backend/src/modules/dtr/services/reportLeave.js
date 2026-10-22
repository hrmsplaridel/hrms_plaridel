'use strict';
module.exports = function createDtrComponent({
  getShiftInfoForDateFromAssignments,
  isOvernight,
  resolveShiftType,
}) {
  async function addLeaveReportRows({
    assignmentsByEmployee,
    existingKeys,
    leaveCoverageByKey,
    rows,
    scopedDepartmentId,
    userIdToName,
  }) {
    for (const [key, leave] of leaveCoverageByKey.entries()) {
      if (existingKeys.has(key)) continue;
      const [empId, dateStr] = key.split('|');
      const shiftInfo = getShiftInfoForDateFromAssignments(assignmentsByEmployee, empId, dateStr);
      if (
        scopedDepartmentId &&
        String(shiftInfo?.departmentId || '') !== String(scopedDepartmentId)
      ) {
        continue;
      }
      existingKeys.add(key);
      rows.push({
        id: null,
        user_id: empId,
        record_date: dateStr,
        time_in: null,
        break_out: null,
        break_in: null,
        time_out: null,
        total_hours: null,
        late_minutes: 0,
        undertime_minutes: 0,
        status: 'on_leave',
        pm_status: null,
        remarks: null,
        source: 'adjusted',
        attendance_remark: leave.leave_type_name || 'Leave',
        holiday_id: null,
        leave_request_id: leave.leave_request_id,
        leave_coverage_id: leave.leave_coverage_id,
        is_leave_covered: true,
        holiday_name: null,
        holiday_type: null,
        coverage: null,
        leave_type_name: leave.leave_type_name || null,
        created_at: null,
        updated_at: null,
        employee_name: userIdToName[empId] || null,
        shift_punch_mode: resolveShiftType(shiftInfo) || 'auto',
        shift_overnight: isOvernight(shiftInfo),
      });
    }
  }
  return { addLeaveReportRows };
};
