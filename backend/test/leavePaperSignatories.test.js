const test=require('node:test'),assert=require('node:assert/strict');
test('paper signatory endpoint returns original named officials without resolving current assignments',async()=>{
 const paper={final_approver:{name:'Original Mayor',position_title:'Mayor'},certification_officer:null,department_reviewer:{name:'Former Head',position_title:'Department Head'}};
 const handler=require('../src/modules/leave/controllers/signatories.controller')({pool:{query:async()=>({rows:[{id:'record',employee_id:'employee',status:'approved',paper_approval_record:paper}]})},workflowEngine:{isShared:()=>false},getEmployeeDepartment:async()=>{throw Error('Do not substitute current officials');}}).getSignatories;
 const res={status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
 await handler({user:{id:'encoder',role:'hr'},query:{employee_id:'employee',leave_request_id:'record'}},res);
 assert.equal(res.body.approving_authority.name,'Original Mayor');assert.equal(res.body.recommendation_officer.name,'Former Head');assert.equal(res.body.hr_certification_officer,null);
});

test('paper form signatures are served only after the existing request access check',async()=>{
 const handler=require('../src/modules/leave/controllers/signatories.controller')({pool:{query:async()=>({rows:[{id:'record',employee_id:'employee',status:'approved',paper_approval_record:{final_approver:{name:'Mayor'}}}]})},workflowEngine:{isShared:()=>false}}).getSignatories;
 const res={status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
 await handler({user:{id:'stranger',role:'employee'},query:{employee_id:'employee',leave_request_id:'record'}},res);
 assert.equal(res.code,403);
});
