const {normalizeLocatorPrintLayout}=require('./locatorPrintLayout');
const FIELDS=new Set(['employee_name','employee_first_name','employee_middle_name','employee_last_name','date','request_type','office','reason','position','salary','start_date','end_date','inclusive_dates','working_days','location_option','location_details','sick_leave_nature','sick_illness_details','maternity_delivery_type','expected_delivery_date','child_delivery_date','accident_date','calamity_date','adoption_parent_role','adoption_placement_date','vawc_support_document_type','vawc_case_details','solo_parent_id_number','solo_parent_id_expiry_date','women_illness_details','study_purpose','study_purpose_details','other_purpose','other_purpose_details','commutation','approved_days_with_pay','approved_days_without_pay','approved_other_details','recommendation_remarks','disapproval_reason','hr_remarks']);
const SIGNATURES=new Set(['applicant','department_head','hr_approver','certification_officer']);
function normalizeLeavePrintLayout(value){
 const result=normalizeLocatorPrintLayout(value,{fields:FIELDS,signatures:SIGNATURES});if(!result)return result;
 const raw=typeof value==='string'?JSON.parse(value):value;
 const invalid=message=>{throw Object.assign(new Error(message),{status:400});};
 if(raw.base_form!==undefined){if(!['csc','wellness'].includes(raw.base_form))invalid('Invalid original form');result.base_form=raw.base_form;}
 if(raw.base_form_box!==undefined){
  const b=raw.base_form_box;const [w,h]=require('./printLayoutPageSettings').printLayoutPageSize(result);
  if(!result.base_form||!b||['x','y','width','height'].some(k=>typeof b[k]!=='number'||!Number.isFinite(b[k]))||b.x<0||b.y<0||b.width<20||b.height<20||b.x+b.width>w+.1||b.y+b.height>h+.1)invalid('Original form must fit on the page');
  result.base_form_box={x:b.x,y:b.y,width:b.width,height:b.height};
 }
 if(Buffer.byteLength(JSON.stringify(result,null,1),'utf8')>100000)invalid('Printed layout must fit within 100 KB');
 return result;
}
module.exports={normalizeLeavePrintLayout};
