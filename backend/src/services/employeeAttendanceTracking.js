'use strict';

const { dateOnly } = require('./holidayOverlay');
const { AssignmentTransitionError } = require('./assignmentTransition');

function cleanTrackingDate(value) {
  if (value === null || value === '') return null;
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new AssignmentTransitionError('Attendance tracking start must use YYYY-MM-DD');
  }
  const date = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new AssignmentTransitionError('Attendance tracking start is invalid');
  }
  return value;
}

async function loadTrackingStarts(db, employeeIds) {
  if (!employeeIds.length) return new Map();
  const result = await db.query(
    `SELECT id,attendance_tracking_start_date::text AS attendance_tracking_start_date,
       date_hired::text AS date_hired FROM users WHERE id=ANY($1::uuid[])`,
    [employeeIds]
  );
  return new Map(result.rows.map((row) => [String(row.id), {
    start: dateOnly(row.attendance_tracking_start_date),
    hired: dateOnly(row.date_hired),
  }]));
}

function isBeforeEmployeeTracking(employeeId, date, starts) {
  const start = starts?.get(String(employeeId))?.start;
  return !!start && dateOnly(date) < start;
}

function zeroDeduction() {
  return { late_minutes: 0, undertime_minutes: 0, absence_minutes: 0, total_minutes: 0, equivalent_day: 0 };
}

// The caller owns the assignment transaction, including rollback of this change.
async function updateEmployeeTrackingStart(db, { employeeId, value, actorId, assignmentId = null }) {
  if (value === undefined) return { changed: false };
  const next = cleanTrackingDate(value);
  // Serialize with opening balances and month-end posting before checking history.
  await db.query('SELECT pg_advisory_xact_lock(743022, 0)');
  const employee = (await db.query(
    `SELECT id,date_hired,attendance_tracking_start_date FROM users WHERE id=$1::uuid FOR UPDATE`,
    [employeeId]
  )).rows[0];
  if (!employee) throw new AssignmentTransitionError('Employee not found', 404);
  const before = dateOnly(employee.attendance_tracking_start_date);
  if (before === next) return { changed: false, date: next };
  if (next && employee.date_hired && next < dateOnly(employee.date_hired)) {
    throw new AssignmentTransitionError('Attendance tracking cannot start before the employee hire date');
  }
  const [low, high] = [before || '1900-01-01', next || '1900-01-01'].sort();
  const posted = await db.query(
    `SELECT id FROM leave_attendance_deductions WHERE user_id=$1::uuid
       AND service_month>=date_trunc('month',$2::date)::date AND service_month<$3::date LIMIT 1`,
    [employeeId, low, high]
  );
  if (posted.rows.length) {
    throw new AssignmentTransitionError(
      'Attendance deductions already exist in the affected period. Reconcile them before changing tracking start.',
      409
    );
  }
  await db.query(
    'UPDATE users SET attendance_tracking_start_date=$2::date,updated_at=now() WHERE id=$1::uuid',
    [employeeId, next]
  );
  await db.query(
    `INSERT INTO audit_logs(user_id,action,entity_type,entity_id,details)
       VALUES($1::uuid,'attendance_tracking_start_updated','users',$2::uuid,$3)`,
    [actorId || null, employeeId, JSON.stringify({ before, after: next, source: 'assignments', assignment_id: assignmentId })]
  );
  return { changed: true, date: next };
}

module.exports = { cleanTrackingDate, loadTrackingStarts, isBeforeEmployeeTracking, zeroDeduction, updateEmployeeTrackingStart };
