'use strict';
module.exports = function createDtrComponent({ _holidaysHasCoverageColumn, pool }) {
  /** The employee's saved or leave-covered DTR row for one date (GET /today). */
  async function findDayRecord(employeeId, dateStr) {
    const hasCoverage = await _holidaysHasCoverageColumn();
    const joinCols = hasCoverage
      ? 'h.name AS holiday_name, h.holiday_type AS holiday_type, h.coverage AS holiday_coverage'
      : 'h.name AS holiday_name, h.holiday_type AS holiday_type, NULL::text AS holiday_coverage';
    const result = await pool.query(
      `WITH target AS (
         SELECT $1::uuid AS employee_id, $2::date AS attendance_date
       )
       SELECT d.id,
              target.employee_id,
              target.attendance_date,
              target.attendance_date::text AS attendance_date_iso,
              d.time_in, d.break_out, d.break_in, d.time_out, d.total_hours, d.shift_snapshot,
              CASE WHEN dlc.id IS NOT NULL OR lr.status = 'approved' THEN 'on_leave' ELSE d.status END AS status,
              d.pm_status, d.remarks,
              lr.number_of_days, lr.total_days,
              lr.start_date::text AS leave_start_date, lr.end_date::text AS leave_end_date,
              CASE WHEN dlc.id IS NOT NULL OR lr.status = 'approved' THEN 'adjusted' ELSE d.source END AS source,
              d.holiday_id, d.created_at, d.updated_at,
              dlc.id AS leave_coverage_id,
              COALESCE(dlc.leave_request_id, CASE WHEN lr.status = 'approved' THEN d.leave_request_id END) AS leave_request_id,
              (dlc.id IS NOT NULL OR lr.status = 'approved') AS is_leave_covered,
              COALESCE(NULLIF(lt.display_name, ''), NULLIF(lt.description, ''), lt.name) AS leave_type_name,
              u.full_name AS employee_name,
              ${joinCols}
       FROM target
       LEFT JOIN dtr_daily_summary d
         ON d.employee_id = target.employee_id AND d.attendance_date = target.attendance_date
       LEFT JOIN dtr_leave_coverage dlc
         ON dlc.employee_id = target.employee_id
        AND dlc.attendance_date = target.attendance_date
        AND EXISTS (
          SELECT 1 FROM leave_requests approved_request
          WHERE approved_request.id = dlc.leave_request_id
            AND approved_request.status = 'approved'
        )
       LEFT JOIN leave_requests lr ON lr.id = COALESCE(dlc.leave_request_id, d.leave_request_id)
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = target.employee_id
       LEFT JOIN holidays h ON h.id = d.holiday_id
       WHERE d.id IS NOT NULL OR dlc.id IS NOT NULL`,
      [employeeId, dateStr]
    );
    return { row: result.rows[0], hasCoverage };
  }
  return { findDayRecord };
};
