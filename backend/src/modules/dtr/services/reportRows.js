'use strict';
module.exports = function createDtrComponent({
  calculateAttendancePolicyPenalties,
  computeAttendanceRemark,
  computeLateMinutes,
  computeUndertimeMinutes,
  getAttendancePolicyForEmployeeDate,
  getShiftInfoForDateFromAssignments,
  hasShiftEnded,
  isOvernight,
  resolveAttendanceHolidayOverlay,
  resolveAttendancePolicy,
  resolveShiftType,
  toIsoDateStr,
}) {
  async function mapSavedAttendanceRow(
    r,
    {
      activeHolidayByDate,
      rawAssignmentsByEmployee,
      rawAttendancePolicyContext,
      recomputeExistingRows,
      savedShiftsByDate,
    }
  ) {
    // Use the date-only text from SQL to avoid timezone shifting issues when JS receives Date objects.
    const dateStr =
      (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) ||
      toIsoDateStr(r.attendance_date);
    const shiftInfo =
      r.shift_snapshot ||
      (dateStr
        ? getShiftInfoForDateFromAssignments(rawAssignmentsByEmployee, r.employee_id, dateStr)
        : null);
    if (r.shift_snapshot && dateStr) {
      savedShiftsByDate.set(`${r.employee_id}|${dateStr}`, r.shift_snapshot);
    }
    const activeHoliday = activeHolidayByDate.get(dateStr) || null;
    const holidayState = resolveAttendanceHolidayOverlay(r, activeHoliday);
    const activeHolidayId = holidayState.holidayId;
    const coverage = holidayState.coverage;
    const hasLeaveCoverage = r.leave_coverage_id != null || r.leave_request_status === 'approved';
    const activeLeaveRequestId = hasLeaveCoverage ? r.leave_request_id : null;
    const effectiveStatus = activeHoliday
      ? 'holiday'
      : hasLeaveCoverage
        ? 'on_leave'
        : holidayState.status;
    const isWholeDayHoliday = activeHoliday?.coverage === 'whole_day';
    const isPartialSuspension =
      activeHoliday != null && (coverage === 'am_only' || coverage === 'pm_only');
    let lateMinutes =
      hasLeaveCoverage || isWholeDayHoliday
        ? 0
        : r.late_minutes != null
          ? parseInt(r.late_minutes, 10)
          : 0;
    let undertimeMinutes =
      hasLeaveCoverage || isWholeDayHoliday
        ? 0
        : r.undertime_minutes != null
          ? parseInt(r.undertime_minutes, 10)
          : 0;
    let effectiveAttendancePolicy = null;
    const reconcileHolidayChange = isPartialSuspension || holidayState.staleStoredHoliday;
    if (
      (recomputeExistingRows || reconcileHolidayChange) &&
      dateStr &&
      effectiveStatus !== 'on_leave' &&
      !isWholeDayHoliday
    ) {
      // Optional expensive path for after schedule/policy changes. The normal
      // Time Logs view uses stored summary values for fast reads.
      lateMinutes = await computeLateMinutes(
        r.employee_id,
        dateStr,
        r.time_in,
        r.break_in,
        effectiveStatus,
        activeHolidayId,
        coverage,
        shiftInfo
      );
      undertimeMinutes = await computeUndertimeMinutes(
        r.employee_id,
        dateStr,
        r.time_out,
        r.break_out,
        effectiveStatus,
        activeHolidayId,
        coverage,
        r.time_in,
        r.break_in,
        [],
        shiftInfo
      );
      const policyForDay = rawAttendancePolicyContext
        ? resolveAttendancePolicy(rawAttendancePolicyContext, r.employee_id, dateStr, shiftInfo)
        : await getAttendancePolicyForEmployeeDate(r.employee_id, dateStr);
      const adjusted = calculateAttendancePolicyPenalties(
        policyForDay,
        lateMinutes,
        undertimeMinutes
      );
      lateMinutes = adjusted.lateMinutes;
      undertimeMinutes = adjusted.undertimeMinutes;
      effectiveAttendancePolicy = policyForDay;
    }
    const recordForRemark = {
      time_in: r.time_in,
      break_out: r.break_out,
      break_in: r.break_in,
      time_out: r.time_out,
      late_minutes: lateMinutes,
      undertime_minutes: undertimeMinutes,
      status: effectiveStatus,
      holiday_id: activeHolidayId,
      leave_request_id: activeLeaveRequestId,
      leave_type_name: r.leave_type_name,
    };
    let attendanceRemark = await computeAttendanceRemark(
      recordForRemark,
      shiftInfo,
      activeHolidayId,
      activeLeaveRequestId,
      activeHoliday
    );
    if (
      isOvernight(shiftInfo) &&
      !hasShiftEnded(shiftInfo, dateStr) &&
      !r.time_out &&
      !hasLeaveCoverage &&
      !activeHoliday
    )
      attendanceRemark = 'In progress';
    const recordDateStr =
      (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) ||
      toIsoDateStr(r.attendance_date);
    return {
      id: r.id,
      user_id: r.employee_id,
      record_date: recordDateStr,
      time_in: r.time_in,
      break_out: r.break_out,
      break_in: r.break_in,
      time_out: r.time_out,
      total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
      late_minutes: lateMinutes,
      undertime_minutes: undertimeMinutes,
      status: effectiveStatus,
      pm_status: r.pm_status,
      remarks: r.remarks,
      attendance_remark: attendanceRemark,
      holiday_id: activeHolidayId,
      leave_request_id: activeLeaveRequestId,
      is_leave_covered: hasLeaveCoverage,
      holiday_name: activeHoliday?.name || null,
      holiday_type: activeHoliday?.holiday_type || null,
      coverage,
      leave_type_name: r.leave_type_name || null,
      source: hasLeaveCoverage || activeHoliday ? 'adjusted' : r.source || null,
      leave_coverage_id: r.leave_coverage_id || null,
      created_at: r.created_at,
      updated_at: r.updated_at,
      employee_name: r.employee_name,
      shift_punch_mode: resolveShiftType(shiftInfo) || 'auto',
      shift_overnight: isOvernight(shiftInfo),
      combine_late_and_undertime: effectiveAttendancePolicy?.combineLateAndUndertime ?? false,
    };
  }
  return { mapSavedAttendanceRow };
};
