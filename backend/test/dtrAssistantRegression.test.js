const test = require('node:test');
const assert = require('node:assert/strict');

const {
  detectEmployeeAssistantIntent,
} = require('../src/services/dtrAssistant/dtrAssistantIntentService');
const {
  buildFastEmployeeAssistantReply,
} = require('../src/services/dtrAssistant/dtrAssistantFastReply');
const {
  dtrExportRows,
} = require('../src/services/dtrAssistant/dtrAssistantExportService');
const {
  normalizeRating,
} = require('../src/services/dtrAssistant/dtrAssistantFeedbackService');
const {
  __test: assistantServiceTest,
} = require('../src/services/dtrAssistant/dtrAssistantService');

test('DTR assistant regression: Bisaya/Tagalog/English prompts route to expected intents', () => {
  const cases = [
    ['pila kabuok absent nako aning bulana?', 'dtr_absent_summary'],
    ['unsay status sa akong dtr adtung niaging miyerkules?', 'dtr_status_explanation'],
    ['naa koy absent gahapon?', 'dtr_absent_summary'],
    ['pila akong balance sa sick leave?', 'leave_balance'],
    ['ngano gamay nalang akong vacation leave?', 'leave_balance'],
    ['why is my vacation leave balance low?', 'leave_balance'],
    ['unsay requirements sa maternity leave?', 'leave_requirements'],
    ['need med cert if 5 days sick leave?', 'leave_attachment_requirement'],
    ['kinsa nag hold sa akong leave request?', 'leave_approval_tracker'],
    ['ngano gi reject akong leave?', 'leave_rejection_reason'],
    ['pwede ba ko mag file ug pass slip ugma?', 'locator_availability_check'],
    ['ngano gi reject akong locator?', 'locator_rejection_reason'],
    ['asa na akong official business request?', 'locator_approval_tracker'],
    ['covered ba sa locator akong PM out?', 'dtr_locator_coverage_check'],
    ['what are the locator types i can file?', 'locator_types'],
    ['how about the wfh?', 'locator_types'],
    ['unsa ang wfh?', 'locator_types'],
    ['export my dtr this month', 'dtr_export_guidance'],
  ];

  for (const [message, expected] of cases) {
    assert.equal(detectEmployeeAssistantIntent(message), expected, message);
  }
});

test('DTR assistant regression: locator type questions list active request types', () => {
  const context = {
    locator_types: [
      {
        code: 'locator',
        label: 'Locator / Official Business',
        short_label: 'Locator',
        location_label: 'Office / Destination',
        location_hint: 'Enter office or destination',
        dtr_slot_label: 'On Field',
        requires_attachment: false,
        coverage_mode: 'manual',
      },
      {
        code: 'pass_slip',
        label: 'Pass Slip',
        short_label: 'Pass Slip',
        location_label: 'Destination / Location',
        location_hint: 'Enter destination or location',
        dtr_slot_label: 'Pass Slip',
        requires_attachment: false,
        coverage_mode: 'manual',
      },
      {
        code: 'work_from_home',
        label: 'Work From Home',
        short_label: 'WFH',
        location_label: 'Work Location',
        location_hint: 'Enter work location',
        dtr_slot_label: 'WFH',
        requires_attachment: false,
        coverage_mode: 'wfh',
      },
    ],
  };

  const listReply = buildFastEmployeeAssistantReply(
    'what are the locator types i can file?',
    context,
    'locator_types'
  );

  assert.match(listReply, /Locator \/ Official Business/);
  assert.match(listReply, /Pass Slip/);
  assert.match(listReply, /Work From Home/);

  const wfhReply = buildFastEmployeeAssistantReply(
    'how about the wfh?',
    context,
    'locator_types'
  );

  assert.match(wfhReply, /Work From Home/);
  assert.match(wfhReply, /WFH coverage/i);
  assert.doesNotMatch(wfhReply, /locator request is approved/i);
  assert.doesNotMatch(wfhReply, /Pass Slip/);
});

test('DTR assistant regression: conversation memory keeps topic and entity follow-ups', () => {
  let memory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'locator_types',
    text: 'how about wfh?',
    dateRange: {
      label: 'today',
      startDate: '2026-06-15',
      endDate: '2026-06-15',
    },
    locatorType: 'work_from_home',
    modelProfile: 'tools_ollama',
  });

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('what about tomorrow?', memory),
    'locator_availability_check'
  );
  assert.match(
    assistantServiceTest.enrichMessageWithMemory(
      'what about tomorrow?',
      memory,
      'locator_availability_check'
    ),
    /work from home/i
  );
  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('what about tomorrow for wfh?', memory),
    'locator_availability_check'
  );

  memory = assistantServiceTest.buildNextAssistantMemory(memory, {
    intent: 'dtr_status_explanation',
    text: 'unsay status sa akong dtr adtung niaging miyerkules?',
    dateRange: {
      label: 'previous Wednesday',
      startDate: '2026-06-10',
      endDate: '2026-06-10',
    },
    modelProfile: 'tools_ollama',
  });

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('same date?', memory),
    'dtr_status_explanation'
  );
  assert.match(
    assistantServiceTest.enrichMessageWithMemory(
      'same date?',
      memory,
      'dtr_status_explanation'
    ),
    /2026-06-10/
  );
  assert.equal(memory.history.length, 2);
  assert.equal(memory.topics.locator.locatorType, 'work_from_home');
});

test('DTR assistant regression: conversation memory does not leak stale leave type into explicit topic switches', () => {
  let memory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'leave_balance',
    text: 'pila akong sick leave balance?',
    dateRange: {
      label: 'today',
      startDate: '2026-06-15',
      endDate: '2026-06-15',
    },
    leaveType: 'sick',
    modelProfile: 'tools_ollama',
  });

  memory = assistantServiceTest.buildNextAssistantMemory(memory, {
    intent: 'locator_types',
    text: 'what are locator types?',
    dateRange: {
      label: 'today',
      startDate: '2026-06-15',
      endDate: '2026-06-15',
    },
    modelProfile: 'tools_ollama',
  });

  const enriched = assistantServiceTest.enrichMessageWithMemory(
    'what is my leave balance?',
    memory,
    null
  );

  assert.doesNotMatch(enriched, /sick leave/i);
});

test('DTR assistant regression: vague filing/status prompts ask clarification instead of guessing', () => {
  assert.equal(
    assistantServiceTest.clarificationIntentForMessage(
      'pwede ba ko mag file?',
      null,
      null
    ),
    'clarify_filing_topic'
  );
  assert.match(
    assistantServiceTest.clarificationContent(
      'clarify_filing_topic',
      'pwede ba ko mag file?'
    ),
    /leave request.*locator slip\/WFH/i
  );
  assert.equal(
    assistantServiceTest.clarificationIntentForMessage(
      'pwede ba ko mag file ug pass slip ugma?',
      null,
      null
    ),
    null
  );
  assert.equal(
    assistantServiceTest.clarificationIntentForMessage(
      'approved na ba?',
      null,
      null
    ),
    'clarify_status_topic'
  );
  assert.equal(
    assistantServiceTest.clarificationIntentForMessage(
      'where is my request?',
      null,
      null
    ),
    'clarify_status_topic'
  );

  const filingMemory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'clarify_filing_topic',
    text: 'pwede ba ko mag file?',
    dateRange: {
      label: 'today',
      startDate: '2026-06-15',
      endDate: '2026-06-15',
    },
    modelProfile: 'tools_ollama',
  });

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('leave', filingMemory),
    'leave_guided_filing'
  );
  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('wfh tomorrow', filingMemory),
    'locator_availability_check'
  );

  const statusMemory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'clarify_status_topic',
    text: 'approved na ba?',
    dateRange: {
      label: 'today',
      startDate: '2026-06-15',
      endDate: '2026-06-15',
    },
    modelProfile: 'tools_ollama',
  });

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('locator', statusMemory),
    'locator_status'
  );
  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('DTR', statusMemory),
    'today_dtr'
  );
});

test('DTR assistant regression: locator exact slot coverage requires approved matching slot', () => {
  const context = {
    date_range: {
      label: 'tomorrow',
      startDate: '2026-06-16',
      endDate: '2026-06-16',
    },
    recent_locator_slips: [
      {
        slip_date: '2026-06-16',
        request_type: 'pass_slip',
        request_type_label: 'Pass Slip',
        status: 'pending_department_head',
        coverage: {
          am_in: false,
          am_out: false,
          pm_in: true,
          pm_out: true,
        },
      },
    ],
  };

  const reply = buildFastEmployeeAssistantReply(
    'covered ba sa locator akong PM out ugma?',
    context,
    'dtr_locator_coverage_check'
  );

  assert.match(reply, /PM out/);
  assert.match(reply, /wala koy approved locator/i);
  assert.match(reply, /not final coverage until approved/i);
});

test('DTR assistant regression: DTR export rows include no-record scheduled days', () => {
  const rows = dtrExportRows({
    date_range: {
      startDate: '2026-06-01',
      endDate: '2026-06-02',
    },
    dtr_records: [
      {
        attendance_date: '2026-06-01',
        status: 'present',
        time_in: '08:00',
        time_out: '17:00',
      },
    ],
    dtr_calendar_days: [
      {
        attendance_date: '2026-06-01',
        shift_id: 'shift-1',
        shift_name: 'Morning Shift',
        start_time: '08:00',
        end_time: '17:00',
      },
      {
        attendance_date: '2026-06-02',
        shift_id: 'shift-1',
        shift_name: 'Morning Shift',
        start_time: '08:00',
        end_time: '17:00',
      },
    ],
  });

  assert.equal(rows.rows.length, 2);
  assert.equal(rows.rows[0][5], 'present');
  assert.equal(rows.rows[1][5], 'no_record');
});

test('DTR assistant regression: feedback rating aliases normalize safely', () => {
  assert.equal(normalizeRating('correct'), 'up');
  assert.equal(normalizeRating('wrong'), 'down');
  assert.equal(normalizeRating('maybe'), null);
});
