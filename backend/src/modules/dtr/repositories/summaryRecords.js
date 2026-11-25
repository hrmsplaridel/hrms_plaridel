'use strict';
// DTR row writes. Transactional functions take the caller's client so the row
// lock, audit insert, commit and rollback stay in one controller transaction.
module.exports = function createDtrComponent({ _holidaysHasCoverageColumn, pool }) {
  /** Lock a DTR row for a manual edit (PUT /:id). */
  async function lockSummaryForUpdate(client, summaryId) {
    const hasCoverage = await _holidaysHasCoverageColumn();
    const joinCols = hasCoverage
      ? 'h.coverage AS holiday_coverage'
      : 'NULL::text AS holiday_coverage';
    return client.query(
      `SELECT d.*, d.attendance_date::text AS attendance_date_iso, ${joinCols}
       FROM dtr_daily_summary d
       LEFT JOIN holidays h ON h.id = d.holiday_id
       WHERE d.id = $1
       FOR UPDATE OF d`,
      [summaryId]
    );
  }

  /** Lock a DTR row for recalculation (POST /:id/recalculate). */
  async function lockSummaryForRecalculation(client, summaryId) {
    const hasCoverage = await _holidaysHasCoverageColumn();
    const joinCols = hasCoverage
      ? 'h.coverage AS holiday_coverage, h.name AS holiday_name'
      : 'NULL::text AS holiday_coverage, NULL::text AS holiday_name';
    return client.query(
      `SELECT d.*, d.attendance_date::text AS attendance_date_iso, ${joinCols}
       FROM dtr_daily_summary d
       LEFT JOIN holidays h ON h.id = d.holiday_id
       WHERE d.id = $1
       FOR UPDATE OF d`,
      [summaryId]
    );
  }

  /**
   * Apply an edit's column assignments. `setClauses` are `column = $n` fragments
   * numbered against `values`; the row id is the final parameter (`idIndex`).
   */
  async function updateSummaryFields(client, setClauses, values, idIndex) {
    const result = await client.query(
      `UPDATE dtr_daily_summary SET ${setClauses.join(', ')} WHERE id = $${idIndex}
       RETURNING *, attendance_date::text AS attendance_date_iso`,
      values
    );
    return result.rows[0];
  }

  async function applyRecalculation(
    client,
    { summaryId, totalHours, lateMinutes, undertimeMinutes, status, pmStatus, holidayId }
  ) {
    const result = await client.query(
      `UPDATE dtr_daily_summary
       SET total_hours = $2::numeric,
           late_minutes = $3,
           undertime_minutes = $4,
           status = $5,
           pm_status = $6,
           holiday_id = $7::uuid,
           source = CASE WHEN source = 'system' THEN source ELSE 'adjusted' END,
           updated_at = now()
       WHERE id = $1::uuid
       RETURNING *, attendance_date::text AS attendance_date_iso`,
      [summaryId, totalHours, lateMinutes, undertimeMinutes, status, pmStatus, holidayId]
    );
    return result.rows[0];
  }

  function insertAdjustmentAudit(client, { actorId, summaryId, details }) {
    return client.query(
      `INSERT INTO audit_logs (
         user_id, action, entity_type, entity_id, details, created_at
       ) VALUES (
         $1::uuid, 'dtr_time_entry_adjusted', 'dtr_daily_summary', $2::uuid, $3, now()
       )`,
      [actorId, summaryId, JSON.stringify(details)]
    );
  }

  function insertRecalculationAudit(client, { actorId, summaryId, details }) {
    return client.query(
      `INSERT INTO audit_logs (
         user_id, action, entity_type, entity_id, details, created_at
       ) VALUES (
         $1::uuid, 'dtr_time_entry_recalculated', 'dtr_daily_summary', $2::uuid, $3, now()
       )`,
      [actorId, summaryId, JSON.stringify(details)]
    );
  }

  /** Manual/adjusted DTR row created by HR (POST /). */
  async function insertManualSummary({
    employeeId,
    date,
    timeIn,
    breakOut,
    breakIn,
    timeOut,
    totalHours,
    lateMinutes,
    undertimeMinutes,
    status,
    pmStatus,
    source,
    holidayId,
    shiftInfo,
  }) {
    const result = await pool.query(
      `INSERT INTO dtr_daily_summary (employee_id, attendance_date, time_in, break_out, break_in, time_out, total_hours, late_minutes, undertime_minutes, status, pm_status, source, holiday_id, shift_snapshot)
       VALUES ($1, $2::date, $3::timestamptz, $4::timestamptz, $5::timestamptz, $6::timestamptz, $7::numeric, $8, $9, $10, $11, $12, $13, $14::jsonb)
       RETURNING id, employee_id, attendance_date::text AS attendance_date_iso, time_in, break_out, break_in, time_out, total_hours, late_minutes, undertime_minutes, status, pm_status, source, created_at`,
      [
        employeeId,
        date,
        timeIn,
        breakOut,
        breakIn,
        timeOut,
        totalHours,
        lateMinutes,
        undertimeMinutes,
        status,
        pmStatus,
        source,
        holidayId,
        JSON.stringify(shiftInfo),
      ]
    );
    return result.rows[0];
  }

  return {
    applyRecalculation,
    insertAdjustmentAudit,
    insertManualSummary,
    insertRecalculationAudit,
    lockSummaryForRecalculation,
    lockSummaryForUpdate,
    updateSummaryFields,
  };
};
