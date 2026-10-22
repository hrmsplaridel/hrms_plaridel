// Service requirements use the recorded hire date and the first requested day,
// not today's date. Calendar-month anniversaries clamp at month end.
function isoDate(value) {
  const text = value instanceof Date ? value.toISOString().slice(0, 10) : String(value || '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null;
  const date = new Date(`${text}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === text ? text : null;
}

function serviceEligibility(rule, hireDate, leaveStart) {
  const months = Number(rule?.minimum_service_months || 0);
  if (!months) return {eligible:true, minimum_service_months:0, eligible_from:null, message:null};
  const hired = isoDate(hireDate);
  if (!hired) return {eligible:false, minimum_service_months:months, eligible_from:null,
    message:'Your hire date is missing or invalid. Ask HR to update it before filing this leave type.'};
  const date = new Date(`${hired}T00:00:00Z`);
  const year = date.getUTCFullYear();
  const month = date.getUTCMonth() + months;
  const day = Math.min(date.getUTCDate(), new Date(Date.UTC(year, month + 1, 0)).getUTCDate());
  const eligibleFrom = new Date(Date.UTC(year, month, day)).toISOString().slice(0, 10);
  const eligible = !!isoDate(leaveStart) && leaveStart >= eligibleFrom;
  return {eligible, minimum_service_months:months, eligible_from:eligibleFrom,
    message:eligible ? null : `This leave type requires ${months} month(s) of service. You become eligible on ${eligibleFrom}.`};
}

async function assertLeaveServiceEligibility(db, rule, userId, leaveStart) {
  if (!Number(rule?.minimum_service_months || 0)) return;
  const result = await db.query('SELECT date_hired::text AS date_hired FROM users WHERE id = $1::uuid LIMIT 1', [userId]);
  const eligibility = serviceEligibility(rule, result.rows[0]?.date_hired, leaveStart);
  if (!eligibility.eligible) throw Object.assign(new Error(eligibility.message), {statusCode:400, eligibility});
  return eligibility;
}

module.exports = {isoDate, serviceEligibility, assertLeaveServiceEligibility};
