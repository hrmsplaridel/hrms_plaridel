'use strict';
module.exports = function createDtrComponent({ _holidaysHasCoverageColumn, pool }) {
  /** Saved DTR rows for the list/report endpoint, filtered by the caller's resolved scope. */
  async function listSavedSummaryRows({
    privileged,
    scopedEmployeeId,
    startDate,
    endDate,
    requestedEmployeeIds,
    scopedDepartmentId,
    sqlMaxRows,
  }) {
    const params = [];
    const conditions = [];
    let i = 1;
    if (!privileged) {
      conditions.push(`d.employee_id = $${i++}`);
      params.push(scopedEmployeeId);
    }
    if (startDate) {
      conditions.push(`d.attendance_date >= $${i++}`);
      params.push(startDate);
    }
    if (endDate) {
      conditions.push(`d.attendance_date <= $${i++}`);
      params.push(endDate);
    }
    if (scopedEmployeeId && privileged) {
      conditions.push(`d.employee_id = $${i++}`);
      params.push(scopedEmployeeId);
    }
    if (requestedEmployeeIds.length > 0) {
      conditions.push(`d.employee_id = ANY($${i++}::uuid[])`);
      params.push(requestedEmployeeIds);
    }
    if (scopedDepartmentId) {
      const depIdx = i;
      conditions.push(`(
        SELECT a.department_id
        FROM assignments a
        WHERE a.employee_id = d.employee_id
          AND a.effective_from <= d.attendance_date
          AND (a.effective_to IS NULL OR a.effective_to >= d.attendance_date)
        ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
        LIMIT 1
      ) = $${depIdx}::uuid`);
      params.push(scopedDepartmentId);
      i += 1;
    }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    params.push(sqlMaxRows);

    const hasCoverage = await _holidaysHasCoverageColumn();
    const joinCols = hasCoverage
      ? 'h.name AS holiday_name, h.holiday_type AS holiday_type, h.coverage AS holiday_coverage'
      : 'h.name AS holiday_name, h.holiday_type AS holiday_type, NULL::text AS holiday_coverage';
    const result = await pool.query(
      `SELECT d.id, d.employee_id, d.attendance_date, d.attendance_date::text AS attendance_date_iso, d.time_in, d.break_out, d.break_in, d.time_out, d.total_hours,
              d.late_minutes, d.undertime_minutes, d.status, d.pm_status, d.remarks, d.source, d.holiday_id, d.shift_snapshot,
              d.leave_request_id AS base_leave_request_id,
              dlc.id AS leave_coverage_id,
              COALESCE(dlc.leave_request_id, d.leave_request_id) AS leave_request_id,
              lr.status AS leave_request_status,
              lr.number_of_days, lr.total_days,
              lr.start_date::text AS leave_start_date, lr.end_date::text AS leave_end_date,
              d.created_at, d.updated_at,
              u.full_name AS employee_name,
              ${joinCols},
              COALESCE(NULLIF(lt.display_name, ''), NULLIF(lt.description, ''), lt.name) AS leave_type_name
       FROM dtr_daily_summary d
       LEFT JOIN users u ON u.id = d.employee_id
       LEFT JOIN holidays h ON h.id = d.holiday_id
       LEFT JOIN dtr_leave_coverage dlc
         ON dlc.employee_id = d.employee_id
        AND dlc.attendance_date = d.attendance_date
        AND EXISTS (
          SELECT 1 FROM leave_requests approved_request
          WHERE approved_request.id = dlc.leave_request_id
            AND approved_request.status = 'approved'
        )
       LEFT JOIN leave_requests lr ON lr.id = COALESCE(dlc.leave_request_id, d.leave_request_id)
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       ${where}
       ORDER BY d.attendance_date DESC, d.time_in DESC NULLS LAST
       LIMIT $${i}`,
      params
    );
    const rawRows = result.rows;
    if (!hasCoverage) for (const r of rawRows) r.holiday_coverage = 'whole_day';
    return rawRows;
  }
  return { listSavedSummaryRows };
};
