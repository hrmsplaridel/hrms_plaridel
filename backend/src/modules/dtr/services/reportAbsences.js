'use strict';
module.exports = function createDtrComponent({
  evaluateLocatorCoverage,
  getExpectedWorkMinutes,
  getShiftInfoForDateFromAssignments,
  hasShiftEnded,
  isOvernight,
  resolveAttendancePolicy,
  resolveShiftType,
  resolvedWorkingDay,
}) {
  async function addAbsenceReportRows({
    assignmentsByEmployee,
    attendancePolicyContext,
    employeeIds,
    endD,
    existingKeys,
    holidayByDate,
    leaveKeys,
    locatorByKey,
    nowMinutes,
    rows,
    scheduleOverrides,
    scopedDepartmentId,
    startD,
    todayStr,
    userIdToName,
  }) {
    for (let d = new Date(startD); d <= endD; d.setDate(d.getDate() + 1)) {
      const dateStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
      if (dateStr > todayStr) continue; // no future absences

      const holiday = holidayByDate.get(dateStr) || null;
      const holidayCoverage = holiday?.coverage || 'whole_day';
      const isWholeDayHoliday = holiday != null && holidayCoverage === 'whole_day';
      if (isWholeDayHoliday) continue; // holiday row already injected (or exists)

      for (const empId of employeeIds) {
        const key = `${empId}|${dateStr}`;
        if (existingKeys.has(key)) continue;
        if (leaveKeys.has(key)) continue;
        const shiftInfo = getShiftInfoForDateFromAssignments(assignmentsByEmployee, empId, dateStr);
        if (!shiftInfo) continue; // no assignment/shift => can't determine working day
        if (
          scopedDepartmentId &&
          String(shiftInfo.departmentId || '') !== String(scopedDepartmentId)
        ) {
          continue;
        }

        const locator = locatorByKey.get(key);
        const locatorCoverage = evaluateLocatorCoverage({
          locator,
          shiftInfo,
          holidayInfo: holiday,
          date: dateStr,
        });
        if (locatorCoverage.isFullCoverage) continue;

        if (
          !resolvedWorkingDay({
            employeeId: empId,
            dateStr,
            workingDays: shiftInfo.workingDays,
            overrides: scheduleOverrides,
          })
        )
          continue;

        // Only show "Absent" for today after shift end, or any past working day.
        if (isOvernight(shiftInfo) && !hasShiftEnded(shiftInfo, dateStr)) continue;
        if (!isOvernight(shiftInfo) && dateStr === todayStr) {
          const endMinutes = shiftInfo.endMinutes != null ? shiftInfo.endMinutes : 24 * 60 - 1;
          if (nowMinutes <= endMinutes) continue;
        }

        // Absent = no rendered work; undertime baseline should be net expected
        // work minutes (exclude lunch for full-day shifts).
        const policyForDay = resolveAttendancePolicy(
          attendancePolicyContext,
          empId,
          dateStr,
          shiftInfo
        );
        const absentUndertime = policyForDay.absentEqualsFullDayDeduction
          ? getExpectedWorkMinutes(shiftInfo)
          : 0;

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
          undertime_minutes: absentUndertime,
          status: 'absent',
          pm_status: null,
          remarks: null,
          source: null,
          attendance_remark: 'Absent',
          holiday_id: null,
          leave_request_id: null,
          holiday_name: null,
          holiday_type: null,
          coverage: null,
          created_at: null,
          updated_at: null,
          employee_name: userIdToName[empId] || null,
          shift_punch_mode: resolveShiftType(shiftInfo) || 'auto',
          shift_overnight: isOvernight(shiftInfo),
          combine_late_and_undertime: policyForDay.combineLateAndUndertime,
        });
      }
    }
  }
  return { addAbsenceReportRows };
};
