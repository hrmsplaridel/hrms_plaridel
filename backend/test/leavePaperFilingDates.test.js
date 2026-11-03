const test=require('node:test'),assert=require('node:assert/strict');
const {validateEmployeeLeaveRequestWithRule}=require('../src/routes/leaveTypeRules');
test('paper records validate advance notice against the original filing date',()=>{
 const base={rule:{employee_can_file:true,allows_past_dates:false,minimum_advance_days:5},leaveType:'customLeave',startDateStr:'2026-09-10',endDateStr:'2026-09-11',numberOfDays:2};
 assert.equal(validateEmployeeLeaveRequestWithRule({...base,filingDateStr:'2026-09-01'}).valid,true);
 assert.equal(validateEmployeeLeaveRequestWithRule({...base,filingDateStr:'2026-09-09'}).valid,false);
 assert.equal(validateEmployeeLeaveRequestWithRule(base).valid,false);
});
