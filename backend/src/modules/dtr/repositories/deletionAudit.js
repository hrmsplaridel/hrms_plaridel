'use strict';
// Deleted-DTR audit trail. Transactional functions take the caller's client so
// row locks, commit and rollback stay with the controller's transaction.
module.exports = function createDtrComponent({ pool }) {
  async function listDeletions({ includeRestored, employeeId, startDate, endDate, limit, offset }) {
    const params = [];
    const conditions = [];
    let i = 1;

    if (!includeRestored) conditions.push('dd.restored_at IS NULL');
    if (employeeId) {
      conditions.push(`dd.employee_id = $${i++}::uuid`);
      params.push(employeeId);
    }
    if (startDate) {
      conditions.push(`dd.attendance_date >= $${i++}::date`);
      params.push(startDate);
    }
    if (endDate) {
      conditions.push(`dd.attendance_date <= $${i++}::date`);
      params.push(endDate);
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    params.push(limit, offset);
    const result = await pool.query(
      `SELECT dd.id,
              dd.deleted_dtr_summary_id,
              dd.employee_id,
              dd.attendance_date::text AS attendance_date,
              dd.source,
              dd.reason,
              dd.deleted_by,
              dd.record_snapshot,
              dd.deleted_at,
              dd.restored_by,
              dd.restoration_reason,
              dd.restored_at,
              employee.full_name AS employee_name,
              deleted_actor.full_name AS deleted_by_name,
              restored_actor.full_name AS restored_by_name,
              COUNT(*) OVER()::int AS total_count
       FROM dtr_daily_summary_deletions dd
       LEFT JOIN users employee ON employee.id = dd.employee_id
       LEFT JOIN users deleted_actor ON deleted_actor.id = dd.deleted_by
       LEFT JOIN users restored_actor ON restored_actor.id = dd.restored_by
       ${where}
       ORDER BY (dd.restored_at IS NULL) DESC, dd.deleted_at DESC
       LIMIT $${i++} OFFSET $${i}`,
      params
    );
    return result.rows;
  }

  function lockSummaryForDeletion(client, summaryId) {
    return client.query(
      `SELECT d.*, d.attendance_date::text AS attendance_date_iso
       FROM dtr_daily_summary d
       WHERE d.id = $1
       FOR UPDATE`,
      [summaryId]
    );
  }

  function insertDeletionRecord(client, { row, reason, actorId }) {
    return client.query(
      `INSERT INTO dtr_daily_summary_deletions (
         deleted_dtr_summary_id,
         employee_id,
         attendance_date,
         source,
         reason,
         deleted_by,
         record_snapshot
       ) VALUES ($1::uuid, $2::uuid, $3::date, $4, $5, $6::uuid, $7::jsonb)`,
      [
        row.id,
        row.employee_id,
        row.attendance_date_iso,
        row.source,
        reason,
        actorId,
        JSON.stringify(row),
      ]
    );
  }

  function deleteSummary(client, summaryId) {
    return client.query('DELETE FROM dtr_daily_summary WHERE id = $1', [summaryId]);
  }

  function lockDeletion(client, deletionId) {
    return client.query(
      `SELECT *
       FROM dtr_daily_summary_deletions
       WHERE id = $1::uuid
       FOR UPDATE`,
      [deletionId]
    );
  }

  function findSummaryForDay(client, employeeId, attendanceDate) {
    return client.query(
      `SELECT id
       FROM dtr_daily_summary
       WHERE employee_id = $1::uuid AND attendance_date = $2::date
       LIMIT 1`,
      [employeeId, attendanceDate]
    );
  }

  function insertRestoredSummary(client, { deletion, snapshot, status, pmStatus, source }) {
    return client.query(
      `INSERT INTO dtr_daily_summary (
         id, employee_id, attendance_date,
         assignment_id, shift_id, attendance_policy_id, holiday_id, leave_request_id,
         time_in, time_out, break_in, break_out,
         late_minutes, undertime_minutes, overtime_minutes, total_hours,
         status, pm_status, source, remarks, created_at, updated_at
       ) VALUES (
         $1::uuid, $2::uuid, $3::date,
         (SELECT id FROM assignments WHERE id = $4::uuid),
         (SELECT id FROM shifts WHERE id = $5::uuid),
         (SELECT id FROM attendance_policies WHERE id = $6::uuid),
         (SELECT id FROM holidays WHERE id = $7::uuid),
         (SELECT id FROM leave_requests WHERE id = $8::uuid),
         $9::timestamptz, $10::timestamptz, $11::timestamptz, $12::timestamptz,
         $13, $14, $15, $16::numeric,
         $17, $18, $19, $20, COALESCE($21::timestamptz, now()), now()
       )
       RETURNING id, employee_id, attendance_date::text AS attendance_date, source, status`,
      [
        deletion.deleted_dtr_summary_id,
        deletion.employee_id,
        deletion.attendance_date,
        snapshot.assignment_id || null,
        snapshot.shift_id || null,
        snapshot.attendance_policy_id || null,
        snapshot.holiday_id || null,
        snapshot.leave_request_id || null,
        snapshot.time_in || null,
        snapshot.time_out || null,
        snapshot.break_in || null,
        snapshot.break_out || null,
        Math.max(0, parseInt(snapshot.late_minutes, 10) || 0),
        Math.max(0, parseInt(snapshot.undertime_minutes, 10) || 0),
        Math.max(0, parseInt(snapshot.overtime_minutes, 10) || 0),
        Math.max(0, parseFloat(snapshot.total_hours) || 0),
        status,
        pmStatus,
        source,
        snapshot.remarks || null,
        snapshot.created_at || null,
      ]
    );
  }

  function markDeletionRestored(client, { deletionId, actorId, reason }) {
    return client.query(
      `UPDATE dtr_daily_summary_deletions
       SET restored_by = $2::uuid,
           restoration_reason = $3,
           restored_at = now()
       WHERE id = $1::uuid`,
      [deletionId, actorId, reason]
    );
  }

  return {
    deleteSummary,
    findSummaryForDay,
    insertDeletionRecord,
    insertRestoredSummary,
    listDeletions,
    lockDeletion,
    lockSummaryForDeletion,
    markDeletionRestored,
  };
};
