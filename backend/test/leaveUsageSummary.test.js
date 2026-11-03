const test = require('node:test');
const assert = require('node:assert/strict');
const policy = require('../src/services/leaveEntitlementPolicy');
const create = require('../src/modules/leave/controllers/balances.controller');

for (const employment of ['permanent', 'job_order']) {
  test(`usage summaries include eligible forced-leave compliance without creating credits: ${employment}`, async () => {
    const queries = [];
    const query = async (sql, params) => {
      queries.push({sql, params});
      if (sql.includes('SELECT lb.*')) return {rows:[{leave_type:'vacationLeave',earned_days:12,used_days:3,pending_days:2}]};
      if (sql.includes('SELECT name,')) return {rows:[
        {name:'wellnessLeave',display_name:'Wellness Leave',max_days:5,entitlement_basis:'annual'},
        ...(params.includes('compliance') ? [{name:'mandatoryForcedLeave',display_name:'Mandatory/Forced Leave',max_days:5,entitlement_basis:'compliance',eligible_employment_types:['permanent']}] : []),
      ]};
      if (sql.includes('SELECT sex')) return {rows:[{sex:'male',employment_type:employment,date_hired:'2020-01-01'}]};
      if (sql.includes('FROM leave_requests lr')) {
        assert.match(sql, /lr.status IN/);
        assert.deepEqual(params.slice(0,3), ['employee','2026-01-01','2026-12-31']);
        return {rows:[
          {leave_type:'mandatoryForcedLeave',status:'approved',start_date:'2026-01-05',end_date:'2026-01-06'},
          {leave_type:'vacationLeave',status:'approved',start_date:'2026-01-07',end_date:'2026-01-07'},
          {leave_type:'wellnessLeave',status:'approved',start_date:'2026-01-08',end_date:'2026-01-08'},
          {leave_type:'wellnessLeave',status:'pending_hr',start_date:'2026-01-12',end_date:'2026-01-13'},
          {leave_type:'mandatoryForcedLeave',status:'pending_hr',start_date:'2026-01-14',end_date:'2026-01-15'},
        ].filter(row => params[3].includes(row.leave_type))};
      }
      return {rows:[]};
    };
    const controller = create({
      ...policy, pool:{query,connect:async()=>({query,release(){}})},
      todayInHrmsTimezone:()=> '2026-11-01',
      normalizeSexEligibility:()=> 'any', systemLeaveTypeDisplayName:name=>name,
      serviceEligibility:()=>({eligible:true}), toIsoDateStr:value=>value,
      workingDaysWithinYear:async(_db,_id,start,end,year)=>{
        assert.equal(year,2026);return Number(end.slice(-2))-Number(start.slice(-2))+1;
      },
    });
    const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;}};
    await controller.getBalances({user:{id:'employee',role:'employee'},params:{userId:'employee'}},res);
    assert.equal(res.code,200);
    const forced=res.body.find(row=>row.leave_type==='mandatoryForcedLeave');
    if (employment==='permanent') {
      assert.ok(forced,'The five-day requirement should be returned to the employee');
      assert.equal(forced.record_kind,'compliance_progress');
      assert.equal(forced.entitlement_basis,'compliance');
      assert.equal(forced.earned_days,5);
      assert.equal(forced.used_days,3,'Approved forced and vacation leave count toward compliance');
      assert.equal(forced.pending_days,2,'Pending reservations remain available to backend consumers');
      assert.equal(forced.entitlement_year,2026);
    } else assert.equal(forced,undefined);
    const annual=res.body.find(row=>row.leave_type==='wellnessLeave');
    assert.equal(annual.used_days,1);assert.equal(annual.pending_days,2);
    assert.equal(res.body.find(row=>row.leave_type==='vacationLeave').pending_days,2);
    assert.equal(queries.some(({sql})=>/INSERT|UPDATE|DELETE/.test(sql)),false);
  });
}

for (const verified of [true,false]) test(`usage summary includes opening history, verified=${verified}`, async()=>{
 const query=async(sql)=>({rows:sql.includes('SELECT name,')?[{name:'mandatoryForcedLeave',max_days:5,entitlement_basis:'compliance'}]
   :sql.includes('SELECT sex')?[{employment_type:'permanent'}]
   :sql.includes('FROM leave_opening_balance_setups')?[{cutoff_date:'2026-10-31',qualifying_leave_days:verified?3:null}]
   :sql.includes('FROM leave_requests lr')?[
     {leave_type:'vacationLeave',status:'approved',start_date:'2026-03-02',end_date:'2026-03-04'},
     {leave_type:'mandatoryForcedLeave',status:'approved',start_date:'2026-11-02',end_date:'2026-11-03'},
   ]:[]});
 const controller=create({...policy,pool:{query,connect:async()=>({query,release(){}})},todayInHrmsTimezone:()=> '2026-11-01',
   normalizeSexEligibility:()=> 'any',systemLeaveTypeDisplayName:n=>n,serviceEligibility:()=>({eligible:true}),toIsoDateStr:v=>v,
   workingDaysWithinYear:async(_db,_id,start)=>start==='2026-11-02'?2:4});
 const res={status(c){this.code=c;return this;},json(body){this.body=body;}};
 await controller.getBalances({user:{id:'employee',role:'employee'},params:{userId:'employee'}},res);
 const row=res.body.find(r=>r.leave_type==='mandatoryForcedLeave');
 assert.equal(row.used_days,verified?5:2);assert.equal(row.history_verification_required,!verified);
});
