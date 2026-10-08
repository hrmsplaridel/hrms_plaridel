const test=require('node:test');const assert=require('node:assert/strict');
test('notification list and unread badge hide locator review alerts for their applicant',async()=>{
 const service=require('../src/services/notificationService');
 const db={query:async(sql,args)=>{
  assert.match(sql,/locator_pending_hr/);assert.match(sql,/locator_forwarded_to_hr/);assert.match(sql,/locator_pending_department_head/);
  assert.match(sql,/ls.employee_id = user_notifications.user_id/);
  assert.match(sql,/ls.id = user_notifications.reference_id/);
  assert.equal(args[0],'applicant');return{rows:[]};
 }};
 await service.listNotifications(db,'applicant');await service.countUnread(db,'applicant');
});
