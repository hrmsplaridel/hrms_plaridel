'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const engine = require('../src/services/approvalWorkflows');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');
const id = n => `11111111-1111-4111-8111-${String(n).padStart(12,'0')}`;
const applicant=id(1), primary=id(2), backup=id(3), workflow=id(4);
const person = (id,name) => ({id,employee_id:id,name,position_title:'Reviewer'});
const step = {step_order:1,label:'Office review',assignee_type:'user',assignee_source:'specific_users',user_ids:[primary,backup],requires_signature:true,allowed_actions:['approve','return','reject']};

test('backup printing defaults to keeping the primary and validates both choices', () => {
  assert.equal(engine.normalizeWorkflow({name:'Default',steps:[step]}).backup_signatory_policy,'keep_primary');
  for(const policy of ['keep_primary','actual_reviewer']) {
    assert.equal(engine.normalizeWorkflow({name:'Choice',steps:[step],backup_signatory_policy:policy}).backup_signatory_policy,policy);
  }
  for(const policy of [null,'',false,{},[],'mayor']) {
    assert.throws(()=>engine.normalizeWorkflow({name:'Invalid',steps:[step],backup_signatory_policy:policy}),{statusCode:400});
  }
});

for(const policy of ['keep_primary','actual_reviewer']) test(`catalog and published versions persist backup printing: ${policy}`,async()=>{
  const calls=[];
  const query=async(sql,params=[])=>{
    calls.push({sql,params});
    if(sql.startsWith('SELECT w.*'))return {rows:[{id:workflow,backup_signatory_policy:policy}]};
    if(sql.startsWith('SELECT * FROM approval_workflows'))return {rows:[{id:workflow,current_version:1}]};
    if(/^(INSERT INTO|UPDATE) approval_workflows/.test(sql))return {rows:[{id:workflow,current_version:2}]};
    return {rows:[]};
  };
  const restores=[withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}}),
    withMockedModule('../src/services/sharedDocumentWorkflows',{syncLinkedDocumentWorkflows:async()=>{}})];
  clearModule('../src/routes/approvalWorkflows');
  try {
    const router=require('../src/routes/approvalWorkflows');
    const response=()=>({code:200,status(c){this.code=c;return this;},json(data){this.data=data;}});
    const catalog=response();
    await router.stack.find(s=>s.route?.path==='/'&&s.route.methods.get).route.stack.at(-1).handle({},catalog);
    assert.match(calls.at(-1).sql,/v\.backup_signatory_policy/);
    for(const edit of [false,true]) {
      const res=response();
      await router.stack.find(s=>s.route?.path===(edit?'/:id':'/')&&s.route.methods[edit?'put':'post']).route.stack.at(-1).handle({
        params:edit?{id:workflow}:{},user:{id:primary},body:{name:'Office',steps:['hr'],current_version:1,backup_signatory_policy:policy}},res);
      assert.equal(res.code,edit?200:201,JSON.stringify(res.data));
      const insert=calls.filter(c=>c.sql.startsWith('INSERT INTO approval_workflow_versions')).at(-1);
      assert.match(insert.sql,/backup_signatory_policy/);
      assert.equal(insert.params[6],policy);
      assert.equal(res.data.backup_signatory_policy,policy);
    }
  } finally {clearModule('../src/routes/approvalWorkflows');restores.reverse().forEach(restore=>restore());}
});

for(const kind of ['leave','locator']) test(`${kind} freezes primary identity and backup policy across corrections`,async()=>{
  const restore=withMockedModule('../src/services/docutrackerWorkflowService',{resolveStepAssignees:async()=>[primary,backup]});
  let name='Original Primary';
  const db={query:async(sql)=>({rows:sql.includes('FROM approval_workflows w')?[{id:workflow,name:'Office',version:1,is_active:true,steps:[step],backup_signatory_policy:'keep_primary'}]:
    sql.includes('WHERE id=ANY')?[{id:primary},{id:backup}]:[person(primary,name)]})};
  try {
    const snapshot=await engine.prepareWorkflow(db,kind,{approval_workflow_id:workflow},applicant);
    assert.equal(snapshot.backup_signatory_policy,'keep_primary');
    assert.equal(snapshot.primary_signatories[0].id,primary);
    assert.equal(snapshot.primary_signatories[0].name,'Original Primary');
    name='Changed Name';
    const correction=await engine.prepareWorkflow(db,kind,{approval_workflow_snapshot:snapshot},applicant);
    assert.deepEqual(correction.primary_signatories,snapshot.primary_signatories);
    assert.equal(correction.backup_signatory_policy,'keep_primary');
    const old=await engine.prepareWorkflow(db,kind,{approval_workflow_snapshot:{...snapshot,backup_signatory_policy:undefined,primary_signatories:undefined}},applicant);
    assert.equal(old.backup_signatory_policy,'actual_reviewer','Older request snapshots retain their previous printing behavior');
  } finally {restore();}
});

for(const kind of ['leave','locator']) for(const policy of ['keep_primary','actual_reviewer',undefined]) test(`${kind} printed identity follows ${policy||'historical'} policy without changing the acting reviewer`,async()=>{
  const row={employee_id:applicant,status:'approved',signature_revision:1,workflow_snapshot:{steps:[step],current_step:1,
    backup_signatory_policy:policy,primary_signatories:[person(primary,'Official Primary')],
    decisions:[{step:0,actor_id:backup,action:'approve',reviewer:person(backup,'Acting Backup'),signature:{revision:1,signature_asset_id:id(8),signer_name_snapshot:'Acting Backup'}}]}};
  const db={query:async()=>{throw new Error('Frozen identities should not require current organization lookups');}};
  const result=await engine.printOfficials(db,kind,row);
  assert.equal(result.hr_approver.id,policy==='keep_primary'?primary:backup);
  assert.equal(result.hr_approver.name,policy==='keep_primary'?'Official Primary':'Acting Backup');
  const printed=await engine.workflowPrintSignatories(db,kind,row);
  assert.equal(printed.workflow_step_1.user_id,policy==='keep_primary'?primary:backup);
  assert.equal(row.workflow_snapshot.decisions[0].actor_id,backup);
});

test('fresh schema and migration include the constrained default without rewriting filed requests',()=>{
  const root=path.join(__dirname,'../scripts');
  const schema=fs.readFileSync(path.join(root,'init-schema.sql'),'utf8');
  const migration=fs.readFileSync(path.join(root,'migrations/dtr/20261111_workflow_backup_signatories.sql'),'utf8');
  for(const sql of [schema,migration]) {
    assert.match(sql,/backup_signatory_policy TEXT NOT NULL DEFAULT 'keep_primary'/);
    assert.match(sql,/CHECK \(backup_signatory_policy IN \('keep_primary', 'actual_reviewer'\)\)/);
  }
  assert.doesNotMatch(migration,/UPDATE\s+(leave_requests|locator_slips)/i);
});

for(const primaryStep of [0,1]) test(`Locator never borrows the primary's ink from step ${primaryStep+1} for a backup-approved block`,async()=>{
  const row={id:id(10),employee_id:applicant,employee_name:'Applicant',status:'approved',signature_revision:1,
    print_signatories:{applicant:person(applicant,'Applicant')},workflow_snapshot:{steps:[step,{...step,step_order:2}],current_step:2,
      backup_signatory_policy:'keep_primary',primary_signatories:[person(primary,'Primary'),person(primary,'Primary')],
      decisions:[0,1].map(index=>({step:index,actor_id:index===primaryStep?primary:backup,action:'approve',
        reviewer:person(index===primaryStep?primary:backup,index===primaryStep?'Primary':'Backup'),
        signature:{revision:1,signature_asset_id:id(20+index),signer_name_snapshot:index===primaryStep?'Primary':'Backup'}}))}};
  const db={query:async(sql)=>({rows:sql.includes('FROM locator_slips ls')?[row]:sql.includes('FROM docutracker_signature_assets')?
    row.workflow_snapshot.decisions.map(d=>({id:d.signature.signature_asset_id,owner_user_id:d.actor_id,signature_image_base64:'aW5r'})):[]})};
  const result=await require('../src/services/locatorSignatureService').getLocatorSourceSignatures(db,{id:applicant,role:'employee'},'dtr','locator_slips',row.id);
  assert.equal(result.print_signatories[primaryStep===0?'department_head':'hr_approver'].signature_image_base64,'aW5r');
  assert.equal(result.print_signatories[primaryStep===0?'hr_approver':'department_head'].name,'Primary');
  assert.equal(result.print_signatories[primaryStep===0?'hr_approver':'department_head'].signature_image_base64,null);
});

for(const policy of ['mayor','blank','actual_reviewer']) test(`backup default preserves the separate self-filing ${policy} rule`,async()=>{
  const mayor=id(40);
  const restore=withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>person(mayor,'Mayor')});
  const row={employee_id:applicant,status:'approved',print_signatories:{hr_approver:person(primary,'HR Official')},
    workflow_snapshot:{steps:[step],backup_signatory_policy:'keep_primary',self_filing_signatory_policy:policy,
      primary_signatories:[person(applicant,'Applicant')],decisions:[{step:0,actor_id:backup,action:'approve',reviewer:person(backup,'Backup')} ]}};
  try {
    const result=await engine.workflowPrintSignatories({},'leave',row);
    assert.equal(result.workflow_step_1.user_id,policy==='mayor'?mayor:policy==='actual_reviewer'?backup:null);
  } finally {restore();}
});
