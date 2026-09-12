'use strict';

const { dateInTimeZone } = require('./assignmentReconciliation');

const ASSIGNMENT_STATUSES = Object.freeze([
  'Current',
  'Upcoming',
  'Expired',
  'Archived',
  'All',
]);
const DEFAULT_ASSIGNMENT_HISTORY_START_DATE = '1900-01-01';
const DEFAULT_ASSIGNMENT_FUTURE_HORIZON_YEARS = 10;

class AssignmentStatusError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AssignmentStatusError';
    this.statusCode = 400;
  }
}

function normalizeAssignmentStatus(value, fallback = 'Current') {
  const raw = String(value == null || value === '' ? fallback : value).trim();
  const normalized = raw.toLowerCase();
  if (normalized === 'active') return 'Current';
  if (normalized === 'inactive') return 'Archived';
  const match = ASSIGNMENT_STATUSES.find(
    (status) => status.toLowerCase() === normalized
  );
  if (!match) {
    throw new AssignmentStatusError(
      `status must be one of: ${ASSIGNMENT_STATUSES.join(', ')}`
    );
  }
  return match;
}

function computedAssignmentStatusSql(alias, todayPlaceholder) {
  return `CASE
    WHEN COALESCE(${alias}.is_active, true) = false THEN 'Archived'
    WHEN ${alias}.effective_from > ${todayPlaceholder}::date THEN 'Upcoming'
    WHEN ${alias}.effective_to IS NOT NULL
      AND ${alias}.effective_to < ${todayPlaceholder}::date THEN 'Expired'
    ELSE 'Current'
  END`;
}

function assignmentStatusWhereSql(alias, status, todayPlaceholder) {
  const normalized = normalizeAssignmentStatus(status);
  if (normalized === 'All') return '';
  return `AND (${computedAssignmentStatusSql(alias, todayPlaceholder)}) = '${normalized}'`;
}

function assignmentStatusContext(value, { fallback = 'Current', now = new Date() } = {}) {
  return {
    status: normalizeAssignmentStatus(value, fallback),
    today: dateInTimeZone(now),
  };
}

function normalizeDateOnly(value) {
  const match = String(value || '').match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : null;
}

function normalizeFutureHorizonYears(value) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= 100
    ? parsed
    : DEFAULT_ASSIGNMENT_FUTURE_HORIZON_YEARS;
}

function assignmentDatePickerContext({
  dateHired = null,
  separationDate = null,
  earliestEffectiveDate = null,
  now = new Date(),
  historyStartDate = process.env.ASSIGNMENT_HISTORY_START_DATE,
  futureHorizonYears = process.env.ASSIGNMENT_FUTURE_HORIZON_YEARS,
} = {}) {
  const officialDate = dateInTimeZone(now);
  const fallbackFirstDate =
    normalizeDateOnly(historyStartDate) || DEFAULT_ASSIGNMENT_HISTORY_START_DATE;
  const firstCandidates = [dateHired, earliestEffectiveDate]
    .map(normalizeDateOnly)
    .filter(Boolean)
    .sort();
  const firstDate = firstCandidates[0] || fallbackFirstDate;
  const horizonYears = normalizeFutureHorizonYears(futureHorizonYears);
  const lastYear = Number(officialDate.slice(0, 4)) + horizonYears;
  const horizonDate = `${String(lastYear).padStart(4, '0')}-12-31`;
  const separatedOn = normalizeDateOnly(separationDate);
  let lastDate = separatedOn && separatedOn < horizonDate
    ? separatedOn
    : horizonDate;
  if (lastDate < firstDate) lastDate = firstDate;

  return {
    officialDate,
    firstDate,
    lastDate,
    futureHorizonYears: horizonYears,
  };
}

module.exports = {
  ASSIGNMENT_STATUSES,
  AssignmentStatusError,
  assignmentDatePickerContext,
  assignmentStatusContext,
  assignmentStatusWhereSql,
  computedAssignmentStatusSql,
  normalizeAssignmentStatus,
};
