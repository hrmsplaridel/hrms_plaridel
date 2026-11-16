'use strict';

const iso = value => value instanceof Date ? value.toISOString().slice(0, 10)
  : value == null ? null : String(value).slice(0, 10);

async function loadServicePeriods(db, employees) {
  const returned = employees.filter(row => row.last_service_return_date);
  if (!returned.length) return new Map();
  const ids = [...new Set(returned.map(row => row.user_id || row.id))];
  const history = await db.query(
    `SELECT employee_id, service_started_on::text, separated_on::text, leave_credit_eligible
       FROM employee_service_returns WHERE employee_id=ANY($1::uuid[])
       ORDER BY employee_id, returned_on`, [ids]
  );
  const result = new Map(ids.map(id => [String(id), []]));
  for (const row of history.rows) result.get(String(row.employee_id))?.push({
    from: iso(row.service_started_on), to: iso(row.separated_on), eligible: row.leave_credit_eligible === true,
  });
  for (const employee of returned) {
    const id = String(employee.user_id || employee.id);
    if (result.get(id).some(period => period.current)) continue;
    result.get(id).push({ from: iso(employee.last_service_return_date), to: iso(employee.separation_date),
      eligible: employee.leave_credit_eligible === true || Boolean(employee.leave_credit_eligible_until), current: true });
  }
  return result;
}

// Calendar-day proration over eligible employment periods, excluding gaps.
function serviceMonthCredit(periods, month, rate, notBefore = null) {
  const first = `${iso(month).slice(0, 7)}-01`;
  const start = new Date(`${first}T00:00:00Z`);
  const days = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 1, 0)).getUTCDate();
  const eligibleDates = new Set();
  for (let day = 1; day <= days; day++) {
    const date = `${first.slice(0, 8)}${String(day).padStart(2, '0')}`;
    if (notBefore && date < iso(notBefore)) continue;
    if (periods.some(period => period.eligible && period.from <= date && (!period.to || date <= period.to))) {
      eligibleDates.add(date);
    }
  }
  const worked = eligibleDates.size;
  return { expectedDays: Math.round(worked / days * rate * 1000) / 1000,
    hireProrated: worked > 0 && worked < days,
    separationProrated: false, hireDaysWorked: worked, hireDaysInMonth: days,
    reason: worked ? 'eligible_service_periods' : 'outside_eligible_service_periods' };
}

module.exports = { loadServicePeriods, serviceMonthCredit };
