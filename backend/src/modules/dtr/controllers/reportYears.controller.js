'use strict';
module.exports = function createDtrControllers({
  pool,
  resolveDtrDailySummaryScope,
  todayInHrmsTimezone,
}) {
  const { findReportYearBounds } = require('../repositories/reportYears')({ pool });
  return {
    getReportYears: async (req, res) => {
      try {
        const { employeeId: scopedEmployeeId } = resolveDtrDailySummaryScope(req.user, req.query);
        const officialDate = todayInHrmsTimezone();
        const row = await findReportYearBounds(scopedEmployeeId, officialDate);
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
