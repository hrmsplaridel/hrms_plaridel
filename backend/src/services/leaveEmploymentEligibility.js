const {EMPLOYMENT_TYPES}=require('../utils/employeeAccountValidation');

function normalizeEligibleEmploymentTypes(value) {
  if(value==null) return null;
  if(!Array.isArray(value)||!value.length||value.some(v=>typeof v!=='string'||![...EMPLOYMENT_TYPES, 'regular'].includes(v))) {
    throw Object.assign(Error('Eligible employment types must contain at least one supported employment type, or null for no restriction'),{statusCode:400});
  }
  return [...new Set(value)];
}

async function assertLeaveEmploymentEligibility(db,rule,userId) {
  if(rule?.eligible_employment_types==null) return;
  const result=await db.query('SELECT employment_type FROM users WHERE id=$1::uuid LIMIT 1',[userId]);
  if(!rule.eligible_employment_types.includes(result.rows[0]?.employment_type)) {
    throw Object.assign(Error(`${rule.display_name||'This leave type'} is not available for your employment type. Contact HR to verify your employee profile.`),{statusCode:403});
  }
}
module.exports={normalizeEligibleEmploymentTypes,assertLeaveEmploymentEligibility};
