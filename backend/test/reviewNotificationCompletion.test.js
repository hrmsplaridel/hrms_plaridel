const test=require('node:test');const assert=require('node:assert/strict');
test('completing a department stage marks only that stage for all recipients',async()=>{
 const {completeReviewNotifications}=require('../src/services/reviewNotificationCompletion');let captured;
 await completeReviewNotifications({async query(sql,p){captured={sql,p};return {rows:[]};}},'leave_request','request','pending_department_head','pending_hr');
 assert.deepEqual(captured.p,['leave_request','request',['leave_pending_department_head']]);
 assert.match(captured.sql,/read_at IS NULL/);assert.doesNotMatch(captured.sql,/user_id\s*=/);
});
test('terminal decisions close every review stage but never applicant notices',async()=>{
 const {completeReviewNotifications}=require('../src/services/reviewNotificationCompletion');let types;
 await completeReviewNotifications({async query(sql,p){types=p[2];return {rows:[]};}},'locator_slip','request','pending_hr','approved');
 assert.ok(types.includes('locator_pending_department_head'));assert.ok(types.includes('locator_forwarded_to_hr'));
 assert.ok(!types.includes('locator_approved'));
});
test('unchanged statuses and submission do not clear newly active review alerts',async()=>{
 const {completeReviewNotifications}=require('../src/services/reviewNotificationCompletion');let count=0;
 const db={async query(){count++;}};
 await completeReviewNotifications(db,'leave_request','request','pending_hr','pending_hr');
 await completeReviewNotifications(db,'leave_request','request','draft','pending_department_head');
 assert.equal(count,0);
});
