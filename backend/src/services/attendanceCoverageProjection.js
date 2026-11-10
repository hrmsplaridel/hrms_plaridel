'use strict';

// Project official attendance without rewriting the underlying attendance evidence.
const shiftAttendance = require('./shiftAttendance');
const { evaluateLocatorCoverage, normalizeShiftInfo, locatorCoverageSegments,
  expectedLocatorSlotsForShift } = require('./locatorCoverage');
const { calculateAttendancePolicyPenalties } = require('./attendancePolicyResolver');
const { isOvernight, scheduledMinute, punchMinute } = require('./shiftTimeline');
const fields = ['time_in', 'break_out', 'break_in', 'time_out'];
const slotFields = { am_in: 'time_in', am_out: 'break_out', pm_in: 'break_in', pm_out: 'time_out' };

function uncoveredMinutes(start, end, holidayCoverage) {
  const span = Math.max(0, end - start);
  const from = holidayCoverage === 'am_only' ? 0 : holidayCoverage === 'pm_only' ? 720 : null;
  return from == null ? span : span - Math.max(0, Math.min(end, from + 720) - Math.max(start, from));
}

function uncoveredPenalties(record, shift, date, segments, holidayCoverage, now) {
  const type = shiftAttendance.getShiftType(shift);
  const start = shift.startMinutes;
  const end = scheduledMinute(shift, shift.endMinutes);
  const amEnd = scheduledMinute(shift, shiftAttendance.getExpectedAmEndMinutes(shift));
  const pmStart = scheduledMinute(shift, shiftAttendance.getExpectedPmStartMinutes(shift));
  const session = (from, to, inField, outField, inSlot, outSlot) => ({ from, to, inField, outField, inSlot, outSlot });
  const sessions = type === 'full_day' ? [
    session(start, amEnd, 'time_in', 'break_out', 'AM IN', 'AM OUT'),
    session(pmStart, end, 'break_in', 'time_out', 'PM IN', 'PM OUT'),
  ] : type === 'am_only' ? [session(start, end, 'time_in', 'break_out', 'AM IN', 'AM OUT')]
    : type === 'pm_only' ? [session(start, end, 'break_in', 'time_out', 'PM IN', 'PM OUT')]
      : [session(start, end, 'time_in', 'time_out', 'AM IN', 'PM OUT')];
  let late = 0, under = 0;
  const current = punchMinute(now, date);
  for (const s of sessions) {
    if (s.from == null || s.to == null) continue;
    const coveredIn = segments.has(s.inSlot), coveredOut = segments.has(s.outSlot);
    const inValue = record[s.inField] || (type === 'pm_only' ? record.time_in : null);
    const outValue = record[s.outField] || (type === 'am_only' ? record.time_out : null);
    const from = coveredIn ? s.from : punchMinute(inValue, date);
    const to = coveredOut ? s.to : punchMinute(outValue, date);
    // An approved slot substitutes its scheduled boundary for assessment only.
    if (!coveredIn && from != null) late += uncoveredMinutes(s.from + (shift.graceMinutes || 0), Math.min(from, s.to), holidayCoverage);
    if ((from == null || to == null) && current > s.to) {
      under += uncoveredMinutes(s.from, s.to, holidayCoverage);
    } else if (!coveredOut && to != null) {
      under += uncoveredMinutes(Math.max(to, s.from), s.to, holidayCoverage);
    }
  }
  return { late, under };
}

function isFullDayLeave(leave) {
  if (!leave) return false;
  const days = Number(leave.number_of_days ?? leave.total_days ?? 1);
  const start = leave.start_date ?? leave.sd;
  const end = leave.end_date ?? leave.ed;
  return !(days > 0 && days < 1 &&
    (!start || !end || String(start).slice(0, 10) === String(end).slice(0, 10)));
}

async function projectAttendanceCoverage({ record, date, shiftInfo, holidayInfo = null,
  leave = null, locator = null, policy = null, now = new Date() }) {
  const shift = normalizeShiftInfo(shiftInfo);
  const result = { ...record };
  const holidayCoverage = holidayInfo?.coverage || (holidayInfo ? 'whole_day' : null);
  const locatorState = evaluateLocatorCoverage({ locator, shiftInfo: shift, holidayInfo, date });
  const fullLeave = isFullDayLeave(leave);
  let fullCoverage = holidayCoverage === 'whole_day' || fullLeave || locatorState.isFullCoverage || locatorState.coveredSlots.length === 4;
  const hidden = new Set();
  for (const slot of locatorState.coveredSlots) hidden.add(slotFields[slot]);

  if (holidayCoverage === 'am_only' || holidayCoverage === 'pm_only') {
    const type = shiftAttendance.getShiftType(shift);
    if (isOvernight(shift)) {
      // Partial holidays cover the named half of the shift-start calendar day.
      const slotMinutes = { time_in: shift.startMinutes,
        break_out: scheduledMinute(shift, shiftAttendance.getExpectedAmEndMinutes(shift)),
        break_in: scheduledMinute(shift, shiftAttendance.getExpectedPmStartMinutes(shift)),
        time_out: scheduledMinute(shift, shift.endMinutes) };
      for (const [field, minute] of Object.entries(slotMinutes)) {
        if (minute != null && (holidayCoverage === 'am_only'
          ? minute >= 0 && minute < 720 : minute >= 720 && minute < 1440)) hidden.add(field);
      }
    } else if (type === 'single_session') {
      if ((shift.startMinutes < 720) === (holidayCoverage === 'am_only')) {
        for (const field of fields) hidden.add(field);
      }
    } else {
      for (const field of holidayCoverage === 'am_only' ? fields.slice(0, 2) : fields.slice(2)) hidden.add(field);
    }
  }
  // Single-session/legacy AM/PM records can store the session in either pair.
  const type = shiftAttendance.getShiftType(shift);
  if (type === 'pm_only' && hidden.has('break_in')) hidden.add('time_in');
  if (type === 'am_only' && hidden.has('break_out')) hidden.add('time_out');
  if (type === 'single_session') {
    if (hidden.has('time_in')) hidden.add('break_in');
    if (hidden.has('time_out')) hidden.add('break_out');
  }
  // A half-day holiday can cover an entire AM-only/PM-only assignment.
  const required = expectedLocatorSlotsForShift(shift, null, date);
  if (required.length && required.every((slot) => hidden.has(slotFields[slot]))) fullCoverage = true;
  if (fullCoverage) for (const field of fields) hidden.add(field);
  if (hidden.size === 0) return result;
  for (const field of hidden) result[field] = null;
  result.source = 'adjusted';
  result.pm_status = hidden.has('break_in') ? null : result.pm_status;
  if (fullCoverage) {
    result.status = holidayInfo ? 'holiday' : fullLeave ? 'on_leave' : 'on_field';
    result.total_hours = null;
    result.late_minutes = 0;
    result.undertime_minutes = 0;
    result.pm_status = null;
    return result;
  }
  result.total_hours = shift ? shiftAttendance.computeTotalHoursFromRecord(
    { ...result, record_date: date }, shift) : null;
  if (!shift) return result;
  const segments = new Set(locatorCoverageSegments(locator).map((slot) => slot.toUpperCase()));
  const raw = uncoveredPenalties(record, shift, date, segments, holidayCoverage, now);
  const adjusted = calculateAttendancePolicyPenalties(policy || {
    deductLate: true, deductUndertime: true, deductionMultiplier: 1,
  }, raw.late, raw.under);
  result.late_minutes = adjusted.lateMinutes;
  result.undertime_minutes = adjusted.undertimeMinutes;
  if (!holidayInfo && result.status !== 'not_tracked') {
    result.status = adjusted.lateMinutes > 0 ? 'late' : 'present';
  }
  return result;
}

module.exports = { projectAttendanceCoverage, isFullDayLeave };
