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

function normalizedTime(value) {
  if (value === null || value === undefined || value === '') return null;
  return String(value).trim().slice(0, 8);
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
  SHIFT_SCHEDULE_FIELDS,
  ShiftLifecycleError,
  changedShiftScheduleFields,
  ensureShiftScheduleChangeAllowed,
  lockShiftForUpdate,
  shiftAssignmentHistoryCount,
};
