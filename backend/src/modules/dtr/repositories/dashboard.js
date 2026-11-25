'use strict';
module.exports = function createDtrComponent({ pool }) {
  async function countPresentOn(dateStr) {
    const result = await pool.query(
      `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL`,
      [dateStr]
    );
    return parseInt(result.rows[0]?.c ?? 0, 10);
  }

  async function countLateOn(dateStr) {
    const result = await pool.query(
      `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL AND status = 'late'`,
      [dateStr]
    );
    return parseInt(result.rows[0]?.c ?? 0, 10);
  }

  async function countOnLeaveOn(dateStr) {
    const result = await pool.query(
      `SELECT COUNT(DISTINCT employee_id) AS c
         FROM (
           SELECT c.employee_id
           FROM dtr_leave_coverage c
           JOIN leave_requests lr ON lr.id = c.leave_request_id
           WHERE lr.status = 'approved'
             AND c.attendance_date = $1::date

           UNION

           SELECT COALESCE(lr.user_id, lr.employee_id) AS employee_id
           FROM leave_requests lr
           LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
           WHERE lr.status = 'approved'
             AND COALESCE(lt.affects_dtr_normally, true) = true
             AND lr.start_date <= $1::date
             AND lr.end_date >= $1::date
             AND NOT EXISTS (
               SELECT 1 FROM dtr_leave_coverage c
               WHERE c.leave_request_id = lr.id
             )
         ) covered_employees`,
      [dateStr]
    );
    return parseInt(result.rows[0]?.c ?? 0, 10);
  }

  async function countPendingLeaveApprovals() {
    const result = await pool.query(
      `SELECT COUNT(*) AS c FROM leave_requests
         WHERE status IN ('pending', 'pending_department_head', 'pending_hr')`
    );
    return parseInt(result.rows[0]?.c ?? 0, 10);
  }

  return { countLateOn, countOnLeaveOn, countPendingLeaveApprovals, countPresentOn };
};
