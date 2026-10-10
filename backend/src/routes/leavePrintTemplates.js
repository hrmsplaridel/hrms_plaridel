const express=require('express');
const multer=require('multer');
const {pool}=require('../config/db');
const {requireAdminOrHr}=require('../middleware/rbac');
const {requireDtrFeatureIfAdmin}=require('../middleware/dtrAccess');
const {validateLayout,validateBackground,mergeBackground}=require('../services/leavePrintTemplates');
const {resolveActiveMayor}=require('../services/officialSignatoryService');
const {todayInHrmsTimezone}=require('../utils/dateRangeParser');
const router=express.Router();
const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:5242880,files:1}});
function file(req,res,next){upload.single('file')(req,res,e=>e?res.status(400).json({error:'Use one file up to 5 MB'}):next());}
const manage=[requireAdminOrHr,requireDtrFeatureIfAdmin('leave_allowed')];
function metadata(v){return {id:v?.id||null,layout:v?.layout||'csc',background_name:v?.background_name||null,has_background:!!v?.background_pdf,created_at:v?.created_at||null};}
function failure(res,e){return res.status(e.status||500).json({error:e.status?e.message:'Could not load or save printed form'});}
async function typeVersion(db,id,lock=false){
 const q=await db.query(`SELECT lt.id AS leave_type_id,v.* FROM leave_types lt
 LEFT JOIN leave_print_template_versions v ON v.id=lt.print_template_version_id
 WHERE lt.id=$1::uuid ${lock?'FOR UPDATE OF lt':''}`,[id]);
 if(!q.rows[0])throw Object.assign(new Error('Leave type not found'),{status:404});return q.rows[0];
}
async function requestVersion(db,id,user){
 const q=await db.query(`SELECT lr.*,v.id AS version_id,v.layout,v.background_pdf,v.background_name,
 COALESCE(lr.routing_employment_type,NULLIF(lr.employee_official_snapshot->>'employment_type',''),employee.employment_type) AS employment_type,
 COALESCE(lr.employee_official_snapshot->>'department_name',lr.employee_official_snapshot->'department'->>'name','') AS department_name
 FROM leave_requests lr JOIN leave_types lt ON lt.id=lr.leave_type_id
 JOIN users employee ON employee.id=COALESCE(lr.employee_id,lr.user_id)
 LEFT JOIN leave_print_template_versions v ON v.id=CASE WHEN lr.status='draft'
 THEN lt.print_template_version_id ELSE lr.print_template_version_id END
 WHERE lr.id=$1::uuid AND (
 COALESCE(lr.employee_id,lr.user_id)=$2::uuid OR $3='hr'
 OR ($3='mayor' AND lr.final_reviewer_user_id=$2::uuid)
 OR ($3='admin' AND EXISTS(SELECT 1 FROM dtr_admin_access p WHERE p.admin_user_id=$2::uuid AND p.leave_allowed=true))
 OR EXISTS(SELECT 1 FROM leave_request_department_reviewers r WHERE r.leave_request_id=lr.id AND r.reviewer_id=$2::uuid)
 OR EXISTS(SELECT 1 FROM leave_request_history h WHERE h.leave_request_id=lr.id AND h.acted_by=$2::uuid
 AND h.action IN ('department_head_approved','department_head_rejected','department_head_returned')))
 `,[id,user.id,user.role]);
 if(!q.rows[0])throw Object.assign(new Error('Leave request not found or access denied'),{status:404});
 const row=q.rows[0];
 // The JO/COS-specific Wellness form must never label other employees JO/COS.
 if(row.layout==='wellness' && !['job_order','contract_of_service'].includes(row.employment_type)) {
  return {...row,layout:'csc',background_pdf:null,background_name:null};
 }
 return row;
}
router.get('/types/:id',...manage,async(req,res)=>{
 try{res.json(metadata(await typeVersion(pool,req.params.id)));}catch(e){failure(res,e);}
});
router.post('/types/:id',...manage,file,async(req,res)=>{
 let client;
 try{
  const layout=validateLayout(req.body.layout);
  const uploaded=req.file?await validateBackground(req.file.buffer,req.file.mimetype):null;
  client=await pool.connect();await client.query('BEGIN');
  const current=await typeVersion(client,req.params.id,true);
  const remove=req.body.remove_background==='true';
  const q=await client.query(`INSERT INTO leave_print_template_versions(leave_type_id,layout,background_pdf,background_name,created_by)
   VALUES($1,$2,$3,$4,$5) RETURNING *`,[req.params.id,layout,remove?null:uploaded||current.background_pdf||null,
    remove?null:req.file?req.file.originalname:current.background_name||null,req.user.id]);
  await client.query('UPDATE leave_types SET print_template_version_id=$1,updated_at=now() WHERE id=$2',[q.rows[0].id,req.params.id]);
  await client.query('COMMIT');res.json(metadata(q.rows[0]));
 }catch(e){if(client)await client.query('ROLLBACK');failure(res,e);}finally{client?.release();}
});
router.get('/requests/:id',async(req,res)=>{
 try{const row=await requestVersion(pool,req.params.id,req.user);
  const mayor=await resolveActiveMayor(pool,todayInHrmsTimezone());
  res.json({...metadata({...row,id:row.version_id}),department_name:row.department_name,
   mayor_name:row.approving_authority_snapshot?.name||mayor?.name||'',mayor_title:mayor?.position_title||'Municipal Mayor'});
 }catch(e){failure(res,e);}
});
router.post('/requests/:id/render',file,async(req,res)=>{
 try{const row=await requestVersion(pool,req.params.id,req.user);
  if(!req.file)throw Object.assign(new Error('Generated PDF required'),{status:400});
  // A client must render the version it fetched, never silently mix versions.
  if((req.body.version_id||null)!==(row.version_id||null))throw Object.assign(new Error('Printed form settings changed. Please retry.'),{status:409});
  const bytes=await mergeBackground(row.background_pdf,req.file.buffer,{layout:row.layout});
  res.set('Content-Type','application/pdf').set('Cache-Control','no-store').send(bytes);
 }catch(e){failure(res,e);}
});
router.post('/types/:id/preview',...manage,file,async(req,res)=>{
 try{const version=await typeVersion(pool,req.params.id);
  if(!req.file)throw Object.assign(new Error('Generated PDF required'),{status:400});
  const bytes=await mergeBackground(version.background_pdf,req.file.buffer,{layout:version.layout});
  res.set('Content-Type','application/pdf').set('Cache-Control','no-store').send(bytes);
 }catch(e){failure(res,e);}
});
module.exports=router;
