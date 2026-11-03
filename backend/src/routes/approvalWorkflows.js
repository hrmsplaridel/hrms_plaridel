'use strict';
const express=require('express');
const {pool}=require('../config/db');
const {requireAdminOrHr}=require('../middleware/rbac');
const {requireDtrFeatureIfAdmin}=require('../middleware/dtrAccess');
const {normalizeWorkflow}=require('../services/approvalWorkflows');
const router=express.Router();
// Assigned reviewers use this inbox regardless of their global account role.
router.get('/inbox',async(req,res)=>{
  try {res.json(await require('../services/sharedWorkflowInbox').listInbox(pool,req.user,{
   includeHistory:req.query?.include_history==='true',paginated:req.query?.paginated==='true',
   limit:req.query?.limit,kind:req.query?.kind,cursor:req.query?.cursor,requestId:req.query?.request_id,
  }));}
  catch(error){res.status(error.statusCode||500).json({error:error.statusCode?error.message:'Could not load workflow approvals.'});}
});
router.get('/requests/:kind/:id/attachment',async(req,res)=>{
 try {
  await require('../services/sharedWorkflowInbox').getRequest(pool,req.params.kind,req.params.id,req.user);
  req.sharedWorkflowRead=true;
  const module=req.params.kind==='leave'?require('./leaveRoutes'):require('./locatorSlips');
  return await module.stack.find(s=>s.route?.path==='/:id/attachment' && s.route.methods.get).route.stack.at(-1).handle(req,res);
 }catch(error){res.status(error.statusCode||500).json({error:error.statusCode?error.message:'Could not open workflow attachment.'});}
});
router.post('/requests/:kind/:id/:action',async(req,res)=>{
 try {
  const {kind,id,action}=req.params;
  if(!['approve','return','reject'].includes(action))return res.status(400).json({error:'Invalid workflow action.'});
  const row=await require('../services/sharedWorkflowInbox').getRequest(pool,kind,id,req.user,{decision:true});
  if(!row.workflow_snapshot.steps[row.workflow_snapshot.current_step].allowed_actions.includes(action))
    return res.status(403).json({error:'This action is not allowed for this workflow step.'});
  if(req.body?.expected_step!==row.workflow_snapshot.current_step || req.body?.signature_revision!==row.signature_revision)
    return res.status(409).json({error:'This request changed. Refresh before reviewing.'});
  req.sharedWorkflowExpected={step:req.body.expected_step,revision:req.body.signature_revision};
  const module=kind==='leave'?require('./leaveRoutes'):require('./locatorSlips');
  const endpoint=kind==='locator' && action==='return'?'return-for-correction':action;
  const handler=module.stack.find(s=>s.route?.path===`/:id/${endpoint}` && s.route.methods.patch).route.stack.at(-1).handle;
  // Reuse the source module's transactional signature, credit and coverage rules.
  return await handler(req,res);
 }catch(error){res.status(error.statusCode||500).json({error:error.statusCode?error.message:'Could not review workflow request.'});}
});
// Authentication is applied at the mount. Type editors need the read-only catalog.
router.get('/', requireAdminOrHr, async(req,res)=>{
  try {
    const result=await pool.query(`SELECT w.*,v.steps,v.self_filing_signatory_policy FROM approval_workflows w
      JOIN approval_workflow_versions v ON v.workflow_id=w.id AND v.version=w.current_version
      ORDER BY w.name,w.id`);
    res.json(result.rows);
  } catch(error) { res.status(500).json({error:'Could not load approval workflows.'}); }
});
router.use(requireAdminOrHr,requireDtrFeatureIfAdmin('approvals_allowed'));
router.get('/document-types',async(req,res)=>{
 try {res.json((await pool.query(`SELECT t.document_type,t.display_name FROM docutracker_document_types t WHERE t.is_enabled=true
   UNION SELECT DISTINCT v.document_type,v.document_type FROM docutracker_routing_config_versions v
   WHERE NOT EXISTS(SELECT 1 FROM docutracker_document_types t WHERE t.document_type=v.document_type)
   ORDER BY document_type`)).rows.filter(r=>!['dtr','ld','rsp'].includes(r.document_type)));}
 catch(error){res.status(500).json({error:'Could not load document types.'});}
});
router.get('/document-links',async(req,res)=>{
 try {res.json((await pool.query('SELECT * FROM approval_workflow_document_types ORDER BY document_type')).rows);}
 catch(error){res.status(500).json({error:'Could not load shared document workflows.'});}
});
router.post('/:id/document-types/:documentType',async(req,res)=>{
 if(req.user.role!=='admin')return res.status(403).json({error:'DocuTracker administrator access required.'});
 let client;
 try {
  client=await pool.connect();
  await client.query('BEGIN');
  const workflow=(await client.query(`SELECT w.*,v.version,v.steps FROM approval_workflows w
    JOIN approval_workflow_versions v ON v.workflow_id=w.id AND v.version=w.current_version WHERE w.id=$1::uuid FOR UPDATE OF w`,[req.params.id])).rows[0];
  if(!workflow)throw Object.assign(new Error('Workflow not found.'),{statusCode:404});
  if(['dtr','ld','rsp'].includes(req.params.documentType))throw Object.assign(new Error('Source modules keep their own filing rules.'),{statusCode:400});
  await client.query(`INSERT INTO docutracker_document_types(document_type,display_name)
    SELECT $1,$1 WHERE EXISTS(SELECT 1 FROM docutracker_routing_config_versions WHERE document_type=$1)
    ON CONFLICT(document_type) DO NOTHING`,[req.params.documentType]);
  const type=(await client.query('SELECT document_type FROM docutracker_document_types WHERE document_type=$1 AND is_enabled=true',[req.params.documentType])).rows[0];
  if(!type)throw Object.assign(new Error('Active document type not found.'),{statusCode:404});
  const version=await require('../services/sharedDocumentWorkflows').publishDocumentVersion(client,type.document_type,workflow,req.user.id);
  await client.query('COMMIT');res.json({document_type:type.document_type,version,workflow_id:workflow.id});
 }catch(error){if(client)await client.query('ROLLBACK');res.status(error.statusCode||500).json({error:error.statusCode?error.message:'Could not link document workflow.'});}
 finally{client?.release();}
});
async function write(req,res) {
  let client;
  try {
    const input=normalizeWorkflow(req.body);
    // Keep the nullable legacy column for history; filing rules belong to types.
    const employmentTypes=null;
    client=await pool.connect();
    await client.query('BEGIN');
    await require('../services/approvalWorkflows').assertActiveSelectedReviewers(client,input.steps);
    let workflow;
    if(req.params.id) {
      const previous=(await client.query('SELECT * FROM approval_workflows WHERE id=$1::uuid FOR UPDATE',[req.params.id])).rows[0];
      if(!previous) throw Object.assign(new Error('Workflow not found.'),{statusCode:404});
      if(Number(req.body.current_version)!==previous.current_version) throw Object.assign(new Error('This workflow changed. Reload before publishing.'),{statusCode:409});
      workflow=(await client.query(`UPDATE approval_workflows SET name=$2,is_active=$3,current_version=current_version+1,updated_at=now()
        WHERE id=$1::uuid RETURNING *`,[req.params.id,input.name,input.is_active])).rows[0];
    } else workflow=(await client.query('INSERT INTO approval_workflows(name,is_active) VALUES($1,$2) RETURNING *',[input.name,input.is_active])).rows[0];
    await client.query(`INSERT INTO approval_workflow_versions(workflow_id,version,steps,employment_types,created_by,self_filing_signatory_policy)
      VALUES($1::uuid,$2,$3::jsonb,$4::text[],$5::uuid,$6)`,[workflow.id,workflow.current_version,JSON.stringify(input.steps),employmentTypes,req.user.id,input.self_filing_signatory_policy]);
    await require('../services/sharedDocumentWorkflows').syncLinkedDocumentWorkflows(client,
      {...workflow,version:workflow.current_version,steps:input.steps,employment_types:employmentTypes},req.user.id);
    await client.query('COMMIT');
    res.status(req.params.id?200:201).json({...workflow,steps:input.steps,employment_types:employmentTypes,self_filing_signatory_policy:input.self_filing_signatory_policy});
  } catch(error) {
    if(client) await client.query('ROLLBACK');
    res.status(error.code==='23505'?409:error.statusCode||500).json({error:error.code==='23505'?'A workflow with that name already exists.':error.statusCode?error.message:'Could not publish workflow.'});
  } finally { client?.release(); }
}
router.post('/',write);
router.put('/:id',write);
module.exports=router;
