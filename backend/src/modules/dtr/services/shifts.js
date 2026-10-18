'use strict';
module.exports = function createDtrComponent({
  computeTotalHoursFromRecord,
  resolveExpectedLogsForDay,
  resolveExpectedWorkMinutes,
  resolveShiftType,
}) {
  /**
   * Derive shift type from assignment shift info.
   * Returns 'am_only' | 'pm_only' | 'full_day' | 'single_session' | null (no shift).
   * - pm_only: shift starts at or after noon (startMinutes >= 720)
   * - am_only: no break_end and shift ends by 1 PM
   * - full_day: otherwise (has both AM and PM periods)
   */
  function getShiftType(shiftInfo) {
    return resolveShiftType(shiftInfo);
  }

  /** Expected net work minutes for a shift (exclude lunch on full-day shifts). */
  function getExpectedWorkMinutes(shiftInfo) {
    return resolveExpectedWorkMinutes(shiftInfo);
  }

  /**
   * Get which logs are expected for the shift.
   * Returns { needsAm: boolean, needsPm: boolean, needsInOut: boolean }.
   * needsAm: expects time_in + break_out
   * needsPm: expects break_in + time_out
   */
  function getShiftExpectedLogs(shiftInfo) {
    return resolveExpectedLogsForDay(shiftInfo, null);
  }

  /**
   * Get expected logs for a day considering holiday/suspension coverage.
   * holidayInfo: { holiday_type, coverage } or null.
   * - whole_day or regular/special/local: no logs required.
   * - am_only (work_suspension): only PM required.
   * - pm_only (work_suspension): only AM required.
   */
  function getExpectedLogsForDay(shiftInfo, holidayInfo) {
    return resolveExpectedLogsForDay(shiftInfo, holidayInfo);
  }

  /** Find applicable assignment shift info for employeeId on dateStr using pre-fetched assignments. */
  function getShiftInfoForDateFromAssignments(assignmentsByEmployee, employeeId, dateStr) {
    const list = assignmentsByEmployee.get(employeeId);
    if (!list || list.length === 0) return null;
    for (const a of list) {
      if (a.effective_from <= dateStr && (!a.effective_to || a.effective_to >= dateStr)) return a;
    }
    return null;
  }

  /** Compute total_hours from punch points. Supports full-day, AM/PM-only, and single-session records. */
  function computeTotalHours(timeIn, breakOut, breakIn, timeOut, shiftInfo = null) {
    return computeTotalHoursFromRecord(
      {
        time_in: timeIn,
        break_out: breakOut,
        break_in: breakIn,
        time_out: timeOut,
      },
      shiftInfo
    );
  }
  return {
    getShiftType,
    getExpectedWorkMinutes,
    getShiftExpectedLogs,
    getExpectedLogsForDay,
    getShiftInfoForDateFromAssignments,
    computeTotalHours,
  };
};
