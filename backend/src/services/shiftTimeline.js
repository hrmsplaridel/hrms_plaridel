'use strict';

const { addIsoDays, localTimestampParts } = require('./dtrPunchDateValidation');
const TIME_ZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';

function isOvernight(shift) {
  return shift?.startMinutes != null && shift?.endMinutes != null &&
    shift.endMinutes < shift.startMinutes;
}

function scheduledMinute(shift, minute) {
  if (minute == null) return null;
  return isOvernight(shift) && minute < shift.startMinutes ? minute + 1440 : minute;
}

function timeline(shift) {
  return {
    ...shift,
    endMinutes: scheduledMinute(shift, shift.endMinutes),
    breakStartMinutes: scheduledMinute(shift, shift.breakStartMinutes ?? 720),
    breakEndMinutes: scheduledMinute(shift, shift.breakEndMinutes ?? 780),
  };
}

function punchMinute(value, date, timeZone = TIME_ZONE) {
  const local = localTimestampParts(value, timeZone);
  if (!local) return null;
  return (Date.parse(local.date) - Date.parse(date)) / 86400000 * 1440 + local.minutes;
}

function hasShiftEnded(shift, date, now = new Date(), timeZone = TIME_ZONE) {
  const minute = punchMinute(now, date, timeZone);
  return minute != null && minute > scheduledMinute(shift, shift.endMinutes);
}

function uncoveredMinutes(start, end, coverage) {
  const span = Math.max(0, end - start);
  if (coverage === 'whole_day') return 0;
  const coveredStart = coverage === 'am_only' ? 0 : coverage === 'pm_only' ? 720 : null;
  if (coveredStart == null) return span;
  return span - Math.max(0, Math.min(end, coveredStart + 720) - Math.max(start, coveredStart));
}

function expectedNightMinutes(shift, coverage) {
  const schedule = timeline(shift);
  const plannedBreak = shift.punchMode === 'full_day'
    ? schedule.breakEndMinutes - schedule.breakStartMinutes : 0;
  const remaining = uncoveredMinutes(shift.startMinutes, schedule.endMinutes, coverage);
  const coveredBreak = plannedBreak > 0
    ? uncoveredMinutes(schedule.breakStartMinutes, schedule.breakEndMinutes, coverage) : 0;
  return Math.max(0, remaining - coveredBreak);
}

function overnightPenalties(shift, date, punches, now = new Date(), coverage = null, coveredSegments = []) {
  const schedule = timeline(shift);
  const start = punchMinute(punches.timeIn || (shift.punchMode !== 'full_day' ? punches.breakIn : null), date);
  const end = punchMinute(punches.timeOut, date);
  const breakOut = punchMinute(punches.breakOut, date);
  const breakIn = punchMinute(punches.breakIn, date);
  const split = shift.punchMode === 'full_day';
  const grace = shift.graceMinutes || 0;
  const covered = new Set(coveredSegments);
  let late = start == null || covered.has('AM IN') ? 0 :
    uncoveredMinutes(shift.startMinutes + grace, Math.min(start, split ? schedule.breakStartMinutes : schedule.endMinutes), coverage);
  if (split && breakIn != null && !covered.has('PM IN')) {
    late += uncoveredMinutes(schedule.breakEndMinutes + grace, Math.min(breakIn, schedule.endMinutes), coverage);
  }
  let under = end == null || covered.has('PM OUT') ? 0 :
    uncoveredMinutes(Math.max(end, split ? schedule.breakEndMinutes : shift.startMinutes), schedule.endMinutes, coverage);
  if (split && breakOut != null && !covered.has('AM OUT')) {
    under += uncoveredMinutes(Math.max(breakOut, shift.startMinutes), schedule.breakStartMinutes, coverage);
  }
  if (split && (start == null || breakOut == null) &&
      punchMinute(now, date) >= schedule.breakEndMinutes &&
      !(covered.has('AM IN') && covered.has('AM OUT'))) {
    under = uncoveredMinutes(shift.startMinutes, schedule.breakStartMinutes, coverage) +
      (end == null ? 0 : uncoveredMinutes(Math.max(end, schedule.breakEndMinutes), schedule.endMinutes, coverage));
  }
  if (end == null && (start != null || breakIn != null) &&
      !covered.has('PM OUT') && hasShiftEnded(shift, date, now)) {
    under = expectedNightMinutes(shift, coverage);
  }
  return { lateMinutes: late, undertimeMinutes: under };
}

// Resolve each raw punch once. The previous day's night shift takes priority
// within its capture window; out-of-window night punches remain unmatched.
async function groupPunchesForSchedules(rows, resolveShift, dateFrom, dateTo, timeZone = TIME_ZONE) {
  const groups = new Map();
  const cache = new Map();
  async function shiftFor(user, date) {
    const key = `${user}|${date}`;
    if (!cache.has(key)) cache.set(key, await resolveShift(user, date));
    return cache.get(key);
  }
  for (const row of rows) {
    for (const punch of row.punches || []) {
      const local = localTimestampParts(punch, timeZone);
      if (!local) continue;
      let date = local.date;
      const previous = addIsoDays(date, -1);
      const priorShift = await shiftFor(row.user_id, previous);
      const current = await shiftFor(row.user_id, date);
      const priorLimit = isOvernight(priorShift) && priorShift.isWorkingDay !== false
        ? priorShift.endMinutes + (priorShift.captureWindowMinutes ?? 120) : -1;
      const closerToCurrent = current?.isWorkingDay !== false && current?.startMinutes != null &&
        Math.abs(local.minutes - current.startMinutes) < Math.abs(local.minutes - (priorShift?.endMinutes ?? -1440));
      if (local.minutes <= priorLimit && !closerToCurrent) {
        date = previous;
      } else if (isOvernight(current) && (current.isWorkingDay === false ||
          local.minutes < current.startMinutes - (current.captureWindowMinutes ?? 120))) {
        continue;
      }
      if (date > dateTo || date < addIsoDays(dateFrom, -1)) continue;
      if (date < dateFrom && !isOvernight(await shiftFor(row.user_id, date))) continue;
      const key = `${row.user_id}|${date}`;
      if (!groups.has(key)) groups.set(key, { user_id: row.user_id, attendance_date: date, punches: [] });
      groups.get(key).punches.push(punch);
    }
  }
  for (const group of groups.values()) {
    group.punches.sort((a, b) => new Date(a) - new Date(b));
    if (isOvernight(await shiftFor(group.user_id, group.attendance_date))) {
      const retained = [];
      for (const p of group.punches) {
        if (!retained.length || new Date(p) - new Date(retained[retained.length - 1]) >= 60000) retained.push(p);
      }
      group.punches = retained;
    }
  }
  return [...groups.values()];
}

module.exports = { isOvernight, scheduledMinute, timeline, punchMinute, hasShiftEnded, expectedNightMinutes, uncoveredMinutes,
  overnightPenalties, groupPunchesForSchedules };
