'use strict';
const {validateStaffBatch,runStaffBatch}=require('../../../services/locatorStaffFiling');
module.exports = function createStaffControllers(runtime, submissions) {
  const {pool}=runtime;
  const {suggestPaperSignatories}=require('../services/paperSignatories')(runtime);
  function authorized(req,res) {
    if (req.user?.id && ['admin','hr'].includes(req.user.role)) return true;
    res.status(403).json({error:'Authorized HR staff access is required.'});return false;
  }
  return {
    paperSignatorySuggestions:async(req,res)=>{
      if (!authorized(req,res)) return;
      try {
        const data=await suggestPaperSignatories(pool,{
          employeeId:req.query?.employee_id,leaveType:req.query?.leave_type,
          filingDate:req.query?.filing_date,approvalDate:req.query?.approval_date,
        });
        return res.json(data);
      } catch(error) {
        if(!error.statusCode)console.error('[leave paper signatory suggestions]',error);
        return res.status(error.statusCode||500).json({error:error.statusCode?error.message:'Unable to load signatory suggestions. Use Other signatory or retry.'});
      }
    },
    listFilingEmployees:async(req,res)=>{
      if (!authorized(req,res)) return;
      try {
        const search=String(req.query.search || '').trim().slice(0,100);
        const offset=Math.max(0,parseInt(req.query.offset,10)||0);
        const rows=await pool.query(`SELECT u.id,u.full_name,u.email,u.sex,u.employment_type,
          u.date_hired,u.employment_status,count(*) OVER()::int AS total
          FROM users u WHERE u.id<>$1::uuid AND u.is_active=true
          AND COALESCE(u.employment_status,'active')='active'
          AND ($2::text='' OR u.full_name ILIKE '%' || $2 || '%' OR u.employee_number::text ILIKE '%' || $2 || '%')
          ORDER BY u.full_name,u.id LIMIT 100 OFFSET $3`,[req.user.id,search,offset]);
        res.json({employees:rows.rows,total:rows.rows[0]?.total || 0});
      } catch(error) { console.error('[leave staff employees]',error);res.status(500).json({error:'Unable to load employees.'}); }
    },
    staffSubmissionAvailability:async(req,res)=>{
      if (!authorized(req,res)) return;
      return res.status(409).json({error:'Use Record approved paper leave with the signed document and original approval details.'});
    },
    fileForEmployees:async(req,res)=>{
      if (!authorized(req,res)) return;
      try {
        let ids=req.body?.employee_ids;
        if(typeof ids==='string'){try{ids=JSON.parse(ids);}catch(_){ids=null;}}
        ids=[...new Set(validateStaffBatch(ids).map(id=>id.toLowerCase()))];
        if(ids.length!==1)return res.status(400).json({error:'Record one employee’s approved paper form at a time.'});
        if(!req.file)return res.status(400).json({error:'Upload the approved signed paper form and required supporting documents.'});
        if(req.body?.signature)return res.status(400).json({error:'Paper recording uses the signed original; do not submit digital approval signatures.'});
        if(ids.includes(req.user.id.toLowerCase()))return res.status(400).json({error:'Use My Leave to file your own leave.'});
        if(req.body?.applicant_signature_asset_id)return res.status(400).json({error:'Staff filing cannot apply an applicant signature.'});
        const results=await runStaffBatch(ids,async employeeId=>{
          let output;let code=200;
          const response={status(value){code=value;return this;},json(value){output=value;return this;}};
          await submissions.submitWithAttachment(req,response,employeeId);
          if(code>=400)throw Object.assign(new Error(output?.error || 'Unable to file leave.'),{statusCode:code,payload:output});
          if(!output?.id)throw new Error('Submission did not return a request.');
          return output;
        });
        res.json({results,created:results.filter(r=>r.request).length,failed:results.filter(r=>r.error).length});
      } catch(error) {res.status(error.statusCode || 500).json({error:error.statusCode?error.message:'Unable to file leave requests.'});}
    },
  };
};
