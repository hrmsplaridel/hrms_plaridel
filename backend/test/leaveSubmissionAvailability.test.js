'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
test('a named direct-Mayor leave workflow remains fileable when no HR reviewer is assigned',async()=>{
  const restores=[
    withMockedModule('../src/services/departmentHeadService',{getDepartmentReviewSnapshot:async()=>({reviewers:[],reviewerUserIds:[]})}),
    withMockedModule('../src/services/officialSignatoryService',{resolveActiveMayor:async()=>({employee_id:'mayor',name:'Mayor'})}),
  ];
  const db={query:async(sql)=>{
    if(sql.includes('FROM leave_types'))return {rows:[{id:'type',name:'Travel',approval_workflow_id:'workflow',employee_can_file:true,is_active:true}]};
    if(sql.includes('FROM approval_workflows'))return {rows:[{id:'workflow',name:'Mayor only',is_active:true,version:1,steps:['mayor']}]};
    if(sql.includes('FROM users'))return {rows:[{employment_type:'regular'}]};
    throw Error('Unexpected query '+sql);
  }};
  clearModule('../src/services/leaveSubmissionAvailability');
  try{
    const {getLeaveSubmissionAvailability}=require('../src/services/leaveSubmissionAvailability');
    const result=await getLeaveSubmissionAvailability(db,'employee');
    assert.equal(result.can_submit,true);assert.equal(result.types[0].can_submit,true);
  }finally{clearModule('../src/services/leaveSubmissionAvailability');restores.reverse().forEach(r=>r());}
});
