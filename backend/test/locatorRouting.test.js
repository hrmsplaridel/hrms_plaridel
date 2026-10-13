const test=require('node:test');
const assert=require('node:assert/strict');
const {normalizeLocatorRouting,chooseLocatorRoute,resolveLocatorRouting,locatorFinalReviewers}=require('../src/services/locatorRouting');
const {assertFinalLeaveReviewer}=require('../src/services/leaveFinalReviewerService');
test('direct Mayor decisions reject HR and self approval',async()=>{
 const db={query:async(sql)=>({rows:sql.includes('department_approver_id')?[{}]:sql.includes('final_review_route')?[{final_review_route:'mayor_direct'}]:[{employee_id:'mayor',name:'Mayor'}]})};
 await assertFinalLeaveReviewer(db,'employee','mayor','locator','request');
 await assert.rejects(assertFinalLeaveReviewer(db,'employee','hr','locator','request'),/assigned/);
 await assert.rejects(assertFinalLeaveReviewer(db,'mayor','mayor','locator','request'),/own/);
});
test('locator routing defaults preserve HR and invalid or auto-approved Mayor routes are rejected',()=>{
 assert.equal(normalizeLocatorRouting({}).approval_route,'hr');
 assert.throws(()=>normalizeLocatorRouting({approval_route:'unknown'}),/Invalid/);
 assert.throws(()=>normalizeLocatorRouting({approval_route:'mayor_direct',auto_approve_admin:true}),/auto/);
 assert.equal(chooseLocatorRoute({approval_route:'mayor_direct',mayor_employment_types:['job_order']},'permanent'),'hr');
 assert.equal(chooseLocatorRoute({approval_route:'mayor_direct',mayor_employment_types:['job_order']},'job_order'),'mayor_direct');
});
test('direct Mayor skips department, manual signing requires department, absent/self Mayor blocks submission',async()=>{
 const db={query:async(sql)=>({rows:sql.includes('SELECT employment_type')?[{employment_type:'job_order'}]:[{employee_id:'mayor',name:'Mayor'}]})};
 assert.deepEqual(await resolveLocatorRouting(db,'employee',{approval_route:'mayor_direct'},null),{route:'mayor_direct',mayorId:'mayor',status:'pending_mayor'});
 await assert.rejects(resolveLocatorRouting(db,'employee',{approval_route:'mayor'},null),/department/);
 await assert.rejects(resolveLocatorRouting(db,'mayor',{approval_route:'mayor_direct'},null),/eligible/);
 await assert.rejects(resolveLocatorRouting({query:async()=>({rows:[]})},'employee',{approval_route:'mayor_direct'},null),/eligible/);
});
test('only the active Mayor receives a direct request; manual signing has no HR final reviewer',async()=>{
 const db={query:async(sql)=>({rows:sql.includes('final_review_route')?[{final_review_route:'mayor_direct'}]:[{employee_id:'mayor'}]})};
 assert.deepEqual(await locatorFinalReviewers(db,'request',()=>{throw Error('HR must not be used');}),[{id:'mayor',name:undefined}]);
 const manual={query:async()=>({rows:[{final_review_route:'mayor'}]})};
 assert.deepEqual(await locatorFinalReviewers(manual,'request',()=>{throw Error('HR must not be used');}),[]);
});
