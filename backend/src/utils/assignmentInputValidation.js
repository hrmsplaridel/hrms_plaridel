'use strict';

function parseAssignmentDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith('0000-')) {
    return null;
  }
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
    ? value : null;
}

function assignmentInputError(body) {
  if (body.is_active !== undefined && typeof body.is_active !== 'boolean') {
    return 'is_active must be a boolean.';
  }
  if (body.effective_from !== undefined && !parseAssignmentDate(body.effective_from)) {
    return 'Invalid effective_from: use a real date in YYYY-MM-DD format';
  }
  // Null/empty end dates explicitly clear the end; omitted fields retain the
  // existing value on updates. Neither case is an invalid calendar date.
  if (body.effective_to !== undefined && body.effective_to !== null && body.effective_to !== '' &&
      !parseAssignmentDate(body.effective_to)) {
    return 'Invalid effective_to: use a real date in YYYY-MM-DD format';
  }
  return null;
}

module.exports = { parseAssignmentDate, assignmentInputError };
