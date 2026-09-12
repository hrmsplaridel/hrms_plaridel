'use strict';

const HOLIDAY_TYPES = new Set(['regular', 'special', 'local', 'work_suspension']);
const HOLIDAY_COVERAGE = new Set(['whole_day', 'am_only', 'pm_only']);

function badRequest(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function normalizeBoolean(value, field, defaultValue) {
  if (value === undefined) return defaultValue;
  if (typeof value !== 'boolean') {
    throw badRequest(`${field} must be true or false.`);
  }
  return value;
}

function normalizeEnum(value, field, allowed, defaultValue) {
  if (value === undefined) return defaultValue;
  if (typeof value !== 'string' || !allowed.has(value)) {
    throw badRequest(`${field} must be one of: ${[...allowed].join(', ')}.`);
  }
  return value;
}

function normalizeHolidayType(value, defaultValue = 'regular') {
  return normalizeEnum(value, 'holiday_type', HOLIDAY_TYPES, defaultValue);
}

function normalizeHolidayCoverage(value, defaultValue = 'whole_day') {
  return normalizeEnum(value, 'coverage', HOLIDAY_COVERAGE, defaultValue);
}

function normalizeRequiredName(value, field = 'name') {
  if (typeof value !== 'string' || !value.trim()) {
    throw badRequest(`${field} must be a nonempty string.`);
  }
  return value.trim();
}

function normalizeIsoDate(value, field) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw badRequest(`${field} must be a real date in YYYY-MM-DD format.`);
  }
  const [year, month, day] = value.split('-').map(Number);
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const daysInMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (year === 0 || month < 1 || month > 12 || day < 1 || day > daysInMonth[month - 1]) {
    throw badRequest(`${field} must be a real date in YYYY-MM-DD format.`);
  }
  return value;
}

function validateCoverageForType(holidayType, coverage) {
  if (!['special', 'work_suspension'].includes(holidayType) && coverage !== 'whole_day') {
    throw badRequest('coverage must be whole_day for regular and local holidays.');
  }
}

module.exports = {
  HOLIDAY_COVERAGE,
  HOLIDAY_TYPES,
  badRequest,
  normalizeBoolean,
  normalizeHolidayCoverage,
  normalizeHolidayType,
  normalizeIsoDate,
  normalizeRequiredName,
  validateCoverageForType,
};
