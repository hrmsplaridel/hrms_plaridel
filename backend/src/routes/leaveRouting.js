const express=require('express');const {pool}=require('../config/db');
const {requireAdminOrHr}=require('../middleware/rbac');const {requireDtrFeatureIfAdmin}=require('../middleware/dtrAccess');
const {normalizeRouting}=require('../services/leaveRouting');const router=express.Router();
router.use(requireAdminOrHr,requireDtrFeatureIfAdmin('leave_allowed'));
router.get('/types/:id',async(req,res)=>{
 try{const r=await pool.query('SELECT approval_route,mayor_employment_types,approval_workflow_id FROM leave_types WHERE id=$1::uuid',[req.params.id]);
 if(!r.rows[0])return res.status(404).json({error:'Leave type not found'});res.json(r.rows[0]);
 }catch(e){res.status(500).json({error:'Could not load approval routing'});}
});
router.post('/types/:id',async(req,res)=>{
 try{
 const body=req.body||{};
 // Default HR is for creation, not an incomplete update of saved routing.
 if(!body.approval_workflow_id && (!Object.hasOwn(body,'approval_route') || !body.approval_route)) {
  return res.status(400).json({error:'Select an approval route before saving.'});
 }
 const workflowId=await require('../services/approvalWorkflows').selectedWorkflowId(pool,body.approval_workflow_id);
 const r=normalizeRouting(body);
 const q=await pool.query(`UPDATE leave_types SET approval_route=$1,mayor_employment_types=$2::text[],approval_workflow_id=$4::uuid,updated_at=now()
 WHERE id=$3::uuid RETURNING approval_route,mayor_employment_types,approval_workflow_id`,[r.approval_route,r.mayor_employment_types,req.params.id,workflowId]);
 if(!q.rows[0])return res.status(404).json({error:'Leave type not found'});res.json(q.rows[0]);
 }catch(e){res.status(e.statusCode||500).json({error:e.statusCode?e.message:'Could not save approval routing'});}
});module.exports=router;
