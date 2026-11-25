'use strict';
const {
  HABITUAL_MONTHLY_THRESHOLD,
  countMonthlyInstances,
  evaluateHabitual,
} = require('../policies/habitualAttendance');

function monthRanges(year, through) {
  const ranges = [];
  for (let month = 1; month <= 12; month += 1) {
    const mm = String(month).padStart(2, '0');
    const start = `${year}-${mm}-01`;
    if (start > through) break;
    const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
    const end = `${year}-${mm}-${String(lastDay).padStart(2, '0')}`;
    ranges.push([start, end < through ? end : through]);
  }
  return ranges;
}

module.exports = function createDtrControllers({ listDtrDailySummaries, todayInHrmsTimezone }) {
  return {
    // GET /api/dtr-daily-summary/habitual-attendance?year=YYYY&department_id=
    getHabitualAttendance: async (req, res) => {
      try {
        const today = todayInHrmsTimezone();
        const currentYear = Number(today.slice(0, 4));
        const rawYear = req.query?.year;
        const year = rawYear == null || rawYear === '' ? currentYear : Number(rawYear);
        if (!/^\d{4}$/.test(String(year)) || year < 1900 || year > currentYear) {
          return res.status(400).json({ error: 'year must be a valid year not in the future' });
        }
        const yearEnd = `${year}-12-31`;
        const through = yearEnd < today ? yearEnd : today;

        const rowsByEmployee = new Map();
        for (const [start_date, end_date] of monthRanges(year, through)) {
          const captured = {
            statusCode: 200,
            body: null,
            locals: {},
            status(code) { this.statusCode = code; return this; },
            json(body) { this.body = body; return this; },
            setHeader() {},
          };
          const monthRequest = Object.create(req);
          monthRequest.bulkReport = true;
          Object.defineProperty(monthRequest, 'query', {
            configurable: true,
            enumerable: true,
            value: { start_date, end_date, department_id: req.query?.department_id, recompute: 'true' },
          });
          await listDtrDailySummaries(monthRequest, captured);
          if (captured.statusCode >= 400) {
            return res.status(captured.statusCode).json(
              captured.body || { error: 'Failed to prepare habitual attendance report' }
            );
          }
          for (const row of Array.isArray(captured.body) ? captured.body : []) {
            const id = String(row.user_id || '');
            if (!id) continue;
            const entry = rowsByEmployee.get(id) || { name: null, rows: [] };
            entry.name = entry.name || row.employee_name || null;
            entry.rows.push(row);
            rowsByEmployee.set(id, entry);
          }
        }

        const employees = [];
        for (const [employeeId, { name, rows }] of rowsByEmployee) {
          const counts = countMonthlyInstances(rows);
          const tardiness = evaluateHabitual(counts.tardiness);
          const undertime = evaluateHabitual(counts.undertime);
          if (!tardiness.qualifying_months.length && !undertime.qualifying_months.length) continue;
          employees.push({ employee_id: employeeId, employee_name: name, tardiness, undertime });
        }
        const rank = (e) => (e.tardiness.habitual || e.undertime.habitual ? 0 : 1);
        employees.sort(
          (a, b) =>
            rank(a) - rank(b) ||
            String(a.employee_name || '').localeCompare(String(b.employee_name || ''))
        );

        return res.json({ year, through, threshold: HABITUAL_MONTHLY_THRESHOLD, employees });
      } catch (err) {
        console.error('[dtr-daily-summary GET /habitual-attendance]', err);
        return res.status(500).json({ error: 'Failed to prepare habitual attendance report' });
      }
    },
  };
};
