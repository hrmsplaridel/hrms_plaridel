'use strict';
module.exports = function createDtrControllers({
  pool,
  resolveDtrDailySummaryScope,
  todayInHrmsTimezone,
}) {
  return {
    getReportYears: async (req, res) => {
      try {
        const { employeeId: scopedEmployeeId } = resolveDtrDailySummaryScope(req.user, req.query);
        const officialDate = todayInHrmsTimezone();
        const result = await pool.query(
          `WITH official_clock AS (
         SELECT $2::date AS today
       ),
       report_dates AS (
         SELECT employee_id, attendance_date AS report_date
         FROM dtr_daily_summary

         UNION ALL
         SELECT user_id AS employee_id,
                (logged_at AT TIME ZONE 'Asia/Manila')::date AS report_date
         FROM biometric_attendance_logs

         UNION ALL
         SELECT employee_id,
                (log_time AT TIME ZONE 'Asia/Manila')::date AS report_date
         FROM dtr_logs

         UNION ALL
         SELECT employee_id, effective_from AS report_date
         FROM assignments

         UNION ALL
         SELECT a.employee_id, LEAST(COALESCE(a.effective_to, c.today), c.today)
         FROM assignments a
         CROSS JOIN official_clock c

         UNION ALL
         SELECT id AS employee_id, date_hired AS report_date
         FROM users
         WHERE date_hired IS NOT NULL

         UNION ALL
         SELECT u.id AS employee_id,
                LEAST(COALESCE(u.separation_date, c.today), c.today)
         FROM users u
         CROSS JOIN official_clock c
         WHERE u.date_hired IS NOT NULL

         UNION ALL
         SELECT employee_id, start_date AS report_date
         FROM leave_requests

         UNION ALL
         SELECT employee_id, end_date AS report_date
         FROM leave_requests

         UNION ALL
         SELECT employee_id, slip_date AS report_date
         FROM locator_slips
       )
       SELECT COALESCE(
                MIN(EXTRACT(YEAR FROM rd.report_date))::int,
                EXTRACT(YEAR FROM c.today)::int
              ) AS min_year,
              GREATEST(
                COALESCE(
                  MAX(EXTRACT(YEAR FROM rd.report_date))::int,
                  EXTRACT(YEAR FROM c.today)::int
                ),
                EXTRACT(YEAR FROM c.today)::int
              ) AS max_year,
              EXTRACT(YEAR FROM c.today)::int AS current_year
       FROM official_clock c
       LEFT JOIN report_dates rd
         ON rd.report_date IS NOT NULL
        AND rd.report_date <= c.today
        AND ($1::uuid IS NULL OR rd.employee_id = $1::uuid)
       GROUP BY c.today`,
          [scopedEmployeeId, officialDate]
        );
        const row = result.rows[0] || {};
        const currentYear = Number(row.current_year) || Number(officialDate.slice(0, 4));
        const minYear = Math.max(1900, Math.min(Number(row.min_year) || currentYear, currentYear));
        const maxYear = Math.max(
          minYear,
          Math.min(Number(row.max_year) || currentYear, currentYear)
        );
        const years = Array.from({ length: maxYear - minYear + 1 }, (_, index) => minYear + index);

        res.json({
          min_year: minYear,
          max_year: maxYear,
          years,
          official_date: officialDate,
        });
      } catch (err) {
        console.error('[dtr-daily-summary GET /report-years]', err);
        res.status(500).json({ error: 'Failed to load available DTR report years' });
      }
    },
  };
};
