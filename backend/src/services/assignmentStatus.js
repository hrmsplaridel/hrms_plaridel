'use strict';

const { dateInTimeZone } = require('./assignmentReconciliation');

const ASSIGNMENT_STATUSES = Object.freeze([
  'Current',
  'Upcoming',
  'Expired',
  'Archived',
  'All',
]);

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

module.exports = {
  ASSIGNMENT_STATUSES,
  AssignmentStatusError,
  assignmentStatusContext,
  assignmentStatusWhereSql,
  computedAssignmentStatusSql,
  normalizeAssignmentStatus,
};
