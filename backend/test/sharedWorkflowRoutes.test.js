'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
const id='11111111-1111-4111-8111-111111111111',backup='22222222-2222-4222-8222-222222222222';
test('inbox route forwards bounded paging and exact-request options',async()=>{
 let received;
 const restores=[withMockedModule('../src/config/db',{pool:{}}),
  withMockedModule('../src/services/sharedWorkflowInbox',{listInbox:async(_db,user,options)=>{
   received={user,options};return {items:[],has_more:{leave:false},next_cursor:{leave:null}};
  }})];
 clearModule('../src/routes/approvalWorkflows');
 try{
  const router=require('../src/routes/approvalWorkflows');
  const handler=router.stack.find(s=>s.route?.path==='/inbox').route.stack.at(-1).handle;
  const req={user:{id},query:{paginated:'true',include_history:'true',kind:'leave',limit:'50',cursor:'cursor',request_id:backup}};
  const res={json(value){this.body=value;}};
  await handler(req,res);
  assert.deepEqual(received,{user:req.user,options:{paginated:true,includeHistory:true,kind:'leave',limit:'50',cursor:'cursor',requestId:backup}});
  assert.deepEqual(res.body.items,[]);
 }finally{clearModule('../src/routes/approvalWorkflows');restores.reverse().forEach(r=>r());}
});
for(const scenario of ['backup','outsider','stale','not-allowed'])test(`shared inbox decision: ${scenario}`,async()=>{
 const snapshot={name:'Custom',steps:[{step_order:1,label:'Initial approval',assignee_type:'user',assignee_source:'specific_users',user_ids:[id,backup],allowed_actions:['approve','reject']}],current_step:0,decisions:[]};
 const row={id,employee_id:'applicant',status:'pending_hr',signature_revision:2,workflow_snapshot:snapshot};
 const query=async(sql)=>({rows:sql.startsWith('SELECT *')?[row]:[{id},{id:backup}]});
 let delegated=false;
 const restores=[withMockedModule('../src/config/db',{pool:{query}}),
  withMockedModule('../src/services/docutrackerWorkflowService',{resolveStepAssignees:async()=>[id,backup]}),
  withMockedModule('../src/routes/leaveRoutes',{stack:[{route:{path:'/:id/approve',methods:{patch:true},stack:[{handle:async(req,res)=>{delegated=true;assert.deepEqual(req.sharedWorkflowExpected,{step:0,revision:2});res.json({status:'pending_hr'});}}]}}]}),
 ];
 clearModule('../src/routes/approvalWorkflows');
 try {
  const router=require('../src/routes/approvalWorkflows');
  const handler=router.stack.find(s=>s.route?.path==='/requests/:kind/:id/:action').route.stack.at(-1).handle;
  const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
  await handler({user:{id:scenario==='outsider'?'outsider':backup,role:'employee'},params:{kind:'leave',id,action:scenario==='not-allowed'?'return':'approve'},body:{expected_step:scenario==='stale'?1:0,signature_revision:2}},res);
  assert.equal(res.code,scenario==='backup'?200:scenario==='stale'?409:403);
  assert.equal(delegated,scenario==='backup');
 }finally{clearModule('../src/routes/approvalWorkflows');restores.reverse().forEach(r=>r());}
});
test('publishing rejects inactive or missing specific reviewers before writing a version',async()=>{
 const calls=[];
 const query=async(sql)=>{calls.push(sql);return {rows:[]};};
 const restore=withMockedModule('../src/config/db',{pool:{connect:async()=>({query,release(){}})}});
 clearModule('../src/routes/approvalWorkflows');
 try {
  const router=require('../src/routes/approvalWorkflows');
  const handler=router.stack.find(s=>s.route?.path==='/' && s.route.methods.post).route.stack.at(-1).handle;
  const res={code:200,status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
  await handler({user:{id},params:{},body:{name:'Invalid reviewers',steps:[{step_order:1,label:'Final',assignee_type:'user',assignee_source:'specific_users',user_ids:[backup],allowed_actions:['approve']}]}},res);
  assert.equal(res.code,400);assert.match(res.body.error,/active reviewer/i);
  assert.ok(!calls.some(s=>s.includes('INSERT INTO approval_workflow_versions')));
 }finally{clearModule('../src/routes/approvalWorkflows');restore();}
});
