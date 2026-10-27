'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const create=require('../src/modules/leave/use-cases/staffFiling');
test('paper recording freezes original approval data and actual encoder before accounting',async()=>{
 const calls=[];const actor={id:'encoder',role:'hr'};const record={source:'approved_paper',approval_date:'2026-09-02',encoded_by:actor.id};
 const db={query:async(sql,params)=>{calls.push({sql,params});return {rows:sql.includes('FROM users')?[{full_name:'HR Encoder'}]:[{paper_approval_record:{...JSON.parse(params[1]),encoded_at:'2026-10-26T01:00:00Z'}}]};}};
 const service=create({finalizeLeaveApproval:async(db,row,options)=>{calls.push({row,options});return {row:{...row,status:'approved'}};}});
 const result=await service.completeStaffLeave(db,{actor,row:{id:'record',number_of_days:1},paperRecord:record,leaveTypeName:'sickLeave',approvedDaysWithPay:1,approvedDaysWithoutPay:0});
 assert.equal(result.status,'approved');assert.equal(calls.find(c=>c.options).options.paperRecord.encoded_by_name,'HR Encoder');
 assert.equal(calls.find(c=>c.options).options.paperRecord.approval_date,'2026-09-02');
 assert.equal(calls.some(c=>c.sql?.includes('signature')),false);
});
