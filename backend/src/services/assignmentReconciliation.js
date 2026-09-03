'use strict';

const {
  dateOnly,
  enqueueEmployeeRangeReconciliation,
} = require('./dtrMonthEndReconciliation');
const {
  clearBiometricAttendancePolicyCache,
  processBiometricLogsToSummary,
} = require('./biometricProcessing');

const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';

function dateInTimeZone(now = new Date(), timeZone = HRMS_TIMEZONE) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function affectedAssignmentDateRange(before, after, { today = dateInTimeZone() } = {}) {
  const records = [
    ...(Array.isArray(before) ? before : before ? [before] : []),
    ...(Array.isArray(after) ? after : after ? [after] : []),
  ];
  const starts = records.map((row) => dateOnly(row?.effective_from)).filter(Boolean);
  if (starts.length === 0) return null;

  const dateFrom = starts.sort()[0];
  if (dateFrom > today) return null;
  const ends = records
    .map((row) => dateOnly(row?.effective_to) || today)
    .filter(Boolean)
    .sort();
  const dateTo = ends.length > 0 && ends.at(-1) < today ? ends.at(-1) : today;
  return dateFrom <= dateTo ? { dateFrom, dateTo } : null;
}

async function queueAssignmentReconciliation(
  db,
  { employeeId, before, after, reason, metadata = null } = {}
) {
  const range = affectedAssignmentDateRange(before, after);
  if (!range) return { range: null, count: 0, months: [] };
  const queued = await enqueueEmployeeRangeReconciliation(db, {
    employeeId,
    ...range,
    reason,
    metadata,
  });
  return { range, ...queued };
}

async function rebuildAssignmentDtr(employeeId, range) {
  if (!employeeId || !range?.dateFrom || !range?.dateTo) {
    return { inserted: 0, updated: 0 };
  }
  clearBiometricAttendancePolicyCache({
    employeeId,
    dateFrom: range.dateFrom,
    dateTo: range.dateTo,
  });
  return processBiometricLogsToSummary(
    [String(employeeId)],
    range.dateFrom,
    range.dateTo
  );
}

async function rebuildAfterAssignmentCommit(employeeId, queued) {
  if (!queued?.range) return { required: false, queued_months: [] };
  try {
    const rebuilt = await rebuildAssignmentDtr(employeeId, queued.range);
    return {
      required: queued.count > 0,
      queued_months: queued.months,
      affected_from: queued.range.dateFrom,
      affected_to: queued.range.dateTo,
      dtr_rows_inserted: Number(rebuilt?.inserted || 0),
      dtr_rows_rebuilt: Number(rebuilt?.updated || 0),
    };
  } catch (error) {
    console.error('[assignmentReconciliation] immediate DTR rebuild failed', {
      employeeId,
      range: queued.range,
      error: error?.message || String(error),
    });
    return {
      required: queued.count > 0,
      queued_months: queued.months,
      affected_from: queued.range.dateFrom,
      affected_to: queued.range.dateTo,
      warning: 'The assignment was saved, but DTR rebuilding will retry during reconciliation.',
    };
  }
}

module.exports = {
  affectedAssignmentDateRange,
  dateInTimeZone,
  queueAssignmentReconciliation,
  rebuildAfterAssignmentCommit,
  rebuildAssignmentDtr,
};
