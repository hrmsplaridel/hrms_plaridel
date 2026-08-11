const { getExpectedLogsForDay } = require('./shiftAttendance');

const LOCATOR_SLOTS = Object.freeze(['am_in', 'am_out', 'pm_in', 'pm_out']);
const SLOT_LABELS = Object.freeze({
  am_in: 'AM in',
  am_out: 'AM out',
  pm_in: 'PM in',
  pm_out: 'PM out',
});

function timeToMinutes(value) {
  if (value == null || value === '') return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  const match = String(value).trim().match(/^(\d{1,2}):(\d{2})/);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return null;
  return hours * 60 + minutes;
}

function normalizeShiftInfo(shiftInfo) {
  if (!shiftInfo) return null;
  return {
    ...shiftInfo,
    startMinutes:
      shiftInfo.startMinutes ??
      shiftInfo.start_minutes ??
      timeToMinutes(shiftInfo.start_time ?? shiftInfo.startTime),
    endMinutes:
      shiftInfo.endMinutes ??
      shiftInfo.end_minutes ??
      timeToMinutes(shiftInfo.end_time ?? shiftInfo.endTime),
    breakEndMinutes:
      shiftInfo.breakEndMinutes ??
      shiftInfo.break_end_minutes ??
      timeToMinutes(shiftInfo.break_end ?? shiftInfo.breakEnd),
    punchMode: shiftInfo.punchMode ?? shiftInfo.punch_mode ?? 'auto',
  };
}

function isoWeekday(date) {
  if (!date) return null;
  const parsed = new Date(`${String(date).slice(0, 10)}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return null;
  const day = parsed.getUTCDay();
  return day === 0 ? 7 : day;
}

function isShiftWorkingDate(shiftInfo, date) {
  if (!date) return true;
  const workingDays = shiftInfo?.workingDays ?? shiftInfo?.working_days;
  if (!Array.isArray(workingDays) || workingDays.length === 0) return true;
  const weekday = isoWeekday(date);
  return weekday != null && workingDays.map(Number).includes(weekday);
}

function expectedLocatorSlotsForShift(shiftInfo, holidayInfo = null, date = null) {
  const normalizedShift = normalizeShiftInfo(shiftInfo);
  if (!normalizedShift || !isShiftWorkingDate(normalizedShift, date)) return [];

  const expected = getExpectedLogsForDay(normalizedShift, holidayInfo);
  if (expected.needsInOut) return ['am_in', 'pm_out'];

  const slots = [];
  if (expected.needsAm) slots.push('am_in', 'am_out');
  if (expected.needsPm) slots.push('pm_in', 'pm_out');
  return slots;
}

function isCovered(value) {
  return value === true || value === 1 || String(value).toLowerCase() === 'true';
}

function locatorSlotKey(value) {
  const normalized = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, '_');
  return LOCATOR_SLOTS.includes(normalized) ? normalized : null;
}

function locatorSlotLabel(slot) {
  return SLOT_LABELS[locatorSlotKey(slot)] || String(slot || '');
}

function emptyLocatorCoverage() {
  return {
    am_in: false,
    am_out: false,
    pm_in: false,
    pm_out: false,
  };
}

function normalizeLocatorCoverage(locator) {
  const normalized = emptyLocatorCoverage();
  if (!locator) return normalized;

  const source = locator.coverage && typeof locator.coverage === 'object'
    ? { ...locator, ...locator.coverage }
    : locator;
  for (const slot of LOCATOR_SLOTS) {
    normalized[slot] = isCovered(source[slot]);
  }
  for (const segment of Array.isArray(locator.segments) ? locator.segments : []) {
    const slot = locatorSlotKey(segment);
    if (slot) normalized[slot] = true;
  }
  return normalized;
}

function mergeLocatorCoverages(locators) {
  const merged = emptyLocatorCoverage();
  for (const locator of Array.isArray(locators) ? locators : [locators]) {
    const coverage = normalizeLocatorCoverage(locator);
    for (const slot of LOCATOR_SLOTS) merged[slot] ||= coverage[slot];
  }
  return merged;
}

function locatorCoverageSegments(locator) {
  const coverage = normalizeLocatorCoverage(locator);
  return LOCATOR_SLOTS.filter((slot) => coverage[slot]).map(locatorSlotLabel);
}

function evaluateLocatorCoverage({
  locator = null,
  locators = null,
  shiftInfo = null,
  holidayInfo = null,
  date = null,
} = {}) {
  const coverage = mergeLocatorCoverages(locators || locator);
  const expectedSlots = expectedLocatorSlotsForShift(shiftInfo, holidayInfo, date);
  const coveredSlots = LOCATOR_SLOTS.filter((slot) => coverage[slot]);
  const missingSlots = expectedSlots.filter((slot) => !coverage[slot]);
  return {
    coverage,
    expectedSlots,
    coveredSlots,
    missingSlots,
    hasAnyCoverage: coveredSlots.length > 0,
    isFullCoverage: expectedSlots.length > 0 && missingSlots.length === 0,
  };
}

function locatorCoversExpectedShiftSlots(locator, shiftInfo, holidayInfo = null, date = null) {
  return evaluateLocatorCoverage({ locator, shiftInfo, holidayInfo, date }).isFullCoverage;
}

module.exports = {
  LOCATOR_SLOTS,
  emptyLocatorCoverage,
  evaluateLocatorCoverage,
  expectedLocatorSlotsForShift,
  isShiftWorkingDate,
  locatorCoverageSegments,
  locatorCoversExpectedShiftSlots,
  locatorSlotKey,
  locatorSlotLabel,
  mergeLocatorCoverages,
  normalizeLocatorCoverage,
  normalizeShiftInfo,
};
