const { annualAllowance, normalizeEntitlementBasis } = require('../leaveEntitlementPolicy');
const dates = require('../../modules/leave/policies/dates')({});
const workingDays = require('../../modules/leave/services/workingDays')({ ...dates, ...require('../holidayRangeUtils') });

// Use the same shift/holiday working-day counter as My Leave, including cross-year requests.
async function loadAnnualEntitlements(pool, userId, types, employee, dateRange) {
  const year = Number(dateRange.startDate.slice(0,4));
  const annual = types.filter(type => normalizeEntitlementBasis(type.entitlement_basis, type.name) === 'annual' && Number(type.max_days)>0);
  if (!annual.length) return [];
  const from=`${year}-01-01`, to=`${year}-12-31`;
  const q=await pool.query({text:`SELECT lt.name AS leave_type, lr.start_date::text, lr.end_date::text, lr.status
    FROM leave_requests lr JOIN leave_types lt ON lt.id=lr.leave_type_id
    WHERE (lr.user_id=$1::uuid OR lr.employee_id=$1::uuid) AND lt.name=ANY($2::text[])
      AND lr.status IN ('pending','pending_department_head','pending_hr','pending_mayor','approved')
      AND lr.start_date <= $4::date AND lr.end_date >= $3::date`, values:[userId,annual.map(t=>t.name),from,to],query_timeout:10000});
  const result=[];
  for (const type of annual) {
    let approved=0,pending=0;
    for (const row of q.rows.filter(row=>row.leave_type===type.name)) {
      const days=await workingDays.workingDaysWithinYear(pool,userId,row.start_date,row.end_date,year);
      if(row.status==='approved')approved+=days; else pending+=days;
    }
    const allowance=annualAllowance(type,employee?.date_hired,year);
    result.push({leave_type:type.name,year,limit_days:allowance.limit_days,approved_days:approved,pending_days:pending,
      remaining_days:Math.max(0,allowance.limit_days-approved-pending),error:allowance.error_message});
  }
  return result;
}
module.exports={loadAnnualEntitlements};
