'use strict';
module.exports=function createPaperControllers(runtime){
 return {
  paperSignatorySuggestions:async(req,res)=>{
   try{return res.json(await runtime.suggestLocatorPaperSignatories(runtime.pool,{
    employeeId:req.query.employee_id,requestType:req.query.request_type,filingDate:req.query.filing_date,approvalDate:req.query.approval_date,
   }));}catch(error){return res.status(error.statusCode||500).json({error:error.statusCode?error.message:'Unable to load paper signatory suggestions. Retry or use Other signatory.'});}
  },
  recordApprovedPaper:async(req,res)=>{
   const attachment=req.file?{path:`${runtime.LOCATOR_ATTACHMENT_SUBDIR}/${req.file.filename}`,name:req.file.originalname,mimeType:req.file.mimetype}:null;
   let committed=false;
   try{
    const row=await runtime.recordPaperLocator({actor:req.user,employeeId:req.body.employee_id,
     slipDate:req.body.slip_date,requestType:runtime.normalizeRequestType(req.body.request_type),office:String(req.body.office||''),reason:String(req.body.reason||''),
     slots:{amIn:runtime.boolField(req.body.am_in),amOut:runtime.boolField(req.body.am_out),pmIn:runtime.boolField(req.body.pm_in),pmOut:runtime.boolField(req.body.pm_out)},
     fullShift:runtime.boolField(req.body.full_shift),attachment,paperApproval:req.body.paper_approval,additionalDetails:req.body.additional_details});
    committed=true;
    let mapped=runtime.mapLocatorRow({...row,slip_date_text:req.body.slip_date});
    try{mapped=await runtime.fetchLocatorSlipDetails(runtime.pool,row.id)||mapped;}catch(_){}
    runtime.notifySafe(()=>runtime.locatorNotifications.notifyEmployee(runtime.pool,{employeeUserId:row.employee_id,slipId:row.id,type:'locator_approved_hr',title:'Approved paper locator recorded',body:'HR recorded your already-approved paper locator. No further approval is required.'}));
    runtime.broadcastLocatorUpdated('paper_approved_recorded',mapped,{dateFrom:req.body.slip_date,dateTo:req.body.slip_date,reconciliationRequired:row.month_end_reconciliation_required===true});
    return res.status(201).json(mapped);
   }catch(error){
    if(!committed&&attachment)runtime.removeLocatorAttachmentFile(attachment.path);
    if(!error.statusCode)console.error('[locator approved paper recording]',error);
    return res.status(error.statusCode||500).json({error:error.statusCode?error.message:'Unable to record approved paper locator.'});
   }
  },
 };
};
