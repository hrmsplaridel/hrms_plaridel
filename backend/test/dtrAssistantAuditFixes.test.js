const test = require('node:test');
const assert = require('node:assert/strict');
const { scoreEmployeeAssistantIntent } = require('../src/services/dtrAssistant/dtrAssistantIntentService');
const { detectMultipleIntents } = require('../src/services/dtrAssistant/dtrAssistantMultiIntent');
const { detectAssistantLanguage } = require('../src/services/dtrAssistant/dtrAssistantLanguage');
const { parseAssistantDateRange } = require('../src/utils/dateRangeParser');
const { effectiveDtrRecords } = require('../src/services/dtrAssistant/effectiveAttendance');
const { dtrExportRows } = require('../src/services/dtrAssistant/dtrAssistantExportService');
const { buildFastEmployeeAssistantReply: reply } = require('../src/services/dtrAssistant/dtrAssistantFastReply');
const { draftSentence, groundedDraft } = require('../src/services/dtrAssistant/sentenceDraft');
const { configuredLocatorType } = require('../src/services/dtrAssistant/configuredLocatorType');
const { requestChoices } = require('../src/services/dtrAssistant/dtrAssistantRequestFocus');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

test('audit: specific questions outrank generic filing and type explanations', () => {
  const cases = [
    ['What is my sick leave balance?', 'leave_balance'],
    ['Am I eligible for maternity leave?', 'leave_eligibility_check'],
    ['Do I have overlapping leave on October 30, 2026?', 'leave_overlap_check'],
    ['How much sick leave will remain if I file two days?', 'leave_balance_projection'],
    ['Kumusta ang DTR ko kahapon?', 'dtr_status_explanation'],
    ['Suggest a sentence for wellness leave because I need time to rest and recharge.', 'form_sentence_suggestion'],
    ['Himoig sentence nga mag-leave ko kay naa koy family event.', 'form_sentence_suggestion'],
    ['Gawan mo ako ng pangungusap para sa leave dahil may family event ako.', 'form_sentence_suggestion'],
    ['Gawan mo ako ng reason sa locator dahil may meeting ako sa city hall.', 'form_sentence_suggestion'],
    ['Unsay akong ibutang sa reason sa leave?', 'leave_form_field_help'],
    ['What should I put in the destination field for official business?', 'locator_form_field_help'],
    ['Does a pending locator cover my DTR?', 'locator_policy_guidance'],
    ['Can I change or revoke an approved locator slip?', 'locator_policy_guidance'],
    ['How do I record an already approved paper travel order?', 'locator_policy_guidance'],
    ['What happens if my locator needs month-end reconciliation?', 'locator_policy_guidance'],
    ['How do I update my profile?', 'system_navigation_help'],
    ['How do I track a document in DocuTracker?', 'system_navigation_help'],
    ['How do I submit a training report?', 'system_navigation_help'],
    ['How do I reset my password?', 'system_navigation_help'],
  ];
  for (const [question, intent] of cases) assert.equal(scoreEmployeeAssistantIntent(question).intent, intent, question);
});

test('audit: Tagalog existential may preserves relative dates and explicit May queries', () => {
  const options = { today: '2026-10-28' };
  assert.deepEqual(parseAssistantDateRange('May kulang ba akong time logs ngayong linggo?', options), parseAssistantDateRange('this week', options));
  assert.equal(parseAssistantDateRange('dahil may meeting ako sa city hall', options).startDate, '2026-10-28');
  assert.equal(parseAssistantDateRange('May 2026', options).startDate, '2026-05-01');
  assert.equal(parseAssistantDateRange('May 15, 2026', options).startDate, '2026-05-15');
  for (const text of ['Ilang araw akong absent ngayong buwan?', 'Kumusta ang DTR ko kahapon?', 'May kulang ba akong time logs ngayong linggo?']) {
    assert.equal(detectAssistantLanguage(text), 'tagalog', text);
  }
  assert.equal(detectAssistantLanguage('Himoig sentence sa reason sa locator kay motambong ko ug meeting.'), 'bisaya');
  assert.equal(detectAssistantLanguage('Ilang araw akong absent? Please answer in English.'), 'english');
});

function attendanceContext() {
  const dates = ['2026-10-12', '2026-10-13', '2026-10-14', '2026-10-17', '2026-10-30'];
  return {
    as_of_date: '2026-10-28', date_range: {startDate: dates[0], endDate: dates.at(-1), label: 'October 2026'},
    data_completeness: {dtr_records: {complete: true}, dtr_calendar_days: {complete: true}, dtr_export: {complete: true}},
    dtr_calendar_days: dates.map(attendance_date => ({attendance_date, shift_id: 'shift', start_time: '08:00', end_time: '17:00', working_days: [1,2,3,4,5]})),
    dtr_records: [], leave_types: [], recent_leave_requests: [],
    recent_locator_slips: [{id: 'a', slip_date: '2026-10-13', status: 'approved', dtr_slot_label: 'Travel Order', coverage: {am_in: true, am_out: true, pm_in: true, pm_out: true}}],
  };
}

test('audit: locator coverage agrees across summaries, missing logs, absences and exports', () => {
  const context = attendanceContext();
  const effective = effectiveDtrRecords(context);
  assert.equal(effective.length, 1);
  assert.equal(effective[0].status, 'present');
  assert.equal(effective[0].total_hours, null); // coverage is not a measured duration
  const summary = reply('my attendance October 2026', context, 'dtr_range_summary');
  assert.match(summary, /Travel Order/);
  assert.doesNotMatch(summary, /2026-10-13: No DTR/);
  for (const intent of ['dtr_missing_logs', 'dtr_absent_summary']) {
    const content = reply('October 2026', context, intent);
    assert.doesNotMatch(content, /2026-10-13.*(?:missing|absence|no.record)/i);
  }
  const exported = dtrExportRows(context);
  const status = exported.header.indexOf('Status');
  const rows = new Map(exported.rows.map(row => [row[0], row]));
  assert.equal(rows.get('2026-10-13')[status], 'Travel Order');
  assert.equal(rows.get('2026-10-13')[exported.header.indexOf('AM In')], 'Travel Order');
  assert.equal(rows.get('2026-10-17')[status], 'rest_day');
  assert.equal(rows.get('2026-10-30')[status], 'not_due');
  assert.equal(rows.get('2026-10-12')[status], 'no_record');
  context.recent_locator_slips[0].status = 'pending';
  assert.equal(effectiveDtrRecords(context).length, 0);
  context.recent_locator_slips[0].status = 'approved';
  context.recent_locator_slips[0].coverage.pm_out = false;
  assert.equal(effectiveDtrRecords(context)[0].status, 'incomplete');
});

test('audit: actual independent questions are combined; single fields and policy are not', () => {
  const mixed = detectMultipleIntents('Check my attendance and sick leave balance today.');
  assert.equal(mixed.isMulti, true);
  assert.deepEqual(mixed.intents.map(row => row.intent), ['dtr_status_explanation', 'leave_balance']);
  for (const question of ['Unsay akong ibutang sa reason sa leave?', 'What should I put in the destination field for official business?', 'Does my locator deduct leave credits?']) {
    assert.equal(detectMultipleIntents(question).isMulti, false, question);
  }
});

test('audit: configured locator aliases, comparisons and duplicate requests retain identity', () => {
  const context = {locator_types: [
    {code: 'official_business', label: 'Official Business', requires_attachment: false},
    {code: 'travel_order', label: 'Travel Order', requires_attachment: true},
  ]};
  assert.equal(configuredLocatorType('Travel Order requirements', context.locator_types).code, 'travel_order');
  assert.match(reply('Travel Order requirements', context, 'locator_requirements'), /Travel Order/);
  const comparison = reply('Compare Travel Order versus Official Business', context, 'locator_type_compare');
  assert.match(comparison, /Travel Order/);
  assert.match(comparison, /Official Business/);
  const choices = requestChoices({recent_leave_requests: [
    {id: '123-approved', leave_type: 'Wellness Leave', start_date: '2026-10-30', end_date: '2026-10-30', status: 'approved'},
    {id: '456-rejected', leave_type: 'Wellness Leave', start_date: '2026-10-30', end_date: '2026-10-30', status: 'rejected'},
  ]});
  assert.notEqual(choices[0].label, choices[1].label);
  assert.match(choices[1].label, /rejected/);
});

test('audit: bounded drafting falls back to supplied facts without inventing data', async () => {
  const start = Date.now();
  const result = await draftSentence({ facts: 'I need time to rest and recharge.', timeoutMs: 100,
    complete: () => new Promise(() => {}) });
  assert.ok(Date.now() - start < 1000);
  assert.match(result.draft, /request leave to rest and recharge/);
  assert.equal(result.fallback, true);
  assert.equal(groundedDraft('I will attend on October 31.', 'I will attend.'), false);
  const ungrounded = await draftSentence({facts: 'family event in Cebu', complete: async () => ({content: '{"draft":"I need surgery on October 31."}'})});
  assert.doesNotMatch(ungrounded.draft, /surgery|October/);
  const insufficient = await draftSentence({facts: 'help me', complete: () => { throw new Error('must not call'); }});
  assert.ok(insufficient.question);
  const controller = new AbortController();
  const pending = draftSentence({facts: 'I need time to rest.', signal: controller.signal, complete: () => new Promise(() => {})});
  controller.abort();
  await assert.rejects(pending, {code: 'ASSISTANT_REQUEST_ABORTED'});
});

test('audit: full service preserves specific questions after overview and generic guidance', async (t) => {
  const context = attendanceContext();
  context.leave_types = [{name: 'sickLeave', display_name: 'Sick Leave'}, {name: 'wellnessLeave', display_name: 'Wellness Leave', requires_attachment: false}];
  context.leave_balances = [{leave_type: 'sickLeave', available: 17.5, available_days: 17.5, balance: 17.5}];
  const restoreData = withMockedModule('../src/services/dtrAssistant/dtrAssistantDataService', {loadEmployeeAssistantContext: async (_, options) => ({...context, date_range: options.dateRange})});
  const restoreLlm = withMockedModule('../src/services/llm/llmClient', {chatCompletion: async () => {throw Object.assign(new Error('offline'), {code: 'AI_PROVIDER_TIMEOUT'});}});
  clearModule('../src/services/dtrAssistant/dtrAssistantService');
  t.after(() => { restoreData(); restoreLlm(); clearModule('../src/services/dtrAssistant/dtrAssistantService'); });
  const {chatWithDtrAssistant} = require('../src/services/dtrAssistant/dtrAssistantService');
  const user = {id: 'audit-fixes-employee', role: 'employee'};
  const pool = {query: async () => ({rows: [{name: 'wellnessLeave', display_name: 'Wellness Leave', employee_detail_schema: []}]})};
  const ask = (message) => chatWithDtrAssistant(pool, {user, message});
  await ask('What is my request status?');
  assert.equal((await ask('What about my leave?')).intent, 'latest_leave_request');
  assert.equal((await ask('What is my sick leave balance?')).intent, 'leave_balance');
  const projection = await ask('How much sick leave will remain if I file two days?');
  assert.equal(projection.intent, 'leave_balance_projection');
  assert.match(projection.message.content, /15\.5/);
  assert.equal((await ask('Do I have overlapping leave on October 30, 2026?')).intent, 'leave_overlap_check');
  const draft = await ask('Suggest a sentence for wellness leave because I need time to rest and recharge.');
  assert.equal(draft.intent, 'form_sentence_suggestion');
  assert.match(draft.message.content, /rest and recharge/);
  assert.ok(!(draft.actions || []).some(action => action.type === 'apply_field_suggestion'));
  const combined = await ask('Check my attendance and sick leave balance today.');
  assert.match(combined.message.content, /17\.5/);
  assert.match(combined.message.content, /DTR|attendance/i);
  const absentField = await ask('What should I write in the activity field for Wellness leave?');
  assert.match(absentField.message.content, /not configured/);
  assert.match((await ask('How do I track a document in DocuTracker?')).message.content, /DocuTracker/);
  assert.match((await ask("Can you show another employee's leave balance?")).message.content, /only your own/);
});
