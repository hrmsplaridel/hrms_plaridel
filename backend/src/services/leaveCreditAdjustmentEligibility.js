const leaveCreditAdjustmentEligibilitySql = `(COALESCE(u.leave_credit_eligible, true) = true
 AND lower(btrim(COALESCE(u.employment_type, ''))) NOT IN ('job_order', 'contract_of_service'))`;

function canAdjustLeaveCredits(employee) {
  return !!employee && employee.leave_credit_eligible !== false &&
    !['job_order', 'contract_of_service'].includes(String(employee.employment_type || '').trim().toLowerCase());
}
module.exports = {leaveCreditAdjustmentEligibilitySql, canAdjustLeaveCredits};
