const test = require('node:test');
const assert = require('node:assert/strict');

const { scoreSemanticIntents } = require('../src/services/dtrAssistant/dtrAssistantSemanticIntent');
const {
  detectMultipleIntents,
  combineMultiIntentReplies,
  splitMessageSegments,
} = require('../src/services/dtrAssistant/dtrAssistantMultiIntent');
const {
  evaluateGuidedClarification,
  applyPendingClarificationAnswer,
} = require('../src/services/dtrAssistant/dtrAssistantGuidedClarification');
const {
  extractMessageEntities,
  extractDayCount,
  mergePlannerExtraction,
  normalizePlannerExtraction,
} = require('../src/services/dtrAssistant/dtrAssistantMessageExtraction');
const { buildFastEmployeeAssistantReply } = require('../src/services/dtrAssistant/dtrAssistantFastReply');

test('custom leave guideline requests answer from configuration without a built-in guide', () => {
  const context = {leave_types:[{
    name:'wellnessLeave', display_name:'Wellness Leave',
    description:'Configured wellness policy for employees.',
    employee_can_file:true, allows_past_dates:false, requires_attachment:true,
    minimum_advance_days:2, max_days:5,
    employee_detail_schema:[{key:'activity',label:'Activity',required:true,instruction:'Describe your planned wellness activity.'}],
  }]};
  const reply = buildFastEmployeeAssistantReply('I want to file wellness leave give me the guidelines of it', context, 'leave_guideline_section');
  assert.match(reply, /Wellness leave/i);
  assert.match(reply, /Configured wellness policy/);
  assert.match(reply, /planned wellness activity/);
  assert.match(reply, /attachment/i);
  assert.doesNotMatch(reply, /Tell me which one|I can explain these leave guideline sections/);
  const missing = buildFastEmployeeAssistantReply('wellness leave guidelines', {leave_types:[{name:'wellnessLeave',display_name:'Wellness Leave'}]}, 'leave_guideline_section');
  assert.match(missing, /No additional written guidelines/);
});

test('day-of-month answers consume pending dates without treating durations as dates', () => {
  const {parseAssistantDateRange} = require('../src/utils/dateRangeParser');
  for (const text of ['petsa 15 nako eh file', 'sa petsa 15', 'ika-15', 'on the 15th', 'date 15']) {
    assert.equal(parseAssistantDateRange(text, {today:'2026-10-14'}).startDate, '2026-10-15');
    const patch = applyPendingClarificationAnswer(text, {pendingClarification:{topic:'leave',intent:'leave_guided_filing',field:'date',fieldsRemaining:[],leaveType:'wellnessLeave'}});
    assert.match(patch.dateRange.startDate, /-15$/);
    assert.notEqual(patch.pendingClarification?.field, 'date');
  }
  const bare = applyPendingClarificationAnswer('15', {pendingClarification:{topic:'leave',intent:'leave_guided_filing',field:'date',fieldsRemaining:[],leaveType:'wellnessLeave'}});
  assert.match(bare.dateRange.startDate, /-15$/);
  assert.equal(parseAssistantDateRange('15', {today:'2026-10-14'}).label, 'today');
  assert.equal(parseAssistantDateRange('sa 2 days', {today:'2026-10-14'}).label, 'today');
  assert.throws(() => parseAssistantDateRange('petsa 31', {today:'2026-02-10'}));
});

test('guided filing recognizes configured leave names before stale built-in memory', () => {
  const context = { leave_types: [{name:'wellnessLeave',display_name:'Wellness Leave'}, {name:'communityServiceLeave',display_name:'Community Service Leave'}] };
  for (const [message, expected] of [['wellness leave akong eh file', 'wellnessLeave'], ['community service leave', 'communityServiceLeave']]) {
    const result = evaluateGuidedClarification({intent:'leave_guided_filing', text:message, context, memory:{leaveType:'sick'}});
    assert.equal(result.pendingClarification.leaveType, expected);
    assert.equal(result.pendingClarification.field, 'date');
  }
  const {configuredLeaveType} = require('../src/services/dtrAssistant/configuredLeaveType');
  assert.equal(configuredLeaveType('wellness leave', [{name:'other',description:'wellness leave'}]), null);
  assert.equal(configuredLeaveType('wellness leave', [{name:'wellnessLeave',is_active:false}]), null);
});

test('semantic intent matching understands paraphrased leave balance questions', () => {
  const scored = scoreSemanticIntents('Do I still have paid sick time I can use?');
  assert.equal(scored.top?.intent, 'leave_balance');
  assert.ok(scored.top.confidence >= 0.22);
});

test('multi-intent detection splits combined leave and DTR questions', () => {
  const multi = detectMultipleIntents(
    'Pila akong sick leave balance ug naa ba koy missing logs karong semanaha?'
  );
  assert.equal(multi.isMulti, true);
  assert.ok(multi.intents.length >= 2);
  const intents = multi.intents.map((item) => item.intent);
  assert.ok(intents.includes('leave_balance'));
  assert.ok(intents.includes('dtr_missing_logs') || intents.includes('missing_logs'));
});

test('multi-intent replies are combined into one response', () => {
  const context = {
    leave_balances: [
      {
        leave_type: 'sick',
        earned_days: 3,
        used_days: 0,
        adjusted_days: 0,
        pending_days: 0,
        remaining_days: 3,
        available_days: 3,
      },
    ],
    dtr_records: [],
    dtr_calendar_days: [],
  };
  const replies = [
    {
      intent: 'leave_balance',
      content: buildFastEmployeeAssistantReply('pila akong sick leave balance', context, 'leave_balance'),
    },
    {
      intent: 'dtr_missing_logs',
      content: buildFastEmployeeAssistantReply(
        'missing logs karong semanaha',
        context,
        'dtr_missing_logs'
      ),
    },
  ];
  const combined = combineMultiIntentReplies(replies, 'combined question');
  assert.match(combined, /Answers to your questions/i);
  assert.match(combined, /Leave balance/i);
  assert.match(combined, /Missing logs/i);
});

test('guided clarification asks for missing leave filing details', () => {
  const guided = evaluateGuidedClarification({
    intent: 'leave_availability_check',
    text: 'pwede ko mag file ug leave?',
    context: { date_range: { label: 'today', startDate: '2026-06-28', endDate: '2026-06-28' } },
    memory: null,
  });
  assert.ok(guided);
  assert.match(guided.content, /leave type|Leave type/i);
  assert.equal(guided.pendingClarification.field, 'leaveType');
});

test('guided clarification continues step-by-step after an answer', () => {
  const memory = {
    pendingClarification: {
      topic: 'leave',
      intent: 'leave_availability_check',
      field: 'leaveType',
      fieldsRemaining: ['date', 'days'],
      leaveType: null,
      locatorType: null,
    },
  };
  const patch = applyPendingClarificationAnswer('sick leave', memory);
  assert.equal(patch.leaveType, 'sick');
  assert.equal(patch.pendingClarification.field, 'date');
});

test('extractDayCount understands Bisaya and bare numeric day answers', () => {
  assert.equal(extractDayCount('isa'), 1);
  assert.equal(extractDayCount('isa ka adlaw'), 1);
  assert.equal(extractDayCount('1'), 1);
  assert.equal(extractDayCount('one day'), 1);
  assert.equal(extractDayCount('2 days'), 2);
  assert.equal(extractDayCount('duha ka adlaw'), 2);
});

test('guided clarification accepts Bisaya day-count follow-ups instead of looping', () => {
  const memory = {
    leaveType: 'sick',
    dateRange: { label: 'tomorrow', startDate: '2026-06-29', endDate: '2026-06-29' },
    pendingClarification: {
      topic: 'leave',
      intent: 'leave_availability_check',
      field: 'days',
      fieldsRemaining: [],
      leaveType: 'sick',
      locatorType: null,
    },
  };

  const invalidPatch = applyPendingClarificationAnswer('maybe', memory);
  assert.equal(invalidPatch.dayCount, undefined);
  assert.equal(invalidPatch.pendingClarification?.field, 'days');

  const validPatch = applyPendingClarificationAnswer('isa ka adlaw', memory);
  assert.equal(validPatch.dayCount, 1);
  assert.equal(validPatch.pendingClarification, null);

  const guided = evaluateGuidedClarification({
    intent: 'leave_availability_check',
    text: 'isa ka adlaw',
    context: {
      date_range: memory.dateRange,
      leave_balances: [{ leave_type: 'sickLeave', available_days: 3 }],
    },
    memory: { ...memory, dayCount: 1, pendingClarification: null },
  });
  assert.equal(guided, null);
});

test('message extraction merges planner fields with rule extraction', () => {
  const rules = extractMessageEntities('help me file sick leave tomorrow for medical checkup');
  const planner = normalizePlannerExtraction({
    leaveType: 'sick',
    dayCount: 1,
    reason: 'Medical checkup',
    destination: 'City Health Office',
  });
  const merged = mergePlannerExtraction(rules, planner);
  assert.equal(merged.leaveType, 'sick');
  assert.equal(merged.dayCount, 1);
  assert.match(merged.reason, /medical checkup/i);
});

test('splitMessageSegments separates conjunction-linked questions', () => {
  const segments = splitMessageSegments(
    'What is my leave balance and do I have missing logs this week?'
  );
  assert.ok(segments.length >= 2);
});
