const test=require('node:test');
const assert=require('node:assert/strict');
const get=()=>require('../src/services/employeeAttendanceTracking');
const ID='11111111-1111-4111-8111-111111111111';
function db({existing=null,posted=false}={}) {
 const calls=[];
 return {calls,query:async(sql,params)=>{calls.push({sql,params});
  if(sql.includes('FROM users'))return {rows:[{id:ID,date_hired:'2025-01-01',attendance_tracking_start_date:existing}]};
  if(sql.includes('FROM leave_attendance_deductions'))return {rows:posted?[{id:'posting'}]:[]};
  return {rows:[]};
 }};
}
test('tracking date is saved with an audit and without altering assignments or hire dates',async()=>{
 const client=db();
 const result=await get().updateEmployeeTrackingStart(client,{employeeId:ID,value:'2026-11-01',actorId:ID,assignmentId:ID});
 assert.equal(result.date,'2026-11-01');
 assert.ok(client.calls.some(c=>c.sql.includes('INSERT INTO audit_logs')));
 assert.equal(client.calls.some(c=>/UPDATE assignments|SET date_hired/.test(c.sql)),false);
});
test('omitting tracking start during a transfer preserves the employee setting',async()=>{
 const client=db({existing:'2026-11-01'});
 const result=await get().updateEmployeeTrackingStart(client,{employeeId:ID,value:undefined});
 assert.equal(result.changed,false);assert.equal(client.calls.length,0);
});
test('unchanged tracking start does not reset or audit the date',async()=>{
 const client=db({existing:'2026-11-01'});
 const result=await get().updateEmployeeTrackingStart(client,{employeeId:ID,value:'2026-11-01'});
 assert.equal(result.changed,false);assert.equal(client.calls.some(c=>c.sql.startsWith('UPDATE')),false);
});
for(const value of ['2026-02-30','2024-12-31','yesterday','2026-11-01T00:00:00Z'])test(`invalid tracking start rejected: ${value}`,async()=>{
 const client=db();await assert.rejects(get().updateEmployeeTrackingStart(client,{employeeId:ID,value}),e=>e.statusCode===400);
 assert.equal(client.calls.some(c=>c.sql.startsWith('UPDATE')),false);
});
test('a tracking change cannot rewrite processed attendance periods',async()=>{
 const client=db({posted:true});await assert.rejects(get().updateEmployeeTrackingStart(client,{employeeId:ID,value:'2026-11-01'}),e=>e.statusCode===409);
 assert.equal(client.calls.some(c=>c.sql.startsWith('UPDATE')),false);
});
test('employees have independent tracking boundaries',()=>{
 const starts=new Map([['a',{start:'2026-11-01'}],['b',{start:null}]]);
 assert.equal(get().isBeforeEmployeeTracking('a','2026-10-30',starts),true);
 assert.equal(get().isBeforeEmployeeTracking('a','2026-11-01',starts),false);
 assert.equal(get().isBeforeEmployeeTracking('b','2026-10-30',starts),false);
});
test('absence generation uses the employee boundary while retaining normal assignment rules',async()=>{
 const {addAbsenceReportRows}=require('../src/modules/dtr/services/reportAbsences')({
  evaluateLocatorCoverage:()=>({isFullCoverage:false}),getExpectedWorkMinutes:()=>480,
  getShiftInfoForDateFromAssignments:()=>({workingDays:[1,2,3,4,5],endMinutes:1020}),
  isOvernight:()=>false,resolveShiftType:()=> 'full_day',resolvedWorkingDay:()=>true,
  resolveAttendancePolicy:()=>({absentEqualsFullDayDeduction:true}),
 });
 const rows=[];
 await addAbsenceReportRows({trackingStarts:new Map([['a',{start:'2026-11-02'}]]),
  assignmentsByEmployee:new Map(),attendancePolicyContext:{},employeeIds:['a','b'],startD:new Date('2026-11-01T12:00:00'),
  endD:new Date('2026-11-02T12:00:00'),existingKeys:new Set(),holidayByDate:new Map(),leaveKeys:new Set(),locatorByKey:new Map(),
  nowMinutes:1200,rows,scheduleOverrides:new Map(),todayStr:'2026-11-03',userIdToName:{}});
 assert.deepEqual(rows.map(r=>r.status),['not_tracked','absent','absent','absent']);
 assert.equal(rows[0].undertime_minutes,0);
});
