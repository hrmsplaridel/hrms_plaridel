'use strict';

const {
  getExpectedAmEndMinutes,
  getExpectedWorkMinutesForCoverage,
} = require('./shiftAttendance');

function addDaysToIsoDate(dateStr, days) {
  const [year, month, day] = String(dateStr).split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function isoWeekdayFromDateStr(dateStr) {
  const date = new Date(`${dateStr}T00:00:00Z`);
  const weekday = date.getUTCDay();
  return weekday === 0 ? 7 : weekday;
}

function isAttendanceDateFinalized({
  dateStr,
  todayStr,
  nowMinutes,
  shiftInfo,
  holidayInfo,
}) {
  const yesterdayStr = addDaysToIsoDate(todayStr, -1);
  if (dateStr < yesterdayStr) return true;
  if (!shiftInfo) return true;

  const workingDays = Array.isArray(shiftInfo.workingDays)
    ? shiftInfo.workingDays
    : [];
  if (
    workingDays.length > 0 &&
    !workingDays.includes(isoWeekdayFromDateStr(dateStr))
  ) {
    return true;
  }

  const coverage = String(holidayInfo?.coverage || '').trim().toLowerCase();
  if (coverage === 'whole_day') return true;
  const crossesMidnight =
    shiftInfo.startMinutes != null &&
    shiftInfo.endMinutes != null &&
    shiftInfo.endMinutes <= shiftInfo.startMinutes;
  if (
    coverage &&
    !crossesMidnight &&
    getExpectedWorkMinutesForCoverage(shiftInfo, coverage) === 0
  ) {
    return true;
  }

  const requiredEndMinutes = coverage === 'pm_only'
    ? getExpectedAmEndMinutes(shiftInfo)
    : shiftInfo.endMinutes;
  if (requiredEndMinutes == null) return dateStr < todayStr;

  const isOvernight =
    coverage !== 'pm_only' &&
    shiftInfo.startMinutes != null &&
    requiredEndMinutes <= shiftInfo.startMinutes;
  if (dateStr === todayStr) {
    return !isOvernight && nowMinutes > requiredEndMinutes;
  }
  if (dateStr === yesterdayStr && isOvernight) {
    return nowMinutes > requiredEndMinutes;
  }
  return dateStr < todayStr;
}

module.exports = {
  addDaysToIsoDate,
  isAttendanceDateFinalized,
};
