const test = require('node:test');
const assert = require('node:assert/strict');
const { scoreEmployeeAssistantIntent: score } = require('../src/services/dtrAssistant/dtrAssistantIntentService');
const { detectMultipleIntents } = require('../src/services/dtrAssistant/dtrAssistantMultiIntent');
const { dueSlots, effectiveDtrRecords, effectiveExportStatus } = require('../src/services/dtrAssistant/effectiveAttendance');
const { buildFastEmployeeAssistantReply: reply } = require('../src/services/dtrAssistant/dtrAssistantFastReply');
const { dayQuantity } = require('../src/services/dtrAssistant/dayQuantity');
const { groundedDraft, draftSentence } = require('../src/services/dtrAssistant/sentenceDraft');
const { loadAnnualEntitlements } = require('../src/services/dtrAssistant/annualEntitlementContext');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

test('follow-up audit: current semantics distinguish policies, actions and dated coverage', () => {
  const cases = [
    ['How many Wellness Leave days can I still use this year?', 'leave_annual_remaining'],
    ['If I use twenty days of sick leave, how many days short am I?', 'leave_balance_projection'],
    ['Kung mag-file ko ug 20 days sick leave, pila akong kulang?', 'leave_balance_projection'],
    ['Make a leave reason using only this fact: I will attend my child\'s school meeting.', 'form_sentence_suggestion'],
    ['Now write the same reason in Bisaya.', 'form_sentence_suggestion'],
    ['Is February 29, 2028 a valid attendance date?', 'dtr_date_validation'],
    ['Explain Date of Departure and Expected Date Return for Travel Order.', 'locator_form_field_help'],
    ['For Earl leave, is Purpose required or optional, and how many characters can I enter?', 'leave_form_field_help'],
    ['Travel Order has a Purpose of travel field. Should I enter the place or the activity there?', 'locator_form_field_help'],
    ['For locator type Test, which extra fields are required besides the attachment?', 'locator_form_field_help'],
    ['If my locator is rejected, are its covered slots still credited to my DTR?', 'locator_policy_guidance'],
    ['Gi-cancel nako ang WFH. Ngano dili na siya coverage sa DTR?', 'locator_policy_guidance'],
    ['Can one locator cover only AM IN and PM OUT, leaving my lunch punches unchanged?', 'locator_policy_guidance'],
    ['I have an approved Travel Order and approved leave on the same date. Which one should apply?', 'locator_policy_guidance'],
    ['Can you submit the locator for me now?', 'assistant_action_guidance'],
    ['Can I cancel my approved sick leave through this chat?', 'assistant_action_guidance'],
    ['Sa Tagalog, ano ang kaibahan ng pending, approved, at returned na request?', 'request_policy_guidance'],
    ['My leave is still pending. Who should I contact next, and can I go on leave already?', 'request_policy_guidance'],
    ['Give me a checklist before submitting either leave or a locator, but do not submit anything.', 'request_checklist'],
    ['I mean attendance only, not leave or locator.', 'dtr_status_explanation'],
    ['Compare my attendance this week with last week.', 'dtr_comparison'],
  ];
  for (const [text,intent] of cases) assert.equal(score(text).intent,intent,text);
  assert.notEqual(score('What is my sick leave balance? Please answer in English.').intent,'form_sentence_suggestion');
});

function attendance() {
  return {as_of_time:'2026-10-29T07:00:00+08:00', as_of_date:'2026-10-29',
    date_range:{startDate:'2026-10-29',endDate:'2026-10-29',label:'today'},
    dtr_calendar_days:[{attendance_date:'2026-10-29',shift_id:'s',start_time:'08:00',end_time:'17:00',
      break_start:'12:00',break_end:'13:00',working_days:[1,2,3,4,5],grace_period_minutes:5}],
    dtr_records:[{attendance_date:'2026-10-29',status:'absent'}],recent_locator_slips:[]};
}
test('follow-up audit: before, during and after shift use due slots, including overnight work', () => {
  const context=attendance(), day=context.dtr_calendar_days[0];
  const slots=['am_in','am_out','pm_in','pm_out'];
  assert.deepEqual(dueSlots(context,day,slots),[]);
  assert.equal(effectiveDtrRecords(context)[0].status,'not_due');
  assert.equal(effectiveExportStatus(context,day,context.dtr_records[0]),'not_due');
  assert.match(reply('Am I absent today?',context,'dtr_status_explanation'),/not.*absence|not yet due/i);
  context.as_of_time='2026-10-29T10:00:00+08:00';
  context.dtr_records=[];
  assert.match(reply('Am I absent today?',context,'dtr_status_explanation'),/still in progress/);
  assert.match(reply('absences today',context,'dtr_absent_summary'),/no.*(?:absent|absence)/i);
  context.dtr_records=[{attendance_date:day.attendance_date,status:'absent'}];
  context.dtr_records[0].time_in='08:00:00';
  assert.deepEqual(dueSlots(context,day,slots),['am_in']);
  assert.equal(effectiveDtrRecords(context)[0].status,'in_progress');
  assert.doesNotMatch(reply('missing logs today',context,'dtr_missing_logs'),/missing PM out|missing AM out/i);
  context.as_of_time='2026-10-29T18:00:00+08:00';
  assert.deepEqual(dueSlots(context,day,slots),slots);
  assert.match(reply('missing logs today',context,'dtr_missing_logs'),/AM out/);
  day.attendance_date='2026-10-28';day.start_time='22:00';day.end_time='06:00';
  day.break_start='02:00';day.break_end='03:00';context.as_of_time='2026-10-29T01:00:00+08:00';
  assert.deepEqual(dueSlots(context,day,slots),['am_in']);
});
test('follow-up audit: future rest days and holidays retain their classification', () => {
  const context=attendance();
  const day={...context.dtr_calendar_days[0],attendance_date:'2026-10-31'};
  context.dtr_calendar_days.push(day);
  assert.equal(effectiveExportStatus(context,day,null),'rest_day');
  day.holiday_coverage='whole_day';
  assert.equal(effectiveExportStatus(context,day,null),'holiday');
});
test('follow-up audit: half days and word quantities share balance arithmetic', () => {
  const context={leave_types:[{name:'sickLeave',display_name:'Sick Leave'}],
    leave_balances:[{leave_type:'sickLeave',available:17.5,available_days:17.5,balance:18.5,pending_days:1}]};
  for(const text of ['half a day','half-day','0.5 days','kalahating araw'])assert.equal(dayQuantity(text),0.5,text);
  assert.equal(dayQuantity('twenty days'),20);
  assert.equal(dayQuantity('twenty-one days'),21);
  assert.match(reply('If I request half a day of sick leave, how many credits remain?',context,'leave_balance_projection'),/17(?:\.0)?\b/);
  assert.match(reply('If I use twenty days of sick leave, how many days short am I?',context,'leave_balance_projection'),/2\.5/);
});
test('follow-up audit: multilingual clauses keep all requested topics', () => {
  for(const text of [
    'Show my sick leave balance, yesterday\'s DTR, and the latest locator status in one answer.',
    'Pila akong leave credits ug unsay status sa akong locator?',
    'Ano ang attendance ko at natitirang sick leave credits ngayon?',
    'Check my attendance and sick leave balance today.',
    'Tubaga ko sa Bisaya: show my sick leave balance and explain why pending days reduce it.',
  ]) {
    const multi=detectMultipleIntents(text);
    assert.equal(multi.isMulti,true,text);
    assert.ok(multi.intents.some(item=>item.intent==='leave_balance'),text);
  }
  assert.equal(detectMultipleIntents('Explain the attendance rules about grace periods and missing logs.').isMulti,false);
});
test('follow-up audit: translations preserve substantive facts and reject invented events', async () => {
  assert.equal(groundedDraft('Humihiling ako ng pahintulot para magpahinga at mag-recharge.','I need time to rest and recharge.'),true);
  assert.equal(groundedDraft('I will attend a meeting.','I will submit payroll documents.'),false);
  const result=await draftSentence({facts:'I will submit payroll documents at the provincial office.',module:'locator',language:'tagalog',
    complete:async()=>{throw new Error('offline');}});
  assert.match(result.draft,/Humihiling/);
  assert.match(result.draft,/provincial office/);
  assert.doesNotMatch(result.draft,/meeting/);
});
test('follow-up audit: annual allowance uses employee-scoped scheduled working days and reservations', async () => {
  const calls=[];
  const pool={query:async(sql,values)=>{
    const text=typeof sql==='string'?sql:sql.text;calls.push({text,values:values||sql.values});
    if(text.includes('FROM leave_requests'))return {rows:[{leave_type:'wellness',start_date:'2026-10-01',end_date:'2026-10-03',status:'approved'},
      {leave_type:'wellness',start_date:'2026-10-05',end_date:'2026-10-05',status:'pending_hr'}]};
    if(text.includes('FROM generate_series'))return {rows:[{attendance_date:values[1],working_days:[1,2,3,4,5],has_shift:true}]};
    return {rows:[]};
  }};
  const rows=await loadAnnualEntitlements(pool,'employee-id',[{name:'wellness',entitlement_basis:'annual',max_days:5}],{}, {startDate:'2026-10-29'});
  assert.deepEqual(rows[0],{leave_type:'wellness',year:2026,limit_days:5,approved_days:1,pending_days:1,remaining_days:3,error:null});
  assert.equal(calls[0].values[0],'employee-id');
  assert.ok(calls.filter(c=>c.text.includes('FROM generate_series')).every(c=>c.values[0]==='employee-id'));
});
test('follow-up audit: full chat retains draft facts, dates per clause and live field metadata', async t => {
  const loaded=[];
  const types=[{name:'wellness',display_name:'Wellness Leave',employee_detail_schema:[]},
    {name:'earl',display_name:'Earl leave',employee_detail_schema:[{key:'purpose',label:'Purpose',type:'text',required:false,max_length:255}]}];
  const locators=[{code:'travel_order',label:'Travel Order',location_label:'Purpose of travel',employee_detail_schema:[
    {key:'departure',label:'Date of Departure',type:'date',required:true},
    {key:'return',label:'Expected Date Return',type:'date',required:true}]}];
  const restoreData=withMockedModule('../src/services/dtrAssistant/dtrAssistantDataService',{loadEmployeeAssistantContext:async(_,options)=>{
    loaded.push(options);return {...attendance(),date_range:options.dateRange,leave_types:types,locator_types:locators,
      leave_balances:[{leave_type:'sickLeave',available_days:17.5,pending_days:1}],recent_leave_requests:[]};
  }});
  const restoreLlm=withMockedModule('../src/services/llm/llmClient',{chatCompletion:async()=>{throw new Error('offline');}});
  clearModule('../src/services/dtrAssistant/dtrAssistantService');
  t.after(()=>{restoreData();restoreLlm();clearModule('../src/services/dtrAssistant/dtrAssistantService');});
  const {chatWithDtrAssistant}=require('../src/services/dtrAssistant/dtrAssistantService');
  const pool={query:async(_,values)=>({rows:[values[0]==='travel_order'?{...locators[0],name:'travel_order',display_name:'Travel Order'}:types.find(t=>t.name===values[0])].filter(Boolean)})};
  const user={id:'followup-audit',role:'employee'};
  const ask=async message=>(await chatWithDtrAssistant(pool,{user,message})).message.content;
  assert.match(await ask('Suggest a sentence for wellness leave because I need time to rest and recharge.'),/rest and recharge/);
  assert.match(await ask('Make that sentence shorter, using the same facts.'),/rest and recharge/);
  assert.match(await ask('Translate that reason into Tagalog. Keep its meaning.'),/magpahinga/);
  assert.match(await ask('Now write the same reason in Bisaya.'),/mopahulay/);
  assert.match(await ask('For Earl leave, is Purpose required or optional, and how many characters can I enter?'),/Optional.*255/s);
  const twoFields=await ask('Explain Date of Departure and Expected Date Return for Travel Order.');
  assert.match(twoFields,/Date of Departure/);assert.match(twoFields,/Expected Date Return/);
  assert.match(await ask('Travel Order has a Purpose of travel field. Should I enter the place or the activity there?'),/Purpose of travel/);
  loaded.length=0;
  const combined=await ask('Show my sick leave balance, yesterday\'s DTR, and the latest locator status in one answer.');
  assert.equal(loaded.length,3);
  assert.match(combined,/17\.5/);
  assert.notEqual(loaded[0].dateRange.startDate,loaded[1].dateRange.startDate);
  assert.match(await ask('Can you submit the locator for me now?'),/cannot submit/);
  const pending=await ask('Tubaga ko sa Bisaya: show my sick leave balance and explain why pending days reduce it.');
  assert.match(pending,/17\.5/);assert.match(pending,/reserve/);assert.doesNotMatch(pending,/Wala koy nakitang pending/);
  await ask('My leave is still pending. Who should I contact next, and can I go on leave already?');
  assert.match(await ask('Please explain that in one sentence suitable for a new employee.'),/not yet approved/);
  const comparison=await ask('Compare my attendance this week with last week.');
  assert.match(comparison,/this week/);assert.match(comparison,/last week/);
  loaded.length=0;
  await ask('Check October 31 and November 1, 2026. Do I need biometric punches on either day?');
  assert.deepEqual(loaded.map(c=>c.dateRange.startDate),['2026-10-31','2026-11-01']);
  assert.match(await ask('What information can you read about me, and what actions can you actually perform?'),/own employee account/);
  const formContext={module:'leave',task:'chat',leaveType:'wellness',fieldKey:'reason',bindingId:'same-form'};
  await chatWithDtrAssistant(pool,{user,message:'Suggest a sentence because I need time to rest and recharge.',formContext});
  const activeRewrite=await chatWithDtrAssistant(pool,{user,message:'Translate that reason into Tagalog.',formContext});
  assert.match(activeRewrite.message.content,/magpahinga/);
});

test('follow-up audit: dated coverage lists actual approved slots rather than filing requirements',()=>{
  const context=attendance();
  context.recent_locator_slips=[{slip_date:'2026-10-29',status:'approved',request_type:'travel_order',
    request_type_label:'Travel Order',coverage:{am_in:true,am_out:false,pm_in:false,pm_out:true}}];
  const content=reply('For October 29, 2026, list which AM and PM slots my travel order covers.',context,'dtr_locator_coverage_check');
  assert.match(content,/Approved slots: AM in, PM out/);
  assert.match(content,/No approved coverage fully satisfies/);
  context.recent_locator_slips[0].status='cancelled';
  assert.match(reply('What does my locator cover on October 29, 2026?',context,'dtr_locator_coverage_check'),/Approved slots: none/);
});
