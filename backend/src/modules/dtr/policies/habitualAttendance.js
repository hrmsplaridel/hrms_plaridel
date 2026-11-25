'use strict';
// CSC MC No. 04 s.1991 / MC No. 23 s.1998 (tardiness) and MC No. 16 s.2010 (undertime):
// ten or more instances a month, in at least two months of a semester or two consecutive months.
const HABITUAL_MONTHLY_THRESHOLD = 10;
const NON_WORKED_STATUSES = new Set(['absent', 'not_tracked', 'holiday', 'on_leave', 'rest_day']);

function monthIndexOf(row) {
  const month = Number(String(row.record_date || '').slice(5, 7));
  return month >= 1 && month <= 12 ? month - 1 : null;
}

function countMonthlyInstances(rows) {
  const tardiness = Array(12).fill(0);
  const undertime = Array(12).fill(0);
  for (const row of rows || []) {
    const index = monthIndexOf(row);
    if (index == null || NON_WORKED_STATUSES.has(row.status)) continue;
    if (Number(row.late_minutes) > 0 && row.time_in) tardiness[index] += 1;
    if (Number(row.undertime_minutes) > 0 && row.time_in && row.time_out) undertime[index] += 1;
  }
  return { tardiness, undertime };
}

function evaluateHabitual(monthly) {
  const qualifying = [];
  monthly.forEach((count, index) => {
    if (count >= HABITUAL_MONTHLY_THRESHOLD) qualifying.push(index + 1);
  });
  const semesterOf = (month) => (month <= 6 ? 1 : 2);
  const habitual = qualifying.some((month, i) =>
    qualifying.slice(i + 1).some(
      (other) => semesterOf(other) === semesterOf(month) || other - month === 1
    )
  );
  return { monthly, qualifying_months: qualifying, habitual };
}

module.exports = { HABITUAL_MONTHLY_THRESHOLD, countMonthlyInstances, evaluateHabitual };
