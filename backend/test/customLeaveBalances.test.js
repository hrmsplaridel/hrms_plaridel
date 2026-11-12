const test=require('node:test');
const assert=require('node:assert/strict');
const createController=require('../src/modules/leave/controllers/balances.controller');
const {serviceEligibility}=require('../src/services/leaveServiceEligibility');

test('new own wallets appear at zero before any credit posting without creating records',async()=>{
 const calls=[];
 const pool={query:async(sql)=>{
  calls.push(sql);
  if(sql.includes("balance_ledger_type = 'ownBalance'") && sql.includes('FROM leave_types'))
   return {rows:[{name:'wellness',display_name:'Wellness Leave',sex_eligibility:'any',eligible_employment_types:['permanent'],minimum_service_months:0}]};
  if(sql.includes('SELECT sex, employment_type'))return {rows:[{sex:'female',employment_type:'permanent',date_hired:'2020-01-01',leave_credit_eligible:true}]};
  return {rows:[]};
 }};
 const controller=createController({pool,ENTITLEMENT_BASES:{ANNUAL:'annual',COMPLIANCE:'compliance'},
  normalizeEntitlementBasis:()=> 'accrual',normalizeSexEligibility:(sex)=>sex,
  serviceEligibility,todayInHrmsTimezone:()=> '2026-11-12'});
 const res={status(n){this.code=n;return this;},json(data){this.data=data;}};
 await controller.getBalances({user:{id:'test',role:'employee'},params:{userId:'test'}},res);
 assert.equal(res.data.length,1);assert.equal(res.data[0].leave_type,'wellness');
 assert.equal(res.data[0].record_kind,'credit_balance');assert.equal(res.data[0].earned_days,0);
 assert.ok(calls.every(sql=>!sql.includes('INSERT')),'Viewing balances is read only');
});
