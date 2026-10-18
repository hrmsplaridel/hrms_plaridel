'use strict';
module.exports = function createDtrComponent({
  NOON_MINUTES,
  ONE_PM_MINUTES,
  computeClockOutUndertimeMinutes,
  getAssignmentShiftForDate,
  getExpectedAmEndMinutes,
  getExpectedPmStartMinutes,
  getShiftType,
  isOvernight,
  minutesFromMidnightInTimeZone,
  nowMinutesInHrmsTimezone,
  overnightPenalties,
  resolveExpectedWorkMinutes,
  todayInHrmsTimezone,
}) {
  /**
   * Compute AM status from shift: 'late' if time_in is after start_time + grace, else 'present'.
   * Returns 'present' if no assignment/shift.
   */
  async function computeStatusFromShift(employeeId, dateStr, timeInIso) {
    if (!timeInIso) return 'present';
    const shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
    if (!shiftInfo) return 'present';
    const { startMinutes, graceMinutes } = shiftInfo;
    if (isOvernight(shiftInfo))
      return overnightPenalties(shiftInfo, dateStr, { timeIn: timeInIso }).lateMinutes > 0
        ? 'late'
        : 'present';
    const cutoffMinutes = startMinutes + graceMinutes;

    const localMins = minutesFromMidnightInTimeZone(timeInIso);
    if (localMins == null) return 'present';
    return localMins > cutoffMinutes ? 'late' : 'present';
  }

  /**
   * Compute PM status: 'late' if break_in is after break_end + grace, else 'present'.
   * Returns null if there is no break_in. Full-day legacy rows without break_end use 1:00 PM.
   */
  async function computePmLateStatus(employeeId, dateStr, breakInIso) {
    if (!breakInIso) return null;
    const shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
    if (!shiftInfo) return 'present';
    const pmStartMinutes = getExpectedPmStartMinutes(shiftInfo);
    if (pmStartMinutes == null) return 'present';
    if (isOvernight(shiftInfo)) {
      const { punchMinute, scheduledMinute } = require('../../../services/shiftTimeline');
      return punchMinute(breakInIso, dateStr) >
        scheduledMinute(shiftInfo, pmStartMinutes) + shiftInfo.graceMinutes
        ? 'late'
        : 'present';
    }
    const cutoffMinutes = pmStartMinutes + shiftInfo.graceMinutes;

    const localMins = minutesFromMidnightInTimeZone(breakInIso);
    if (localMins == null) return 'present';
    return localMins > cutoffMinutes ? 'late' : 'present';
  }

  /**
   * Compute total late minutes: AM late (time_in after start+grace) + PM late (break_in after pmStart+grace).
   * For full-day/AM: PM late uses breakEndMinutes. For PM-only: uses startMinutes (shift start = PM start).
   * Returns 0 for holiday/on_leave or when no shift. For partial-day suspension (coverage am_only/pm_only),
   * only the non-suspended half is evaluated. Seconds ignored.
   */
  async function computeLateMinutes(
    employeeId,
    dateStr,
    timeInIso,
    breakInIso,
    status,
    holidayId,
    coverage,
    prefetchedShiftInfo = null
  ) {
    if (status === 'on_leave') return 0;
    const isHolidayOrSuspension = status === 'holiday' || holidayId != null;
    if (isHolidayOrSuspension && (!coverage || coverage === 'whole_day')) return 0;
    const shiftInfo = prefetchedShiftInfo || (await getAssignmentShiftForDate(employeeId, dateStr));
    if (!shiftInfo) return 0;
    if (isOvernight(shiftInfo))
      return overnightPenalties(
        shiftInfo,
        dateStr,
        { timeIn: timeInIso, breakIn: breakInIso },
        new Date(),
        coverage
      ).lateMinutes;
    const { startMinutes, graceMinutes } = shiftInfo;
    const type = getShiftType(shiftInfo);
    let total = 0;
    const evalAm = !isHolidayOrSuspension || coverage !== 'am_only';
    const evalPm = !isHolidayOrSuspension || coverage !== 'pm_only';
    if (type === 'single_session') {
      const sessionIn = timeInIso || breakInIso;
      const evaluateSession = shiftInfo.startMinutes >= NOON_MINUTES ? evalPm : evalAm;
      if (evaluateSession && sessionIn) {
        const localMins = minutesFromMidnightInTimeZone(sessionIn);
        if (localMins != null) {
          const cutoff = startMinutes + graceMinutes;
          if (localMins > cutoff) total += localMins - cutoff;
        }
      }
      return total;
    }
    if (evalAm && timeInIso && type !== 'pm_only') {
      const localMins = minutesFromMidnightInTimeZone(timeInIso);
      if (localMins == null) return total;
      const cutoff = startMinutes + graceMinutes;
      if (localMins > cutoff) total += localMins - cutoff;
    }
    const pmStartMinutes = getExpectedPmStartMinutes(shiftInfo);
    if (evalPm && breakInIso && pmStartMinutes != null) {
      const localMins = minutesFromMidnightInTimeZone(breakInIso);
      if (localMins == null) return total;
      const cutoff = pmStartMinutes + graceMinutes;
      if (localMins > cutoff) total += localMins - cutoff;
    }
    return total;
  }

  /**
   * Compute undertime minutes from every required clock-out segment.
   * - AM-only: uses break_out (AM end) vs end_time
   * - Full-day: adds early break_out and early time_out
   * - PM-only / single-session: uses time_out vs end_time
   * Returns 0 for holiday/on_leave or when no shift. For partial-day suspension (coverage am_only/pm_only),
   * only the non-suspended half is evaluated. Seconds ignored.
   */
  async function computeUndertimeMinutes(
    employeeId,
    dateStr,
    timeOutIso,
    breakOutIso,
    status,
    holidayId,
    coverage,
    timeInIso,
    breakInIso,
    locatorSegments = [],
    prefetchedShiftInfo = null
  ) {
    if (status === 'on_leave') return 0;
    if (status === 'on_field' && !timeInIso && !breakOutIso && !breakInIso && !timeOutIso) {
      return 0;
    }
    const isHolidayOrSuspension = status === 'holiday' || holidayId != null;
    if (isHolidayOrSuspension && (!coverage || coverage === 'whole_day')) return 0;
    const shiftInfo = prefetchedShiftInfo || (await getAssignmentShiftForDate(employeeId, dateStr));
    if (!shiftInfo || shiftInfo.endMinutes == null) return 0;
    if (isOvernight(shiftInfo))
      return overnightPenalties(
        shiftInfo,
        dateStr,
        {
          timeIn: timeInIso,
          breakIn: breakInIso,
          timeOut: timeOutIso,
          breakOut: breakOutIso,
        },
        new Date(),
        coverage,
        locatorSegments
      ).undertimeMinutes;
    const type = getShiftType(shiftInfo);
    const evalAm = !isHolidayOrSuspension || coverage !== 'am_only';
    const evalPm = !isHolidayOrSuspension || coverage !== 'pm_only';
    const locatorSegSet = new Set(
      (Array.isArray(locatorSegments) ? locatorSegments : []).map((s) =>
        String(s).toUpperCase().trim()
      )
    );
    // Use HRMS_TIMEZONE so "today" matches the business calendar date, not UTC.
    const todayStr = todayInHrmsTimezone();
    const nowMinutes = nowMinutesInHrmsTimezone();
    let amUndertimePenalty = 0;
    if (type === 'full_day' && evalAm && shiftInfo.startMinutes != null) {
      const hasAmLogs =
        (timeInIso != null || locatorSegSet.has('AM IN')) &&
        (breakOutIso != null || locatorSegSet.has('AM OUT'));
      const amEndMinutes = getExpectedAmEndMinutes(shiftInfo);
      const pmStartMinutes = getExpectedPmStartMinutes(shiftInfo) ?? ONE_PM_MINUTES;
      const amWindowClosed =
        dateStr < todayStr || (dateStr === todayStr && nowMinutes >= pmStartMinutes);
      if (!hasAmLogs && amWindowClosed) {
        amUndertimePenalty = Math.max(0, amEndMinutes - shiftInfo.startMinutes);
      }
    }
    const breakOutMins = breakOutIso ? minutesFromMidnightInTimeZone(breakOutIso) : null;
    const effectiveTimeOut = type === 'single_session' ? timeOutIso || breakOutIso : timeOutIso;
    const timeOutMins = effectiveTimeOut ? minutesFromMidnightInTimeZone(effectiveTimeOut) : null;
    const completedSegmentUndertime = computeClockOutUndertimeMinutes({
      shiftInfo,
      breakOutMinutes: breakOutMins,
      timeOutMinutes: timeOutMins,
      evaluateAm: evalAm,
      evaluatePm: evalPm,
      coveredSegments: [...locatorSegSet],
    });
    let clockOutMins = null;
    let clockOutCovered = false;
    if (type === 'am_only') {
      if (evalAm) clockOutMins = breakOutMins;
      clockOutCovered = locatorSegSet.has('AM OUT');
    } else {
      if (evalPm) clockOutMins = timeOutMins;
      clockOutCovered = locatorSegSet.has('PM OUT');
    }
    if (clockOutMins == null) {
      if (clockOutCovered || (type === 'am_only' ? !evalAm : !evalPm)) {
        return completedSegmentUndertime + amUndertimePenalty;
      }
      // Incomplete record: employee clocked in but never clocked out.
      // Compute undertime as full shift duration only if:
      //   - The date is in the past, OR
      //   - Today but shift has already ended.
      const hasClockIn = !!(timeInIso || breakInIso);
      if (!hasClockIn) return 0;
      const isPast = dateStr < todayStr;
      const isShiftOver = dateStr === todayStr && nowMinutes > shiftInfo.endMinutes;
      if (isPast || isShiftOver) {
        // For full-day shifts, undertime baseline is net work minutes (exclude lunch),
        // not raw elapsed span (e.g. 8-5 should be 480, not 540).
        const startMinutes = shiftInfo.startMinutes != null ? shiftInfo.startMinutes : 0;
        const spanMinutes = Math.max(0, shiftInfo.endMinutes - startMinutes);
        if (type === 'full_day') {
          return resolveExpectedWorkMinutes(shiftInfo) + amUndertimePenalty;
        }
        return spanMinutes + amUndertimePenalty;
      }
      return 0;
    }
    return completedSegmentUndertime + amUndertimePenalty;
  }
  return {
    computeStatusFromShift,
    computePmLateStatus,
    computeLateMinutes,
    computeUndertimeMinutes,
  };
};
