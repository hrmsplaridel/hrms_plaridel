'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
const engine=require('../src/services/approvalWorkflows');
const id=n=>`11111111-1111-4111-8111-${String(n).padStart(12,'0')}`;
const people={owner:id(1),head:id(2),primary:id(3),backup:id(4),mayor:id(5),stranger:id(6)};
const viewers=[['owner','employee',true],['head','employee',true],['primary','employee',true],['backup','admin',true],
 ['mayor','mayor',false],['stranger','employee',false],['stranger','admin',false],['stranger','hr',false]];

for(const kind of ['leave','locator']) for(const [viewer,role,allowed] of viewers) {
 test(`${kind} pending workflow reads: ${viewer}/${role} is ${allowed?'authorized':'denied'}`,async()=>{
  const row={id:id(20),employee_id:people.owner,user_id:people.owner,employee_user_id:people.owner,
   employee_name:'Applicant',employee_full_name:'Applicant',status:'pending_hr',signature_revision:1,
   final_review_route:'mayor_direct',slip_date:'2026-10-20',slip_date_text:'2026-10-20',
   print_signatories:{applicant:{id:people.owner,name:'Applicant',position_title:''},
    department_head:{id:people.head,name:'Department Reviewer',position_title:''},hr_approver:{id:people.mayor,name:'Mayor',position_title:''}},
   workflow_snapshot:{name:'Department HR Mayor',version:1,current_step:1,
    steps:[{label:'Department',assignee_source:'specific_users',user_ids:[people.head]},
     {label:'HR Review',assignee_source:'specific_users',user_ids:[people.primary,people.backup],allowed_actions:['approve']},
     {label:'Mayor',assignee_source:'active_mayor',user_ids:[]}],
    decisions:[{step:0,actor_id:people.head,action:'approve'}]}};
  const user={id:people[viewer],role};
  let signatureReads=0,balanceReads=0;
  async function query(sql,params=[]) {
   const s=String(sql).replace(/\s+/g,' ').trim();
   if(s.startsWith('SELECT workflow_snapshot'))return{rows:[{workflow_snapshot:row.workflow_snapshot}]};
   if(s.includes('FROM users WHERE id=ANY'))return{rows:params[0].map(id=>({id,name:id,role:'employee'}))};
   if(s.includes('FROM docutracker_leave_signatures')||s.includes('FROM docutracker_locator_signatures')){signatureReads++;return{rows:[]};}
   if(s.includes('AS can_view'))return{rows:[{...row,can_view:role==='admin'||role==='hr'||viewer==='owner'||viewer==='mayor'}]};
   if(s.includes('FROM leave_balances lb')){balanceReads++;return{rows:[]};}
   if(s.includes('FROM locator_slips ls LEFT JOIN locator_print_template_versions')&&!params[4]&&!['admin','hr','mayor'].includes(role)&&viewer!=='owner')return{rows:[]};
   if(s.startsWith('SELECT * FROM locator_slips WHERE id='))return{rows:[row]};
   if(s.startsWith('SELECT lr.*')||s.startsWith('SELECT ls.')||s.includes('FROM leave_requests lr')||s.startsWith('SELECT id,user_id,employee_id,status,workflow_snapshot'))return{rows:[row]};
   if(s.includes('FROM locator_slip_history'))return{rows:[]};
   if(s.includes('FROM leave_request_history'))return{rows:[]};
   return{rows:[],rowCount:0};
  }
  const pool={query,connect:async()=>({query,release(){}})};
  const restores=[withMockedModule('../src/config/db',{pool}),
   withMockedModule('../src/services/docutrackerWorkflowService',{resolveStepAssignees:async(_,opts)=>opts.stepConfig.user_ids}),
   withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>({employee_id:people.mayor,name:'Mayor'})}),
   withMockedModule('../src/services/approvalWorkflows',{...engine,printOfficials:async()=>row.print_signatories}),
   withMockedModule('../src/services/leaveFinalReviewerService',{...require('../src/services/leaveFinalReviewerService'),resolveFinalLeaveReviewerConfiguration:async()=>({primary:null})})];
  const signatureModule=kind==='leave'?'../src/services/docutrackerLeaveSignatureService':'../src/services/locatorSignatureService';
  const routeModule=kind==='leave'?'../src/routes/leaveRoutes':'../src/routes/locatorSlips';
  const modules=[signatureModule,routeModule,'../src/routes/leavePrintTemplates','../src/routes/locatorPrintTemplates'];
  modules.forEach(clearModule);
  try{
   const service=require(signatureModule);
   const read=()=> (kind==='leave'?service.getLeaveSourceSignatures:service.getLocatorSourceSignatures)(pool,user,'dtr',kind==='leave'?'leave_requests':'locator_slips',row.id);
   if(allowed)await read();else await assert.rejects(read(),e=>['FORBIDDEN','NOT_FOUND'].includes(e.code));
   assert.equal(signatureReads>0,allowed,'Denied readers must not fetch signature image bytes');
   const router=require(routeModule);
   const paths=kind==='leave'?['/:id','/:id/form-credits','/:id/attachment','/signatories']:['/:id/history','/:id/attachment'];
   for(const path of paths){
    const res={code:200,status(n){this.code=n;return this;},json(body){this.body=body;return this;}};
    await router.stack.find(l=>l.route?.path===path&&l.route.methods.get).route.stack.at(-1).handle({user,params:{id:row.id},query:{employee_id:people.owner,leave_request_id:row.id},get(){return 'test';}},res);
    if(path.endsWith('/attachment'))assert.equal(res.body.error,allowed?'No attachment for this request':kind==='leave'?'Leave request not found':'Locator slip not found',path);
    else assert.equal(res.code,allowed?200:['/:id/form-credits','/signatories'].includes(path)?403:404,path);
   }
   if(kind==='leave') {
    assert.equal(balanceReads,allowed?1:0);
    const print=require('../src/routes/leavePrintTemplates');
    const res={code:200,status(n){this.code=n;return this;},json(body){this.body=body;}};
    await print.stack.find(l=>l.route?.path==='/requests/:id'&&l.route.methods.get).route.stack.at(-1).handle({user,params:{id:row.id}},res);
    assert.equal(res.code,allowed?200:404,'Print metadata uses the same workflow access');
   }else{
    const print=require('../src/routes/locatorPrintTemplates');
    const res={code:200,status(n){this.code=n;return this;},json(body){this.body=body;return this;}};
    await print.stack.find(l=>l.route?.path==='/requests/:id/render'&&l.route.methods.post).route.stack.at(-1).handle({user,params:{id:row.id},body:{}},res);
    assert.equal(res.code,allowed?400:404,'Locator print uses the same workflow access before processing PDF bytes');
   }
  }finally{modules.forEach(clearModule);restores.reverse().forEach(restore=>restore());}
 });
}
