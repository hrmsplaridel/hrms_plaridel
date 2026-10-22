'use strict';
module.exports = function createDtrComponent({
  getExpectedLogsForDay,
  locatorRequestTypeLabel,
  resolveShiftType,
  resolveSingleSessionPunches,
}) {
  /**
   * Compute attendance remark. Priority: 1) Holiday/Suspension 2) Leave 3) Absent 4) Incomplete 5) Late+Undertime 6) Late 7) Undertime 8) On Time.
   * holidayInfo: { name, holiday_type, coverage } or null.
   */
  async function computeAttendanceRemark(
    record,
    shiftInfo,
    holidayId,
    leaveRequestId,
    holidayInfo,
    locatorSegments = []
  ) {
    if (record.holiday_id != null || holidayId != null || record.status === 'holiday') {
      const name = (holidayInfo && holidayInfo.name) || record.holiday_name || 'Holiday';
      const cov = (holidayInfo && holidayInfo.coverage) || record.coverage;
      if (cov === 'am_only') return `${name} (AM)`;
      if (cov === 'pm_only') return `${name} (PM)`;
      return name;
    }
    if (record.leave_request_id != null || leaveRequestId != null || record.status === 'on_leave') {
      return (record.leave_type_name && String(record.leave_type_name).trim()) || 'Leave';
    }
    const locatorSegSet = new Set(
      (Array.isArray(locatorSegments) ? locatorSegments : []).map((s) =>
        String(s).toUpperCase().trim()
      )
    );
    const hasPhysicalLog = record.time_in || record.break_out || record.break_in || record.time_out;
    const hasAnyLog = hasPhysicalLog || locatorSegSet.size > 0;
    if (!hasAnyLog) return 'Absent';
    if (record.status === 'invalid') return 'Invalid Log';
    if (record.status === 'on_field' && !hasPhysicalLog) {
      const locatorDtrLabel = String(record.locator_slip_dtr_slot_label || '').trim();
      if (record.locator_slip_coverage_mode === 'wfh') {
        return locatorDtrLabel || 'WFH';
      }
      const segments = Array.from(locatorSegSet);
      const segText = segments.length > 0 ? ` (${segments.join(', ')})` : '';
      return `${
        locatorDtrLabel || locatorRequestTypeLabel(record.locator_slip_request_type)
      }${segText}`;
    }

    const expected = getExpectedLogsForDay(shiftInfo, holidayInfo);
    const hasAm =
      (record.time_in != null || locatorSegSet.has('AM IN')) &&
      (record.break_out != null || locatorSegSet.has('AM OUT'));
    const hasPm =
      (record.break_in != null || locatorSegSet.has('PM IN')) &&
      (record.time_out != null || locatorSegSet.has('PM OUT'));
    const sessionPunches = resolveSingleSessionPunches(record);
    const hasInOut =
      resolveShiftType(shiftInfo) === 'single_session'
        ? (sessionPunches.timeIn != null ||
            locatorSegSet.has('AM IN') ||
            locatorSegSet.has('PM IN')) &&
          (sessionPunches.timeOut != null ||
            locatorSegSet.has('AM OUT') ||
            locatorSegSet.has('PM OUT'))
        : (record.time_in != null || locatorSegSet.has('AM IN')) &&
          (record.time_out != null || locatorSegSet.has('PM OUT'));
    const missingRequired =
      (expected.needsAm && !hasAm) ||
      (expected.needsPm && !hasPm) ||
      (expected.needsInOut && !hasInOut);
    if (missingRequired) return 'Incomplete';

    const late = (record.late_minutes ?? 0) > 0;
    const under = (record.undertime_minutes ?? 0) > 0;
    if (late && under) return 'Late + Undertime';
    if (late) return 'Late';
    if (under) return 'Undertime';
    return 'On Time';
  }
  return { computeAttendanceRemark };
};
