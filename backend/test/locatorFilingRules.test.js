const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseLocatorDateOnly,
  validateLocatorWorkingDayForEmployee,
  resolveLocatorShiftCoverage,
} = require('../src/services/locatorFilingRules');

const EMPLOYEE_ID = '00000000-0000-0000-0000-000000000101';

test('locator filing accepts a closed assignment effective on the locator date', async () => {
  let executedSql = '';
  let executedParams = null;
  const client = {
    async query(sql, params) {
      executedSql = String(sql);
      executedParams = params;
      return {
        rows: [{
          id: 'historical-assignment',
          shift_id: 'historical-shift',
          shift_name: 'Regular Shift',
          working_days: [1, 2, 3, 4, 5],
          is_active: false,
        }],
      };
    },
  };

  const result = await validateLocatorWorkingDayForEmployee(
    client,
    EMPLOYEE_ID,
    parseLocatorDateOnly('2026-06-19')
  );

  assert.deepEqual(result, { ok: true });
  assert.deepEqual(executedParams, [EMPLOYEE_ID, '2026-06-19']);
  assert.match(executedSql, /a\.effective_from <= \$2::date/);
  assert.doesNotMatch(executedSql, /a\.is_active/i);
});

for (const mode of ['single_session','full_day','auto']) {
 test(`locator segment options use the effective shift: ${mode}`,async()=>{
  const db={async query(sql,params){
   assert.deepEqual(params,[EMPLOYEE_ID,'2026-06-19']);
   assert.match(sql,/effective_from <= \$2::date/);
   return {rows:[{shift_id:'shift',shift_name:'Day shift',working_days:[1,2,3,4,5],
    punch_mode:mode,start_time:'08:00',end_time:'17:00',break_end:'13:00'}]};
  }};
  const info=await resolveLocatorShiftCoverage(db,EMPLOYEE_ID,parseLocatorDateOnly('2026-06-19'));
  assert.equal(info.single_session,mode==='single_session');assert.equal(info.can_file,true);
  assert.deepEqual(info.allowed_slots,mode==='single_session'?['am_in','pm_out']:['am_in','am_out','pm_in','pm_out']);
  const result=await validateLocatorWorkingDayForEmployee(db,EMPLOYEE_ID,parseLocatorDateOnly('2026-06-19'),{amIn:true,amOut:true,pmIn:false,pmOut:true});
  assert.equal(result.ok,mode!=='single_session');
 });
}
test('single-session validation accepts IN/OUT and rejects middle segments',async()=>{
 const db={async query(){return {rows:[{shift_id:'s',shift_name:'Night shift',working_days:[1,2,3,4,5],punch_mode:'auto',start_time:'22:00',end_time:'06:00'}]};}};
 const date=parseLocatorDateOnly('2026-06-19');
 assert.equal((await validateLocatorWorkingDayForEmployee(db,EMPLOYEE_ID,date,{amIn:true,amOut:false,pmIn:false,pmOut:true})).ok,true);
 assert.equal((await validateLocatorWorkingDayForEmployee(db,EMPLOYEE_ID,date,{amIn:false,amOut:false,pmIn:true,pmOut:false})).ok,false);
});
