'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
test('current Mayor can read form credits and pending signatures after a handover; former Mayor cannot',async()=>{
  const id='11111111-1111-4111-8111-111111111111';
  const snapshot={steps:['mayor'],current_step:0,decisions:[]};
  const seen=[];
  const db={query:async(sql,params=[])=>{
    if(/^(CREATE|ALTER)\b/.test(String(sql).trim()))return {rows:[]};
    if(String(sql).trim().startsWith('UPDATE leave_types'))return {rows:[]};
    if(sql.includes('AS can_view')) {seen.push({sql,params});return {rows:[{employee_id:'employee',can_view:params[3]===true && sql.includes("'mayor_direct'")}]};}
    if(sql.includes('FROM leave_balances'))return {rows:[]};
    if(sql.startsWith('SELECT id,user_id,employee_id,status,workflow_snapshot FROM leave_requests'))return {rows:[{id,employee_id:'employee',workflow_snapshot:snapshot}]};
    if(sql.includes('FROM leave_requests lr'))return {rows:[{id,status:'pending_mayor',employee_user_id:'employee',final_reviewer_user_id:'former',
      final_review_route:'mayor_direct',workflow_snapshot:snapshot,signature_revision:1}]};
    if(sql.startsWith('SELECT workflow_snapshot'))return {rows:[{workflow_snapshot:snapshot}]};
    if(sql.includes('docutracker_leave_signatures'))return {rows:[]};
    throw Error('Unexpected query '+sql);
  }};
  const restores=[withMockedModule('../src/config/db',{pool:db}),
    withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>({employee_id:'current',name:'Current Mayor'})})];
  clearModule('../src/routes/leaveRoutes');clearModule('../src/services/docutrackerLeaveSignatureService');
  try {
    const signatures=require('../src/services/docutrackerLeaveSignatureService');
    const bundle=await signatures.getLeaveSourceSignatures(db,{id:'current',role:'mayor'},'dtr','leave_requests',id);
    assert.equal(bundle.signatures.find(s=>s.slot_key==='hr_approver').can_sign,true);
    await assert.rejects(signatures.getLeaveSourceSignatures(db,{id:'former',role:'mayor'},'dtr','leave_requests',id),{code:'FORBIDDEN'});
    const router=require('../src/routes/leaveRoutes');
    const handle=router.stack.find(s=>s.route?.path==='/:id/form-credits').route.stack.at(-1).handle;
    for(const [viewer,expected] of [['current',200],['former',403]]){
      const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;}};
      await handle({user:{id:viewer,role:'mayor'},params:{id}},res);
      assert.equal(res.code,expected);
    }
  }finally{clearModule('../src/routes/leaveRoutes');clearModule('../src/services/docutrackerLeaveSignatureService');restores.reverse().forEach(r=>r());}
});
