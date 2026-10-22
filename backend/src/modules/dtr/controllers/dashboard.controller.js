'use strict';
module.exports = function createDtrControllers({ getHolidayByDate, pool, todayInHrmsTimezone }) {
  return {
    getDashboardSummary: async (req, res) => {
      try {
        const today = todayInHrmsTimezone();
        const todayHoliday = await getHolidayByDate(today);
        const isWholeDayHoliday = todayHoliday?.coverage === 'whole_day';
        const present = await pool.query(
          `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL`,
          [today]
        );
        const late = await pool.query(
          `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL AND status = 'late'`,
          [today]
        );

        let onLeaveToday = 0;
        try {
          const onLeave = await pool.query(
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
            [today]
          );
          onLeaveToday = parseInt(onLeave.rows[0]?.c ?? 0, 10);
        } catch (leaveErr) {
          console.warn(
            '[dtr-daily-summary/summary GET] on_leave_today:',
            leaveErr?.message || leaveErr
          );
        }

        let pendingApproval = 0;
        try {
          const pend = await pool.query(
            `SELECT COUNT(*) AS c FROM leave_requests
         WHERE status IN ('pending', 'pending_department_head', 'pending_hr')`
          );
          pendingApproval = parseInt(pend.rows[0]?.c ?? 0, 10);
        } catch (pendErr) {
          console.warn(
            '[dtr-daily-summary/summary GET] pending_approval:',
            pendErr?.message || pendErr
          );
        }

        res.json({
          present_today: isWholeDayHoliday ? 0 : parseInt(present.rows[0]?.c ?? 0, 10),
          late_today: isWholeDayHoliday ? 0 : parseInt(late.rows[0]?.c ?? 0, 10),
          on_leave_today: onLeaveToday,
          pending_approval: pendingApproval,
        });
      } catch (err) {
        console.error('[dtr-daily-summary/summary GET]', err);
        res.status(500).json({ error: 'Failed to fetch DTR summary counts' });
      }
    },
  };
};
