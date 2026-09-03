'use strict';

class ShiftLifecycleError extends Error {
  constructor(message, statusCode = 409, details = null) {
    super(message);
    this.name = 'ShiftLifecycleError';
    this.statusCode = statusCode;
    this.details = details;
  }
}

const SHIFT_SCHEDULE_FIELDS = Object.freeze([
  'start_time',
  'end_time',
  'break_end',
  'punch_mode',
  'grace_period_minutes',
  'working_days',
]);

const SHIFT_DEACTIVATION_DEPENDENCIES = Object.freeze([
  {
    key: 'assignments',
    label: 'current or future employee assignments',
  },
  {
    key: 'policy_periods',
    label: 'current or future attendance-policy periods',
  },
]);

const SHIFT_DELETE_DEPENDENCIES = Object.freeze([
  {
    key: 'assignments',
    label: 'employee assignments',
    table: 'assignments',
    column: 'shift_id',
  },
  {
    key: 'dtr_records',
    label: 'DTR records',
    table: 'dtr_daily_summary',
    column: 'shift_id',
  },
  {
    key: 'policy_periods',
    label: 'attendance-policy periods',
    table: 'policy_assignments',
    column: 'shift_id',
  },
]);

function normalizedTime(value) {
  if (value === null || value === undefined || value === '') return null;
  return String(value).trim().slice(0, 8);
}

function parseShiftTimeInput(
  value,
  { field, label, required = true }
) {
  const isEmpty = value == null || (typeof value === 'string' && value.trim() === '');
  if (isEmpty) {
    if (!required) return null;
    throw new ShiftLifecycleError(
      `${label} is required.`,
      400,
      { fields: { [field]: `${label} is required.` } }
    );
  }
  if (typeof value !== 'string') {
    throw new ShiftLifecycleError(
      `${label} must be a valid time.`,
      400,
      { fields: { [field]: `${label} must use HH:mm or HH:mm:ss in 24-hour format.` } }
    );
  }
  const match = value.trim().match(/^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$/);
  if (!match) {
    throw new ShiftLifecycleError(
      `${label} must be a valid time.`,
      400,
      { fields: { [field]: `${label} must use HH:mm or HH:mm:ss in 24-hour format.` } }
    );
  }
  return `${match[1]}:${match[2]}:${match[3] || '00'}`;
}

function timeMinutes(value) {
  const normalized = normalizedTime(value);
  const match = normalized?.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  const second = Number(match[3] || 0);
  if (hour > 23 || minute > 59 || second > 59) return null;
  return (hour * 60) + minute + (second / 60);
}

function ensureSupportedShiftRange(startTime, endTime) {
  const startMinutes = timeMinutes(startTime);
  const endMinutes = timeMinutes(endTime);
  if (startMinutes == null || endMinutes == null) {
    throw new ShiftLifecycleError(
      'Start Time and End Time must be valid times.',
      400,
      {
        fields: {
          start_time: 'Enter a valid Start Time.',
          end_time: 'Enter a valid End Time.',
        },
      }
    );
  }
  if (endMinutes <= startMinutes) {
    throw new ShiftLifecycleError(
      'Overnight shifts are not currently supported. End Time must be later than Start Time.',
      400,
      {
        fields: {
          end_time: 'End Time must be later than Start Time.',
        },
      }
    );
  }
}

function normalizedWorkingDays(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((day) => Number(day)).filter(Number.isFinite))]
    .sort((a, b) => a - b);
}

function normalizedScheduleValue(field, value) {
  if (field === 'start_time' || field === 'end_time' || field === 'break_end') {
    return normalizedTime(value);
  }
  if (field === 'working_days') return normalizedWorkingDays(value);
  if (field === 'grace_period_minutes') return Number(value || 0);
  if (field === 'punch_mode') return String(value || 'auto').trim().toLowerCase();
  return value;
}

function changedShiftScheduleFields(current = {}, changes = {}) {
  return SHIFT_SCHEDULE_FIELDS.filter((field) => {
    if (!Object.prototype.hasOwnProperty.call(changes, field)) return false;
    const before = normalizedScheduleValue(field, current[field]);
    const after = normalizedScheduleValue(field, changes[field]);
    if (Array.isArray(before) || Array.isArray(after)) {
      return JSON.stringify(before) !== JSON.stringify(after);
    }
    return before !== after;
  });
}

async function lockShiftForUpdate(db, shiftId) {
  const result = await db.query(
    `SELECT id, shift_number, name, start_time, end_time, break_end,
            punch_mode, grace_period_minutes, working_days, is_active
       FROM shifts
      WHERE id = $1::uuid
      FOR UPDATE`,
    [shiftId]
  );
  return result.rows[0] || null;
}

async function shiftAssignmentHistoryCount(db, shiftId) {
  const result = await db.query(
    `SELECT COUNT(*)::int AS assignment_history_count
       FROM assignments
      WHERE shift_id = $1::uuid`,
    [shiftId]
  );
  return Number(result.rows[0]?.assignment_history_count || 0);
}

function shiftDeactivationCountsSql(
  shiftIdExpression = 'shifts.id',
  todayPlaceholder = '$1'
) {
  return `(
            SELECT COUNT(*)::int
              FROM assignments assignment
             WHERE assignment.shift_id = ${shiftIdExpression}
               AND assignment.is_active = true
               AND (
                 assignment.effective_to IS NULL
                 OR assignment.effective_to >= ${todayPlaceholder}::date
               )
          ) AS deactivation_assignments,
          (
            SELECT COUNT(*)::int
              FROM policy_assignments policy_period
             WHERE policy_period.shift_id = ${shiftIdExpression}
               AND policy_period.is_active = true
               AND (
                 policy_period.effective_to IS NULL
                 OR policy_period.effective_to >= ${todayPlaceholder}::date
               )
          ) AS deactivation_policy_periods`;
}

function shiftDeactivationCountsFromRow(row = {}) {
  return Object.fromEntries(
    SHIFT_DEACTIVATION_DEPENDENCIES.map(({ key }) => [
      key,
      Number(row[`deactivation_${key}`] || 0),
    ])
  );
}

function shiftDeactivationBlockers(counts = {}) {
  return SHIFT_DEACTIVATION_DEPENDENCIES
    .map(({ key, label }) => ({ key, label, count: Number(counts[key] || 0) }))
    .filter((item) => item.count > 0);
}

function shiftDependencyCountsSql(shiftIdExpression = 'shifts.id') {
  return SHIFT_DELETE_DEPENDENCIES
    .map(({ key, table, column }) => (
      `(SELECT COUNT(*)::int FROM ${table} dependency WHERE dependency.${column} = ${shiftIdExpression}) AS dependency_${key}`
    ))
    .join(',\n              ');
}

function shiftDependencyCountsFromRow(row = {}) {
  return Object.fromEntries(
    SHIFT_DELETE_DEPENDENCIES.map(({ key }) => [
      key,
      Number(row[`dependency_${key}`] || 0),
    ])
  );
}

function shiftDependencyBlockers(counts = {}) {
  return SHIFT_DELETE_DEPENDENCIES
    .map(({ key, label }) => ({ key, label, count: Number(counts[key] || 0) }))
    .filter((item) => item.count > 0);
}

async function shiftDependencyCounts(db, shiftId) {
  const result = await db.query(
    `SELECT ${shiftDependencyCountsSql('$1::uuid')}`,
    [shiftId]
  );
  return shiftDependencyCountsFromRow(result.rows[0]);
}

async function deleteUnusedShift(db, { shiftId, lockedShift = null }) {
  const shift = lockedShift || await lockShiftForUpdate(db, shiftId);
  if (!shift) {
    throw new ShiftLifecycleError('Shift not found', 404);
  }

  const dependencies = await shiftDependencyCounts(db, shiftId);
  const blockers = shiftDependencyBlockers(dependencies);
  if (blockers.length > 0) {
    const details = blockers
      .map((item) => `${item.count} ${item.label}`)
      .join(', ');
    throw new ShiftLifecycleError(
      `Shift cannot be permanently deleted because it is used by ${details}. Deactivate it after ending current and future periods instead.`,
      409,
      { blockers, dependencies }
    );
  }

  await db.query('DELETE FROM shifts WHERE id = $1::uuid', [shiftId]);
  return shift;
}

async function ensureShiftDeactivationAllowed(
  db,
  { shiftId, effectiveDate, lockedShift = null }
) {
  const shift = lockedShift || await lockShiftForUpdate(db, shiftId);
  if (!shift) {
    throw new ShiftLifecycleError('Shift not found', 404);
  }

  const result = await db.query(
    `SELECT ${shiftDeactivationCountsSql('$1::uuid', '$2')}`,
    [shiftId, effectiveDate]
  );
  const dependencies = shiftDeactivationCountsFromRow(result.rows[0]);
  const blockers = shiftDeactivationBlockers(dependencies);
  if (blockers.length > 0) {
    const details = blockers
      .map((item) => `${item.count} ${item.label}`)
      .join(', ');
    throw new ShiftLifecycleError(
      `Shift cannot be deactivated because it has ${details}. End or transfer these periods first.`,
      409,
      { blockers, dependencies, official_date: effectiveDate }
    );
  }
  return shift;
}

async function ensureShiftScheduleChangeAllowed(
  db,
  { shiftId, changes, lockedShift = null }
) {
  const shift = lockedShift || await lockShiftForUpdate(db, shiftId);
  if (!shift) {
    throw new ShiftLifecycleError('Shift not found', 404);
  }

  const changedFields = changedShiftScheduleFields(shift, changes);
  if (changedFields.length === 0) return shift;

  const assignmentHistoryCount = await shiftAssignmentHistoryCount(db, shiftId);
  if (assignmentHistoryCount > 0) {
    throw new ShiftLifecycleError(
      'This shift has assignment history, so its schedule cannot be changed. Create a new shift and use Assignment Management to start it on the required effective date.',
      409,
      {
        assignment_history_count: assignmentHistoryCount,
        changed_fields: changedFields,
      }
    );
  }
  return shift;
}

module.exports = {
  SHIFT_DEACTIVATION_DEPENDENCIES,
  SHIFT_DELETE_DEPENDENCIES,
  SHIFT_SCHEDULE_FIELDS,
  ShiftLifecycleError,
  changedShiftScheduleFields,
  deleteUnusedShift,
  ensureShiftDeactivationAllowed,
  ensureShiftScheduleChangeAllowed,
  ensureSupportedShiftRange,
  lockShiftForUpdate,
  parseShiftTimeInput,
  shiftAssignmentHistoryCount,
  shiftDeactivationBlockers,
  shiftDeactivationCountsFromRow,
  shiftDeactivationCountsSql,
  shiftDependencyBlockers,
  shiftDependencyCounts,
  shiftDependencyCountsFromRow,
  shiftDependencyCountsSql,
};
