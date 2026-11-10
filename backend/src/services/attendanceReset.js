'use strict';
const { createHash } = require('node:crypto');
const { parseAssignmentDate } = require('../utils/assignmentInputValidation');
const { localTimestampParts, addIsoDays } = require('./dtrPunchDateValidation');
const { groupPunchesForSchedules } = require('./shiftTimeline');
const { resolvedWorkingDay } = require('./employeeScheduleOverrides');
const { enqueueEmployeeRangeReconciliation } = require('./dtrMonthEndReconciliation');
const { broadcastBiometricUpdate } = require('../websockets/biometricStream');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TIME_ZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';
const fail = (status, message) => Object.assign(new Error(message), { status });

function createAttendanceResetService({ db, now = () => new Date(),
  broadcast = broadcastBiometricUpdate, enqueue = enqueueEmployeeRangeReconciliation }) {
  const today = () => localTimestampParts(now(), TIME_ZONE).date;
  function target(body) {
    if (typeof body?.employee_id !== 'string' || !UUID.test(body.employee_id)) {
      throw fail(400, 'Select one employee.');
    }
    const date = parseAssignmentDate(body.attendance_date);
    if (!date || date > today()) throw fail(400, 'Select a valid attendance date that is not in the future.');
    return { employeeId: body.employee_id.toLowerCase(), date };
  }

  async function snapshot(client, { employeeId, date }, actorId) {
    const employeeResult = await client.query(
      `SELECT id, full_name, employee_number, biometric_user_id FROM users
       WHERE id = $1::uuid AND role IN ('employee', 'admin', 'hr', 'supervisor')`, [employeeId]);
    if (!employeeResult.rows.length) throw fail(404, 'Employee not found. System accounts cannot be reset here.');
    const employee = employeeResult.rows[0];
    const summaryResult = await client.query(
      `SELECT *, attendance_date::text AS attendance_date_iso,
              to_char(COALESCE(time_in, break_in) AT TIME ZONE $3, 'YYYY-MM-DD HH24:MI:SS') AS clock_in_local,
              to_char(COALESCE(time_out, break_out) AT TIME ZONE $3, 'YYYY-MM-DD HH24:MI:SS') AS clock_out_local
       FROM dtr_daily_summary WHERE employee_id = $1::uuid AND attendance_date = $2::date`, [employeeId, date, TIME_ZONE]);
    const summary = summaryResult.rows[0] || null;
    const rawResult = await client.query(
      `SELECT *, to_char(logged_at AT TIME ZONE $3, 'YYYY-MM-DD HH24:MI:SS') AS logged_at_local FROM biometric_attendance_logs
       WHERE user_id = $1::uuid
         AND (logged_at AT TIME ZONE $3)::date BETWEEN $2::date - 1 AND $2::date + 1
       ORDER BY logged_at, id LIMIT 10001`, [employeeId, date, TIME_ZONE]);
    if (rawResult.rows.length > 10000) throw fail(413, 'Too many punches for this reset. Contact your database administrator.');
    const timeToMinutes = value => {
      if (value == null) return null;
      const [hours, minutes] = String(value).split(':').map(Number);
      return hours * 60 + minutes;
    };
    const { getAssignmentShiftForDate } = require('../modules/dtr/repositories/assignments')({
      pool: client, resolvedWorkingDay, timeToMinutes,
    });
    const schedules = new Map();
    async function scheduleFor(_employeeId, day) {
      if (!schedules.has(day)) schedules.set(day, day === date && summary?.shift_snapshot
        ? summary.shift_snapshot : await getAssignmentShiftForDate(employeeId, day));
      return schedules.get(day);
    }
    const groups = await groupPunchesForSchedules([
      { user_id: employeeId, punches: rawResult.rows.map(row => row.logged_at) },
    ], scheduleFor, date, date, TIME_ZONE, { deduplicate: false });
    const selected = new Set((groups.find(row => row.attendance_date === date)?.punches || [])
      .map(value => new Date(value).getTime()));
    const punches = rawResult.rows.filter(row => selected.has(new Date(row.logged_at).getTime()));
    const blocks = (await client.query(
      `SELECT * FROM dtr_daily_summary_deletions
       WHERE employee_id = $1::uuid AND attendance_date = $2::date AND restored_at IS NULL
       ORDER BY id`, [employeeId, date])).rows;
    const coverage = (await client.query(
      `SELECT id, 'leave' AS kind FROM leave_requests
       WHERE employee_id = $1::uuid AND status = 'approved' AND start_date <= $2::date AND end_date >= $2::date
       UNION ALL
       SELECT id, 'locator' AS kind FROM locator_slips
       WHERE employee_id = $1::uuid AND slip_date = $2::date
         AND status IN ('approved', 'approved_by_hr', 'approved_by_mayor')
       ORDER BY kind, id`, [employeeId, date])).rows;
    const processed = (await client.query(
      `SELECT id, service_month::text AS service_month, leave_type, deducted_days, updated_at
       FROM leave_attendance_deductions
       WHERE user_id = $1::uuid AND service_month = date_trunc('month', $2::date)::date
       ORDER BY id`, [employeeId, date])).rows;
    const before = { employee, attendance_date: date, punches, summary, deletion_blocks: blocks,
      approved_coverage: coverage, processed_months: processed };
    // This digest detects a changed preview; authorization is enforced separately
    // by the super-admin route. Bind it to the operator and surrounding schedules.
    const previewToken = createHash('sha256').update(JSON.stringify({ actorId, before,
      raw: rawResult.rows, schedules: [...schedules.entries()].sort() })).digest('hex');
    return { before, previewToken };
  }

  function describe({ before, previewToken }) {
    const blocked = before.approved_coverage.length > 0;
    const hasRecords = before.punches.length > 0 || before.summary != null || before.deletion_blocks.length > 0;
    return {
      employee: before.employee, attendance_date: before.attendance_date, time_zone: TIME_ZONE,
      punches: before.punches.map(row => ({ id: row.id, logged_at: row.logged_at,
        logged_at_local: row.logged_at_local, device_ref_id: row.device_ref_id })),
      summary: before.summary, deletion_blocks: before.deletion_blocks.length,
      processed_months: before.processed_months,
      can_reset: hasRecords && !blocked,
      blocked_reason: blocked ? 'Approved leave or locator coverage exists. Revoke or correct that approval before resetting attendance.'
        : !hasRecords ? 'No attendance records or deletion blocks exist for this employee and date.' : null,
      preview_token: previewToken,
    };
  }

  return {
    async employees(search = '') {
      if (typeof search !== 'string' || search.length > 100) throw fail(400, 'Search must not exceed 100 characters.');
      const result = await db.query(
        `SELECT u.id, u.full_name, u.employee_number, u.biometric_user_id
         FROM users u WHERE u.role IN ('employee', 'admin', 'hr', 'supervisor')
           AND (u.full_name ILIKE $1 OR u.employee_number::text ILIKE $1)
         ORDER BY u.full_name, u.id LIMIT 50`, [`%${search.trim()}%`]);
      return { items: result.rows, official_date: today(), time_zone: TIME_ZONE };
    },
    async preview(body, actorId) {
      const scope = target(body);
      const client = await db.connect();
      try {
        await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
        const result = describe(await snapshot(client, scope, actorId));
        await client.query('COMMIT');
        return result;
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    },
    async apply(body, actorId) {
      const scope = target(body);
      if (typeof body.reason !== 'string' || body.reason.trim().length < 3 || body.reason.trim().length > 1000) {
        throw fail(400, 'Enter a reset reason between 3 and 1000 characters.');
      }
      if (body.confirmation !== 'RESET' || typeof body.preview_token !== 'string' || !/^[a-f0-9]{64}$/.test(body.preview_token)) {
        throw fail(400, 'Preview the records and type RESET to confirm.');
      }
      const client = await db.connect();
      let result;
      try {
        await client.query('BEGIN');
        await client.query("SET LOCAL lock_timeout = '5s'");
        // Keep the inspected set and deletion atomic against ingestion and edits.
        await client.query('LOCK TABLE biometric_attendance_logs, dtr_daily_summary, dtr_daily_summary_deletions IN SHARE ROW EXCLUSIVE MODE');
        await client.query('LOCK TABLE leave_requests, locator_slips IN SHARE MODE');
        const state = await snapshot(client, scope, actorId);
        if (state.previewToken !== body.preview_token) throw fail(409, 'Attendance changed since the preview. Preview again before resetting.');
        const preview = describe(state);
        if (!preview.can_reset) throw fail(409, preview.blocked_reason);
        const { before } = state;
        await client.query(
          `INSERT INTO attendance_reset_punches (employee_id, logged_at)
           SELECT user_id, logged_at FROM biometric_attendance_logs
           WHERE user_id = $1::uuid AND id = ANY($2::uuid[])
           ON CONFLICT (employee_id, logged_at) DO NOTHING`,
          [scope.employeeId, before.punches.map(row => row.id)]);
        const removed = await client.query('DELETE FROM biometric_attendance_logs WHERE user_id = $1::uuid AND id = ANY($2::uuid[]) RETURNING id',
          [scope.employeeId, before.punches.map(row => row.id)]);
        const summary = await client.query('DELETE FROM dtr_daily_summary WHERE employee_id = $1::uuid AND attendance_date = $2::date',
          [scope.employeeId, scope.date]);
        // Retain deletion history while lifting the block on fresh processing.
        const blocks = await client.query(
          `UPDATE dtr_daily_summary_deletions SET restored_at = now(), restored_by = $3::uuid, restoration_reason = $4
           WHERE employee_id = $1::uuid AND attendance_date = $2::date AND restored_at IS NULL`,
          [scope.employeeId, scope.date, actorId, `Attendance reset: ${body.reason.trim()}`]);
        const reconciliation = await enqueue(client, {
          employeeId: scope.employeeId, dateFrom: scope.date, dateTo: scope.date,
          reason: 'attendance_reset', metadata: { actor_id: actorId, reason: body.reason.trim() }, timeZone: TIME_ZONE,
        });
        result = { employee_id: scope.employeeId, attendance_date: scope.date, punches_deleted: removed.rowCount,
          summaries_deleted: summary.rowCount, deletion_blocks_cleared: blocks.rowCount,
          reconciliation_months: reconciliation.months };
        await client.query(
          `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
           VALUES ($1::uuid, 'attendance_reset', 'users', $2::uuid, $3)`,
          [actorId, scope.employeeId, JSON.stringify({ reason: body.reason.trim(), before, result })]);
        await client.query('COMMIT');
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
      broadcast('dtr_refresh', { action: 'attendance_reset', userId: scope.employeeId,
        date: scope.date, userIds: [scope.employeeId], dates: [scope.date] });
      return result;
    },
  };
}
module.exports = { createAttendanceResetService };
