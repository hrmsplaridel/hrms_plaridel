'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
const today=require('../src/utils/dateRangeParser').todayInHrmsTimezone();
const ids={employee:'11111111-1111-4111-8111-111111111111',head:'22222222-2222-4222-8222-222222222222',
  hr:'33333333-3333-4333-8333-333333333333',mayor:'44444444-4444-4444-8444-444444444444',request:'55555555-5555-4555-8555-555555555555'};
for(const format of ['legacy','shared']) for(const kind of ['leave','locator']) for(const action of ['approve','return','reject']) {
  test(`${format} ${kind}: Department -> HR -> Mayor ${action} at the last step preserves accounting and workflow state`,async()=>{
    const row={id:ids.request,employee_id:ids.employee,user_id:ids.employee,status:format==='shared'?'pending_hr':'pending_department_head',
      final_review_route:'mayor_direct',final_reviewer_user_id:ids.mayor,signature_revision:1,
      start_date:'2026-10-15',end_date:'2026-10-15',slip_date:today,slip_date_text:today,days:1,number_of_days:1,
      leave_type_name:'Wellness',reserved_credit_days:1,workflow_snapshot:{id:'workflow',name:'Full approval',version:1,
        steps:['department','hr','mayor'],current_step:0,decisions:[]}};
    if(format==='shared')row.workflow_snapshot.steps=['Initial reviewer','HR review','Mayor approval'].map((label,index)=>({
      step_order:index+1,label,assignee_type:'user',assignee_source:index===2?'active_mayor':'specific_users',
      user_ids:index===0?[ids.head]:index===1?[ids.hr]:[],requires_signature:true,allowed_actions:['approve','return','reject']}));
    let deducted=0,coverage=0;
    const statements=[],notifications=[];
    async function query(sql,params=[]) {
      const s=String(sql).replace(/\s+/g,' ').trim();statements.push(s);
      if(s.startsWith('SELECT workflow_snapshot'))return {rows:[{workflow_snapshot:structuredClone(row.workflow_snapshot)}]};
      if(s.startsWith('SELECT * FROM leave_requests') || s.startsWith('SELECT * FROM locator_slips'))return {rows:[structuredClone(row)]};
      if(s.includes('FOR UPDATE OF lr') || s.includes('FOR UPDATE OF ls') || s.includes('FROM locator_slips') && s.endsWith('FOR UPDATE'))return {rows:[structuredClone(row)]};
      if(s.includes('JOIN users u ON u.id=r.reviewer_id'))return {rows:[{id:ids.head,name:'Head'}]};
      if(s.includes('FROM users WHERE id=ANY'))return {rows:params[0].map(id=>({id,name:id,role:'employee'}))};
      if(s.includes('FROM primary_reviewer_designations'))return {rows:[{id:ids.hr,name:'HR',role:'hr'}]};
      if(s.includes('FROM leave_final_reviewer_backups'))return {rows:[]};
      if(s.startsWith('SELECT final_review_route'))return {rows:[structuredClone(row)]};
      if(s.startsWith('SELECT * FROM leave_types'))return {rows:[{name:'Wellness',requires_attachment:false,balance_ledger_type:'Wellness',affects_dtr_normally:true}]};
      if(s.includes('FROM generate_series'))return {rows:[{attendance_date:'2026-10-15',working_days:[1,2,3,4,5],has_shift:true}]};
      if(s.includes('FROM leave_balances'))return {rows:[{earned_days:10,used_days:deducted,pending_days:row.reserved_credit_days,adjusted_days:0}]};
      if(s.startsWith('SELECT balance_ledger_type'))return {rows:[{balance_ledger_type:'Wellness'}]};
      if(s.startsWith('INSERT INTO leave_balances'))deducted+=Number(params[2]);
      if(s.startsWith('UPDATE leave_requests') || s.startsWith('UPDATE locator_slips')) {
        if(s.includes('SET workflow_snapshot='))row.workflow_snapshot=JSON.parse(params[1]);
        else if(s.includes("status = 'returned_for_correction'"))row.status='returned_for_correction';
        else if(s.includes("status = 'returned'"))row.status='returned';
        else if(s.includes("status = 'rejected_by_hr'"))row.status='rejected_by_hr';
        else if(s.includes("status = 'rejected'"))row.status='rejected';
        else if(s.includes("status = 'approved'")) {row.status='approved';row.reserved_credit_days=0;}
        else if(s.includes('SET status=$2') || s.includes('SET status = $2'))row.status=params[1];
        else if(s.includes('SET status = $4'))row.status=params[3];
        return {rows:[structuredClone(row)]};
      }
      if(s.startsWith('SELECT lr.*') || s.startsWith('SELECT ls.*'))return {rows:[{...structuredClone(row),employee_full_name:'Employee'}]};
      return {rows:[],rowCount:0};
    }
    const pool={query,connect:async()=>({query,release(){}})};
    const coverageService=require('../src/services/leaveDtrCoverage');
    const locatorSignatures=require('../src/services/locatorSignatureService');
    const conflict=require('../src/services/locatorConflictPolicy');
    const department=require('../src/services/departmentHeadService');
    const restores=[withMockedModule('../src/config/db',{pool}),
      withMockedModule('../src/services/docutrackerWorkflowService',{resolveStepAssignees:async(db,{stepConfig})=>stepConfig.user_ids}),
      withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>({employee_id:ids.mayor,name:'Mayor'})}),
      withMockedModule('../src/services/docutrackerLeaveSignatureService',{requireDepartmentHeadApprovalSignature:async()=>{},requireHrApprovalSignature:async()=>{}}),
      withMockedModule('../src/services/locatorSignatureService',{...locatorSignatures,persistLocatorSignature:async()=>{}}),
      withMockedModule('../src/services/leaveDtrCoverage',{...coverageService,replaceApprovedLeaveCoverage:async()=>coverage++}),
      withMockedModule('../src/services/locatorConflictPolicy',{...conflict,findLocatorRequestConflicts:async()=>({ok:true})}),
      withMockedModule('../src/services/departmentHeadService',{...department,isDepartmentHead:async()=>({isHead:true,departmentId:null})}),
      ...['leave','locator'].map(module=>withMockedModule(`../src/services/${module}Notifications`,new Proxy({}, {get:()=>async(...args)=>notifications.push(args)}))),
    ];
    const module=kind==='leave'?'../src/routes/leaveRoutes':'../src/routes/locatorSlips';
    clearModule(module);const oldError=console.error;console.error=()=>{};
    try {
      const router=require(module);
      async function act(actor,endpoint) {
        const handler=router.stack.find(s=>s.route?.path===endpoint && s.route.methods.patch).route.stack.at(-1).handle;
        const response={code:200,status(c){this.code=c;return this;},json(body){this.body=body;}};
        await handler({user:{id:ids[actor],role:actor==='head'?'employee':actor},params:{id:ids.request},body:{approved_days_with_pay:1,approved_days_without_pay:0,reviewer_remarks:'Reviewed'}},response);
        assert.equal(response.code,200,JSON.stringify(response.body));
      }
      await act('head',format==='shared'?'/:id/approve':'/:id/department-head-approve');
      assert.equal(row.status,'pending_hr');assert.equal(deducted,0);assert.equal(coverage,0);
      function assertLeaveForwardNotice(status) {
        if (kind !== 'leave') return;
        const input = notifications.map(args => args[1]).find(n => n.status === status);
        assert.ok(input, `Expected a notification for ${status}`);
        assert.equal(input.employeeName, 'Employee');
        assert.equal(input.leaveTypeName, 'Wellness');
        assert.equal(input.startDateStr, '2026-10-15');
        assert.equal(input.endDateStr, '2026-10-15');
        assert.equal(input.employeeUserId, ids.employee);
        assert.equal(input.leaveRequestId, ids.request);
      }
      if (format === 'shared') assertLeaveForwardNotice('pending_hr');
      await act('hr','/:id/approve');
      assert.equal(row.status,'pending_mayor');assert.equal(deducted,0);assert.equal(coverage,0);
      assertLeaveForwardNotice('pending_mayor');
      await act('mayor',action==='return' && kind==='locator'?'/:id/return-for-correction':`/:id/${action}`);
      if(action!=='approve'){
        assert.equal(row.status,action==='return'?(kind==='locator'?'returned_for_correction':'returned'):(kind==='locator'?'rejected_by_hr':'rejected'));
        assert.equal(row.workflow_snapshot.outcome,row.status);
        assert.equal(deducted,0);assert.equal(coverage,0);return;
      }
      assert.equal(row.status,'approved');
      assert.equal(row.workflow_snapshot.current_step,3);
      assert.deepEqual(row.workflow_snapshot.decisions.map(d=>d.actor_id),[ids.head,ids.hr,ids.mayor]);
      assert.equal(deducted,kind==='leave'?1:0);assert.equal(coverage,kind==='leave'?1:0);
    }finally {console.error=oldError;clearModule(module);restores.reverse().forEach(r=>r());}
  });
}
