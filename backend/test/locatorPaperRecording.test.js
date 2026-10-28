'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const id=n=>`99999999-9999-4999-8999-${String(n).padStart(12,'0')}`;
const paper=()=>({original_filing_date:'2026-09-01',approval_date:'2026-09-02',final_approver:{name:'Original Mayor',position_title:'Municipal Mayor'},confirmed_complete:true,confirmed_not_recorded:true});
function harness(){
 const calls=[],events=[];let payload;
 const db={async query(sql,params=[]){calls.push(sql);
  if(sql.includes('FROM users'))return {rows:[{id:params[0],full_name:params[0]===id(1)?'Encoder':'Applicant',role:params[0]===id(1)?'hr':'employee'}]};
  if(sql.includes('INSERT INTO locator_slips')){payload=params[0];return {rows:[{id:id(20),...JSON.parse(payload)}]};}
  return {rows:[]};},release(){events.push('released');}};
 const deps={pool:{connect:async()=>db},todayInHrmsTimezone:()=> '2026-10-28',
  getLocatorTypeByCode:async()=>({code:'locator',label:'Locator',filing_access:'employee',is_active:true}),
  findAssignmentProfileByUserIdAtDate:async()=>({department_id:id(4),position_title:'Clerk'}),
  validateLocatorWorkingDayForEmployee:async()=>({ok:true}),findLocatorRequestConflicts:async()=>({ok:true}),
  resolveLocatorShiftCoverage:async()=>({can_file:true,single_session:false}),
  captureLocatorTypeSnapshot:()=>({label:'Locator',shortLabel:'Locator',locationLabel:'Destination',coverageMode:'manual'}),
  normalizeLocatorFieldSchema:()=>[],locatorDetailValues:()=>({}),
  recordLocatorWorkflowEvent:async(_db,event)=>{events.push(event);},
  suggestPaperSignatories:async()=>({final_approver:[],department_reviewer:[]}),
 };
 return {calls,events,db,deps,get payload(){return JSON.parse(payload);}};
}
const input=()=>({actor:{id:id(1),role:'hr'},employeeId:id(2),slipDate:'2026-09-10',requestType:'locator',office:'Hall',reason:'Meeting',slots:{amIn:true,amOut:false,pmIn:false,pmOut:false},attachment:{path:'signed.pdf',name:'signed.pdf',mimeType:'application/pdf'},paperApproval:paper()});
test('paper locator records original approval without digital routing and attributes HR only as encoder',async()=>{
 const h=harness(); const service=require('../src/modules/locator/services/paperRecording')(h.deps);
 const row=await service.recordPaperLocator(input());
 assert.equal(row.status,'approved');assert.equal(h.payload.hr_reviewer_id,null);
 assert.equal(h.payload.workflow_snapshot,null);assert.equal(h.payload.paper_approval_record.encoded_by,id(1));
 assert.equal(h.payload.paper_approval_record.applicant.user_id,id(2));
 assert.equal(h.payload.paper_approval_record.final_approver.name,'Original Mayor');
 assert.equal(h.events[0].action,'paper_approved_recorded');assert.equal(h.events[0].actorId,id(1));
 assert.ok(h.calls.includes('COMMIT'));assert.equal(h.events.at(-1),'released');
});
test('paper locator requires HR authority, complete evidence, valid dates and prevents duplicates',async()=>{
 for(const change of [{actor:{id:id(1),role:'employee'}},{employeeId:id(1)},{attachment:null},{paperApproval:{...paper(),confirmed_complete:false}},{paperApproval:{...paper(),approval_date:'2026-02-30'}}]){
  const h=harness();await assert.rejects(require('../src/modules/locator/services/paperRecording')(h.deps).recordPaperLocator({...input(),...change}),e=>[400,403].includes(e.statusCode));
 }
 const h=harness();h.deps.findLocatorRequestConflicts=async()=>({ok:false,message:'Already recorded'});
 await assert.rejects(require('../src/modules/locator/services/paperRecording')(h.deps).recordPaperLocator(input()),{statusCode:409});
 assert.ok(h.calls.includes('ROLLBACK'));assert.equal(h.calls.some(sql=>sql.includes('INSERT INTO')),false);
});

test('failed paper uploads are removed and unauthorized paper revocation is blocked',async()=>{
 const removed=[];
 const controller=require('../src/modules/locator/controllers/paperRecording.controller')({
  LOCATOR_ATTACHMENT_SUBDIR:'locator-attachments',boolField:v=>v===true,normalizeRequestType:v=>v,
  recordPaperLocator:async()=>{throw Object.assign(Error('Evidence incomplete'),{statusCode:400});},
  removeLocatorAttachmentFile:p=>removed.push(p),
 });
 const res=()=>({code:200,status(c){this.code=c;return this;},json(body){this.body=body;return this;}});
 const failed=res();await controller.recordApprovedPaper({user:{id:id(1),role:'hr'},body:{},file:{filename:'new.pdf',originalname:'signed.pdf',mimetype:'application/pdf'}},failed);
 assert.equal(failed.code,400);assert.deepEqual(removed,['locator-attachments/new.pdf']);
 const queries=[];const client={query:async sql=>{queries.push(sql);return {rows:sql.includes('SELECT id')?[{id:id(20),status:'approved',paper_approval_record:{source:'approved_paper'}}]:[]};},release(){}};
 const revoke=require('../src/modules/locator/controllers/revoke.controller')({pool:{connect:async()=>client},evaluateLocatorRevocation(){throw Error('Paper approvals must not enter the digital policy');}});
 const blocked=res();await revoke.revokeRequest({user:{id:id(1),role:'employee'},params:{id:id(20)},body:{reason:'Recorded on paper'}},blocked);
 assert.equal(blocked.code,403);assert.ok(queries.includes('ROLLBACK'));assert.equal(queries.some(sql=>/^\s*UPDATE\b/.test(sql)),false);
});
