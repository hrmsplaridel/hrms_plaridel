'use strict';
module.exports = function createDtrComponent({
  getExpectedWorkMinutesForCoverage,
  getShiftInfoForDateFromAssignments,
  isOvernight,
  resolveShiftType,
  resolvedWorkingDay,
}) {
  async function addHolidayReportRows({
    assignmentsByEmployee,
    employeeIds,
    existingKeys,
    holidaysInRange,
    rows,
    scheduleOverrides,
    scopedDepartmentId,
    userIdToName,
  }) {
    if (holidaysInRange.length > 0) {
      for (const h of holidaysInRange) {
        const cov = h.coverage || 'whole_day';
        let remark = h.name || 'Holiday';
        if (cov === 'am_only') remark = `${remark} (AM)`;
        else if (cov === 'pm_only') remark = `${remark} (PM)`;
        for (const empId of employeeIds) {
          const key = `${empId}|${h.dateStr}`;
          if (existingKeys.has(key)) continue;
          const shiftInfo = getShiftInfoForDateFromAssignments(
            assignmentsByEmployee,
            empId,
            h.dateStr
          );
          if (!shiftInfo) continue;
          if (
            scopedDepartmentId &&
            String(shiftInfo.departmentId || '') !== String(scopedDepartmentId)
          ) {
            continue;
          }
          if (
            !resolvedWorkingDay({
              employeeId: empId,
              dateStr: h.dateStr,
              workingDays: shiftInfo.workingDays,
              overrides: scheduleOverrides,
            })
          )
            continue;
          existingKeys.add(key);
          rows.push({
            id: null,
            user_id: empId,
            record_date: h.dateStr,
            time_in: null,
            break_out: null,
            break_in: null,
            time_out: null,
            total_hours: null,
            late_minutes: 0,
            undertime_minutes: getExpectedWorkMinutesForCoverage(shiftInfo, cov),
            status: 'holiday',
            pm_status: null,
            remarks: null,
            source: 'adjusted',
            attendance_remark: remark,
            holiday_id: h.id,
            leave_request_id: null,
            holiday_name: h.name,
            holiday_type: h.holiday_type,
            coverage: cov,
            created_at: null,
            updated_at: null,
            employee_name: userIdToName[empId] || null,
            shift_punch_mode: resolveShiftType(shiftInfo) || 'auto',
            shift_overnight: isOvernight(shiftInfo),
          });
        }
      }
    }
  }
  return { addHolidayReportRows };
};
