const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
test('manual Mayor route finishes at department approval and does not notify HR',async()=>{
 const id='11111111-1111-4111-8111-111111111111';
 const row={id,status:'pending_department_head',employee_id:'22222222-2222-4222-8222-222222222222',
   slip_date:'2026-10-13',request_type:'locator',am_in:true,final_review_route:'mayor'};
 const writes=[];let hrNotifications=0;
 const query=async(sql,params=[])=>{
   if(sql.includes('FOR UPDATE OF ls'))return {rows:[row]};
   if(sql.startsWith('SELECT final_review_route'))return {rows:[{final_review_route:'mayor'}]};
   if(sql.includes('UPDATE locator_slips')&&sql.includes('dept_head_reviewer_id'))writes.push(params);
   if(sql.includes('FROM locator_slips ls')&&sql.includes('ls.*'))return {rows:[{...row,status:'approved'}]};
   return {rows:[]};
 };
 const signatures=require('../src/services/locatorSignatureService');
 const departments=require('../src/services/departmentHeadService');
 const notifications=require('../src/services/locatorNotifications');
 const conflicts=require('../src/services/locatorConflictPolicy');
 const restores=[
   withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}}),
   withMockedModule('../src/services/locatorSignatureService',{...signatures,persistLocatorSignature:async()=>{}}),
   withMockedModule('../src/services/departmentHeadService',{...departments,isDepartmentHead:async()=>({departmentId:id,isDeptHead:true})}),
   withMockedModule('../src/services/locatorNotifications',{...notifications,notifyEmployee:async()=>{},notifyDepartmentHeadApprovedForHr:async()=>{hrNotifications++;}}),
   withMockedModule('../src/services/locatorConflictPolicy',{...conflicts,findLocatorRequestConflicts:async()=>({ok:true})}),
 ];
 clearModule('../src/routes/locatorSlips');
 try {
   const router=require('../src/routes/locatorSlips');
   const handler=router.stack.find(e=>e.route?.path==='/:id/department-head-approve').route.stack.at(-1).handle;
   const res={statusCode:200,status(n){this.statusCode=n;return this;},json(body){this.body=body;return this;}};
   await handler({params:{id},user:{id:'33333333-3333-4333-8333-333333333333',role:'employee'},body:{}},res);
   assert.equal(res.statusCode,200);
   assert.equal(res.body.status,'approved');
   assert.equal(writes[0][3],'approved');
   assert.equal(hrNotifications,0);
 } finally {
   clearModule('../src/routes/locatorSlips');restores.reverse().forEach(r=>r());
 }
});
