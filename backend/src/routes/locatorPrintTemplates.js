const express=require('express');const multer=require('multer');
const {withHeavyWork}=require('../middleware/heavyWork');
const {pool}=require('../config/db');
const {requireAdminOrHr}=require('../middleware/rbac');
const {requireDtrFeatureIfAdmin}=require('../middleware/dtrAccess');
const {validateLocatorBackground,mergeLocatorBackground}=require('../services/locatorPrintTemplates');
const {normalizeLocatorPrintLayout}=require('../services/locatorPrintLayout');
const {PDFDocument}=require('pdf-lib');
const {resolveActiveMayor}=require('../services/officialSignatoryService');
const {todayInHrmsTimezone}=require('../utils/dateRangeParser');
const router=express.Router();
const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:5242880,files:1}});
function file(req,res,next){upload.single('file')(req,res,e=>e?res.status(400).json({error:'Use one file up to 5 MB'}):next());}
const draftUpload=multer({storage:multer.memoryStorage(),limits:{fileSize:5242880,files:2}});
function draftFiles(req,res,next){draftUpload.fields([{name:'file',maxCount:1},{name:'background',maxCount:1}])(req,res,e=>e?res.status(400).json({error:'Use a PDF preview and one background, each up to 5 MB'}):next());}
const manage=[requireAdminOrHr,requireDtrFeatureIfAdmin('locator_allowed')];
function metadata(v){return {id:v?.id||null,background_name:v?.background_name||null,has_background:!!v?.background_pdf,print_layout:v?.print_layout||null};}
function failure(res,e){return res.status(e.status||500).json({error:e.status?e.message:'Could not load or save locator printed form'});}
async function typeVersion(db,id,lock=false){
 const q=await db.query(`SELECT t.id AS locator_type_id,v.* FROM locator_request_types t
 LEFT JOIN locator_print_template_versions v ON v.id=t.print_template_version_id
 WHERE t.id=$1::uuid ${lock?'FOR UPDATE OF t':''}`,[id]);
 if(!q.rows[0])throw Object.assign(new Error('Locator type not found'),{status:404});return q.rows[0];
}
async function requestVersion(db,id,user){
 if(user.role==='mayor') {
   const mayor=await resolveActiveMayor(db,todayInHrmsTimezone());
   if(!mayor || String(mayor.employee_id)!==String(user.id))throw Object.assign(new Error('Only the active Mayor can access these forms'),{status:404});
 }
 const q=await db.query(`SELECT ls.print_template_version_id AS version_id,v.background_pdf,v.print_layout
 FROM locator_slips ls LEFT JOIN locator_print_template_versions v ON v.id=ls.print_template_version_id
 WHERE ls.id=$1::uuid AND (ls.employee_id=$2::uuid OR $3='hr'
 OR ($3='admin' AND EXISTS(SELECT 1 FROM dtr_admin_access p WHERE p.admin_user_id=$2::uuid AND p.locator_allowed=true))
 OR ($3='mayor' AND ls.final_review_route='mayor_direct')
 OR ls.assigned_department_head_id=$2::uuid OR ls.dept_head_reviewer_id=$2::uuid
 OR EXISTS(SELECT 1 FROM locator_slip_department_reviewers r WHERE r.locator_slip_id=ls.id AND r.reviewer_id=$2::uuid))`,[id,user.id,user.role]);
 if(!q.rows[0])throw Object.assign(new Error('Locator request not found or access denied'),{status:404});return q.rows[0];
}
router.get('/types/:id',...manage,async(req,res)=>{
 try{res.json(metadata(await typeVersion(pool,req.params.id)));}catch(e){failure(res,e);}
});
router.get('/types/:id/background',...manage,async(req,res)=>{
 try{
  const current=await typeVersion(pool,req.params.id);
  if(!current.background_pdf)return res.status(404).json({error:'No background uploaded'});
  res.set('Content-Type','application/pdf').set('Cache-Control','no-store').send(current.background_pdf);
 }catch(e){failure(res,e);}
});
async function checkOrientation(background,layout){
 if(!background||!layout)return;
 const doc=await PDFDocument.load(background);const {width,height}=doc.getPage(0).getSize();
 if((width>height)!==(layout.orientation==='landscape'))throw Object.assign(new Error('Choose the same page orientation as the background'),{status:400});
}
router.post('/types/:id',...manage,file,async(req,res)=>{
 let client;
 try{
  const uploaded=req.file?await validateLocatorBackground(req.file.buffer,req.file.mimetype):null;
  client=await pool.connect();await client.query('BEGIN');
  const current=await typeVersion(client,req.params.id,true);
  const remove=req.body.remove_background==='true';
  const layout=normalizeLocatorPrintLayout(req.body.print_layout===undefined?current.print_layout:req.body.print_layout);
  const background=remove?null:uploaded||current.background_pdf||null;
  await checkOrientation(background,layout);
  const q=await client.query(`INSERT INTO locator_print_template_versions(locator_type_id,background_pdf,background_name,created_by,print_layout)
   VALUES($1,$2,$3,$4,$5::jsonb) RETURNING *`,[req.params.id,background,
    remove?null:req.file?req.file.originalname:current.background_name||null,req.user.id,layout?JSON.stringify(layout):null]);
  await client.query('UPDATE locator_request_types SET print_template_version_id=$1,updated_at=now() WHERE id=$2',[q.rows[0].id,req.params.id]);
  await client.query('COMMIT');res.json(metadata(q.rows[0]));
 }catch(e){if(client)await client.query('ROLLBACK');failure(res,e);}finally{client?.release();}
});
router.post('/requests/:id/render',file,withHeavyWork(async(req,res)=>{
 try{
  const row=await requestVersion(pool,req.params.id,req.user);
  if(!req.file)throw Object.assign(new Error('Generated PDF required'),{status:400});
  if((req.body.version_id||null)!==(row.version_id||null))throw Object.assign(new Error('Printed form settings changed. Please retry.'),{status:409});
  const bytes=await mergeLocatorBackground(row.background_pdf,req.file.buffer,row.print_layout);
  res.set('Content-Type','application/pdf').set('Cache-Control','no-store').send(bytes);
 }catch(e){failure(res,e);}
}));
router.post('/types/:id/preview',...manage,file,withHeavyWork(async(req,res)=>{
 try{
  const version=await typeVersion(pool,req.params.id);
  if(!req.file)throw Object.assign(new Error('Generated PDF required'),{status:400});
  const bytes=await mergeLocatorBackground(version.background_pdf,req.file.buffer,version.print_layout);
  res.set('Content-Type','application/pdf').set('Cache-Control','no-store').send(bytes);
 }catch(e){failure(res,e);}
}));
// Preview unsaved settings, including new types, without appending a version.
router.post('/preview',...manage,draftFiles,withHeavyWork(async(req,res)=>{
 try{
  const current=req.body.type_id?await typeVersion(pool,req.body.type_id):null;
  const layout=normalizeLocatorPrintLayout(req.body.print_layout===undefined?current?.print_layout:req.body.print_layout);
  const overlay=req.files?.file?.[0];if(!overlay)throw Object.assign(new Error('Generated PDF required'),{status:400});
  const uploaded=req.files?.background?.[0];
  const background=req.body.remove_background==='true'?null:uploaded?await validateLocatorBackground(uploaded.buffer,uploaded.mimetype):current?.background_pdf||null;
  const bytes=await mergeLocatorBackground(background,overlay.buffer,layout);
  res.set('Content-Type','application/pdf').set('Cache-Control','no-store').send(bytes);
 }catch(e){failure(res,e);}
}));
module.exports=router;
