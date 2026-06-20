const test = require('node:test');
const assert = require('node:assert/strict');

const {
  detectEmployeeAssistantIntent,
  scoreEmployeeAssistantIntent,
} = require('../src/services/dtrAssistant/dtrAssistantIntentService');
const {
  buildFastEmployeeAssistantReply,
} = require('../src/services/dtrAssistant/dtrAssistantFastReply');
const {
  dtrExportRows,
} = require('../src/services/dtrAssistant/dtrAssistantExportService');
const {
  normalizeRating,
  __test: feedbackServiceTest,
} = require('../src/services/dtrAssistant/dtrAssistantFeedbackService');
const {
  __test: assistantServiceTest,
} = require('../src/services/dtrAssistant/dtrAssistantService');
const {
  parseAssistantDateRange,
} = require('../src/utils/dateRangeParser');
const {
  buildAllLeaveGuidelines,
} = require('../src/services/dtrAssistant/leaveFilingGuidelines');

test('DTR assistant regression: Bisaya/Tagalog/English prompts route to expected intents', () => {
  const cases = [
    ['pila kabuok absent nako aning bulana?', 'dtr_absent_summary'],
    ['how many absents i have for this month?', 'dtr_absent_summary'],
    ['unsay status sa akong dtr adtung niaging miyerkules?', 'dtr_status_explanation'],
    ['unsa akong dtr status adtun first week sa june?', 'dtr_status_explanation'],
    ['naa koy absent gahapon?', 'dtr_absent_summary'],
    ['pila akong balance sa sick leave?', 'leave_balance'],
    ['ngano gamay nalang akong vacation leave?', 'leave_balance'],
    ['why is my vacation leave balance low?', 'leave_balance'],
    ['how can I file sick leave?', 'leave_form_guidance'],
    ['paano mag file ng sick leave?', 'leave_form_guidance'],
    ['unsaon pag file ug sick leave?', 'leave_form_guidance'],
    ['unsaon pag file mandatory leave?', 'leave_form_guidance'],
    ['can I file 1 day sick leave tomorrow?', 'leave_availability_check'],
    ['okay explain filing deadlines', 'leave_guideline_section'],
    ['can you give me the guidlines of the leave types?', 'leave_guideline_section'],
    ['explain me the leave types', 'leave_guideline_section'],
    ['explain the sick leave', 'leave_guideline_section'],
    ['unsay requirements sa maternity leave?', 'leave_requirements'],
    ['need med cert if 5 days sick leave?', 'leave_attachment_requirement'],
    ['what attachment do I need?', 'leave_attachment_requirement'],
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
    ['what are the dtr rules?', 'dtr_policy_guidance'],
    ['how many absent last pay period?', 'dtr_absent_summary'],
    ['show my dtr from Monday to Friday', 'dtr_range_summary'],
  ];

  for (const [message, expected] of cases) {
    assert.equal(detectEmployeeAssistantIntent(message), expected, message);
  }
});

test('DTR assistant regression: fuzzy intent scoring handles typos and mixed language', () => {
  const cases = [
    ['pila akong sik leev balnce?', 'leave_balance'],
    ['explan sik leev', 'leave_guideline_section'],
    ['unsa requirements sa matirnity leev?', 'leave_requirements'],
    ['how many abssents i have this mnth?', 'dtr_absent_summary'],
    ['naa koy absnt karong bulna?', 'dtr_absent_summary'],
    ['staus sa akong lokator?', 'locator_status'],
    ['pwede ko mag lokator ugma?', 'locator_availability_check'],
  ];

  for (const [message, expected] of cases) {
    const scored = scoreEmployeeAssistantIntent(message);
    assert.equal(scored.intent, expected, message);
    assert.ok(scored.confidence >= 0.62, `${message}: ${scored.confidence}`);
  }
});

test('DTR assistant regression: unclear fuzzy intent is marked for AI planning', () => {
  const scored = scoreEmployeeAssistantIntent('unsa ani karon?');
  assert.equal(scored.intent, null);
  assert.equal(scored.needsAiPlan, true);
});

test('DTR assistant regression: stronger date phrases resolve to useful ranges', () => {
  const today = '2026-06-18';
  assert.deepEqual(parseAssistantDateRange('show my DTR next cutoff', { today }), {
    label: 'next cutoff',
    startDate: '2026-06-16',
    endDate: '2026-06-30',
  });
  assert.deepEqual(parseAssistantDateRange('how many absences last pay period?', { today }), {
    label: 'last pay period',
    startDate: '2026-06-01',
    endDate: '2026-06-15',
  });
  assert.deepEqual(parseAssistantDateRange('my DTR 2 weeks ago', { today }), {
    label: '2 weeks ago',
    startDate: '2026-06-01',
    endDate: '2026-06-07',
  });
  assert.deepEqual(parseAssistantDateRange('what is my status first Monday of June?', { today }), {
    label: 'first monday of june',
    startDate: '2026-06-01',
    endDate: '2026-06-01',
  });
  assert.deepEqual(
    parseAssistantDateRange('unsa akong dtr status adtun first week sa june?', { today }),
    {
      label: 'first week of june',
      startDate: '2026-06-01',
      endDate: '2026-06-07',
    }
  );
  assert.deepEqual(parseAssistantDateRange('show DTR from Monday to Friday', { today }), {
    label: 'monday to friday',
    startDate: '2026-06-15',
    endDate: '2026-06-19',
  });
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

test('DTR assistant regression: DTR and locator policy knowledge appears in replies', () => {
  const dtrReply = buildFastEmployeeAssistantReply(
    'what are the dtr rules?',
    {
      date_range: {
        label: 'this month',
        startDate: '2026-06-01',
        endDate: '2026-06-30',
      },
      dtr_records: [],
      dtr_calendar_days: [],
      recent_leave_requests: [],
      recent_locator_slips: [],
    },
    'dtr_policy_guidance'
  );
  assert.match(dtrReply, /DTR policy guide/);
  assert.match(dtrReply, /Required DTR logs are based on the employee schedule/i);
  assert.match(dtrReply, /Pending leave or locator requests are not final/i);

  const locatorReply = buildFastEmployeeAssistantReply(
    'what are locator requirements?',
    {
      locator_types: [
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
    },
    'locator_requirements'
  );
  assert.match(locatorReply, /Locator filing requirements/);
  assert.match(locatorReply, /A locator slip needs a slip date/i);
  assert.match(locatorReply, /A locator slip helps DTR only after approval/i);
});

test('DTR assistant regression: how-to-file leave questions show form guidance', () => {
  const reply = buildFastEmployeeAssistantReply(
    'how can I file sick leave?',
    {
      leave_types: [
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
          requires_attachment: false,
        },
      ],
    },
    detectEmployeeAssistantIntent('how can I file sick leave?')
  );

  assert.match(reply, /Leave form guide/);
  assert.match(reply, /Sick Leave/i);
  assert.match(reply, /leave form/i);
  assert.doesNotMatch(reply, /balance is not enough/i);
});

test('DTR assistant regression: Bisaya leave form guidance stays in Bisaya', () => {
  const reply = buildFastEmployeeAssistantReply(
    'unsaon pag file mandatory leave?',
    {
      leave_types: [
        {
          name: 'mandatoryForcedLeave',
          display_name: 'Mandatory/Forced leave',
          employee_can_file: true,
          requires_attachment: false,
        },
      ],
    },
    'leave_form_guidance'
  );

  assert.match(reply, /Giya sa pag-file ug leave/);
  assert.match(reply, /Mao ni gamita/i);
  assert.match(reply, /Pilia ang Mandatory\/Forced leave/i);
  assert.match(reply, /Attachment: walay required attachment/i);
  assert.doesNotMatch(reply, /Use these details/i);
  assert.doesNotMatch(reply, /Requirement:/i);
});

test('DTR assistant regression: leave type list includes short explanations', () => {
  const reply = buildFastEmployeeAssistantReply(
    'what are the leave types i can file?',
    {
      leave_types: [
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
        },
        {
          name: 'maternityLeave',
          display_name: 'Maternity Leave',
          employee_can_file: true,
        },
      ],
    },
    'leave_types'
  );

  assert.match(reply, /Leave types you can file/);
  assert.match(reply, /Sick Leave: Granted when an employee is unable to report/i);
  assert.match(reply, /Maternity Leave: Granted to female employees/i);
  assert.doesNotMatch(reply, /^These are the leave types you can file: Sick Leave, Maternity Leave\.$/);
});

test('DTR assistant regression: broad attachment questions show all matching leave types', () => {
  const reply = buildFastEmployeeAssistantReply(
    'What attachment do I need?',
    {
      leave_types: [
        {
          name: 'tenDayVawcLeave',
          display_name: '10-Day VAWC leave',
          employee_can_file: true,
          requires_attachment: true,
        },
        {
          name: 'adoptionLeave',
          display_name: 'Adoption leave',
          employee_can_file: true,
          requires_attachment: true,
        },
        {
          name: 'maternityLeave',
          display_name: 'Maternity leave',
          employee_can_file: true,
          requires_attachment: true,
        },
        {
          name: 'mandatoryForcedLeave',
          display_name: 'Mandatory/Forced leave',
          employee_can_file: true,
          requires_attachment: false,
        },
        {
          name: 'paternityLeave',
          display_name: 'Paternity leave',
          employee_can_file: true,
          requires_attachment: true,
        },
        {
          name: 'sickLeave',
          display_name: 'Sick leave',
          employee_can_file: true,
          requires_attachment: false,
          requires_attachment_when_over_days: 5,
        },
      ],
    },
    'leave_attachment_requirement'
  );

  assert.match(reply, /10-Day VAWC leave:/);
  assert.match(reply, /Adoption leave:/);
  assert.match(reply, /Maternity leave:/);
  assert.match(reply, /Mandatory\/Forced leave:/);
  assert.match(reply, /Paternity leave:/);
  assert.match(reply, /Sick leave:/);
  assert.doesNotMatch(reply, /Plus \d+ more/);
});

test('DTR assistant regression: leave guideline follow-ups stay in guideline context', () => {
  const memory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'leave_guideline_section',
    text: 'what i mean is the leave guidelines',
    dateRange: {
      label: 'today',
      startDate: '2026-06-18',
      endDate: '2026-06-18',
    },
    modelProfile: 'tools_ollama',
  });

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('okay explain filing deadlines', memory),
    'leave_guideline_section'
  );
  assert.equal(
    assistantServiceTest.clarificationIntentForMessage(
      'okay explain filing deadlines',
      null,
      'leave_guideline_section'
    ),
    null
  );

  const reply = buildFastEmployeeAssistantReply(
    'okay explain filing deadlines',
    {},
    'leave_guideline_section'
  );

  assert.match(reply, /Filing Deadlines/);
  assert.match(reply, /Vacation leave is normally filed in advance/i);
  assert.doesNotMatch(reply, /Which one do you want to file/i);
});

test('DTR assistant regression: leave type guideline overview is supported', () => {
  const reply = buildFastEmployeeAssistantReply(
    'explain me the leave types',
    {
      leave_types: [
        {
          name: 'tenDayVawcLeave',
          display_name: '10-Day VAWC leave',
          employee_can_file: true,
        },
        {
          name: 'adoptionLeave',
          display_name: 'Adoption leave',
          employee_can_file: true,
        },
        {
          name: 'vacationLeave',
          display_name: 'Vacation Leave',
          employee_can_file: true,
        },
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
        },
        {
          name: 'maternityLeave',
          display_name: 'Maternity Leave',
          employee_can_file: true,
        },
        {
          name: 'others',
          display_name: 'Others',
          employee_can_file: true,
        },
        {
          name: 'paternityLeave',
          display_name: 'Paternity leave',
          employee_can_file: true,
        },
        {
          name: 'rehabilitationPrivilege',
          display_name: 'Rehabilitation Privilege',
          employee_can_file: true,
        },
        {
          name: 'soloParentLeave',
          display_name: 'Solo Parent leave',
          employee_can_file: true,
        },
      ],
    },
    'leave_guideline_section'
  );

  assert.match(reply, /Leave Type Guidelines/);
  assert.match(reply, /10-Day VAWC leave:/);
  assert.match(reply, /Adoption leave:/);
  assert.match(reply, /Vacation Leave: Granted to employees for personal recreation/i);
  assert.match(reply, /Sick Leave: Granted when an employee is unable to report/i);
  assert.match(reply, /Maternity Leave: Granted to female employees/i);
  assert.match(reply, /Others:/);
  assert.match(reply, /Paternity leave:/);
  assert.match(reply, /Rehabilitation Privilege:/);
  assert.match(reply, /Solo Parent leave:/);
  assert.doesNotMatch(reply, /Tell me which one you want/i);
  assert.doesNotMatch(reply, /These are the leave types you can file/i);
  assert.doesNotMatch(reply, /Plus \d+ more/);
  assert.ok(reply.length < 2200, `reply length: ${reply.length}`);
});

test('DTR assistant regression: leave guideline catalog fills missing DB leave types', () => {
  const reply = buildFastEmployeeAssistantReply(
    'what are the guidelines of the leave types?',
    {
      leave_types: [
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
        },
      ],
      leave_guideline_catalog: buildAllLeaveGuidelines(),
    },
    'leave_guideline_section'
  );

  assert.match(reply, /Vacation Leave: Granted to employees for personal recreation/i);
  assert.match(reply, /Sick Leave: Granted when an employee is unable to report/i);
  assert.doesNotMatch(reply, /Plus \d+ more/);
});

test('DTR assistant regression: Bisaya leave type guideline replies localize standard descriptions', () => {
  const reply = buildFastEmployeeAssistantReply(
    'what are the guidelines of the leave types? bisayaa daw na',
    {
      leave_types: [
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
        },
      ],
      leave_guideline_catalog: buildAllLeaveGuidelines(),
    },
    'leave_guideline_section'
  );

  assert.match(reply, /Leave Type Guidelines/);
  assert.match(reply, /Mao ni ang guideline summary/i);
  assert.match(reply, /Vacation Leave: Para sa personal nga pahuway/i);
  assert.match(reply, /Sick Leave: Para kung dili ka makareport/i);
  assert.doesNotMatch(reply, /Granted to employees for personal recreation/i);
  assert.doesNotMatch(reply, /Granted when an employee is unable to report/i);
});

test('DTR assistant regression: Bisaya specific leave explanation localizes details', () => {
  const reply = buildFastEmployeeAssistantReply(
    'explain ang sick leave sa bisaya',
    {
      leave_types: [
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
          requires_attachment: false,
          requires_attachment_when_over_days: 5,
        },
      ],
    },
    'leave_guideline_section'
  );

  assert.match(reply, /Sick Leave guideline/i);
  assert.match(reply, /Pasabot: Para kung dili ka makareport/i);
  assert.match(reply, /Medical certificate kasagaran kinahanglan/i);
  assert.doesNotMatch(reply, /unable to report due to personal illness/i);
});

test('DTR assistant regression: specific leave explain questions show guideline details', () => {
  const reply = buildFastEmployeeAssistantReply(
    'explain the sick leave',
    {
      leave_types: [
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
          requires_attachment: false,
          requires_attachment_when_over_days: 5,
        },
      ],
    },
    'leave_guideline_section'
  );

  assert.match(reply, /Sick Leave guideline/i);
  assert.match(reply, /unable to report due to personal illness/i);
  assert.match(reply, /Medical certificate required/i);
  assert.doesNotMatch(reply, /Leave balance/i);
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

  const mistakenDtrMemory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'dtr_status_explanation',
    text: 'how many absents i have for this month?',
    dateRange: {
      label: 'June 9, 2026',
      startDate: '2026-06-09',
      endDate: '2026-06-09',
    },
    modelProfile: 'tools_ollama',
  });

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory(
      'this month not today',
      mistakenDtrMemory
    ),
    'dtr_absent_summary'
  );
  assert.doesNotMatch(
    assistantServiceTest.enrichMessageWithMemory(
      'this month not today',
      mistakenDtrMemory,
      'dtr_absent_summary'
    ),
    /2026-06-09/
  );

  const dailyDtrMemory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'today_dtr',
    text: 'show my DTR today',
    dateRange: {
      label: 'today',
      startDate: '2026-06-15',
      endDate: '2026-06-15',
    },
    modelProfile: 'tools_ollama',
  });
  assert.equal(
    assistantServiceTest.resolveIntentFromMemory(
      'this month not today',
      dailyDtrMemory
    ),
    'dtr_range_summary'
  );
});

test('DTR assistant regression: explain follow-up after leave type list expands the list', () => {
  for (const previousIntent of ['leave_types', 'leave_guideline_section']) {
    const memory = assistantServiceTest.buildNextAssistantMemory(null, {
      intent: previousIntent,
      text: 'explain me the leave types',
      dateRange: {
        label: 'today',
        startDate: '2026-06-15',
        endDate: '2026-06-15',
      },
      modelProfile: 'tools_ollama',
    });

    assert.equal(
      assistantServiceTest.resolveIntentFromMemory('eh explain daw na sila', memory),
      'leave_guideline_section',
      previousIntent
    );

    const enriched = assistantServiceTest.enrichMessageWithMemory(
      'eh explain daw na sila',
      memory,
      'leave_guideline_section'
    );

    assert.match(enriched, /leave types/i, previousIntent);
    assert.match(enriched, /eh explain daw na sila/i, previousIntent);
  }

  const reply = buildFastEmployeeAssistantReply(
    'explain me the leave types (eh explain daw na sila)',
    {
      leave_types: [
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
        },
        {
          name: 'maternityLeave',
          display_name: 'Maternity Leave',
          employee_can_file: true,
        },
      ],
    },
    'leave_guideline_section'
  );

  assert.match(reply, /Leave Type Guidelines/);
  assert.match(reply, /Sick Leave: Granted when an employee is unable to report/i);
  assert.doesNotMatch(reply, /These are the leave types you can file/i);
});

test('DTR assistant regression: all leave types follow-up keeps guideline context', () => {
  const memory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'leave_guideline_section',
    text: 'what are the guidelines of the leave types?',
    dateRange: {
      label: 'today',
      startDate: '2026-06-15',
      endDate: '2026-06-15',
    },
    modelProfile: 'tools_ollama',
  });

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('all leave types', memory),
    'leave_guideline_section'
  );

  const enriched = assistantServiceTest.enrichMessageWithMemory(
    'all leave types',
    memory,
    'leave_guideline_section'
  );

  assert.match(enriched, /guidelines of the leave types/i);
  assert.match(enriched, /all leave types/i);
});

test('DTR assistant regression: language restyle follow-ups keep previous HRMS answer', () => {
  const memory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'leave_attachment_requirement',
    text: 'need med cert if 5 days sick leave?',
    dateRange: {
      label: 'today',
      startDate: '2026-06-15',
      endDate: '2026-06-15',
    },
    leaveType: 'sick',
    modelProfile: 'tools_ollama',
  });

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('bisayaa daw na', memory),
    'leave_attachment_requirement'
  );

  const enriched = assistantServiceTest.enrichMessageWithMemory(
    'bisayaa daw na',
    memory,
    'leave_attachment_requirement'
  );

  assert.match(enriched, /need med cert if 5 days sick leave/i);
  assert.match(enriched, /bisayaa daw na/i);

  const reply = buildFastEmployeeAssistantReply(
    enriched,
    {
      leave_types: [
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
          requires_attachment: false,
          requires_attachment_when_over_days: 5,
        },
      ],
    },
    'leave_attachment_requirement'
  );

  assert.match(reply, /Mao ni ang attachment rule/i);
  assert.match(reply, /kinahanglan ug attachment/i);
  assert.doesNotMatch(reply, /Leave balance/i);

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('tagaloga daw na', memory),
    'leave_attachment_requirement'
  );

  const tagalogEnriched = assistantServiceTest.enrichMessageWithMemory(
    'tagaloga daw na',
    memory,
    'leave_attachment_requirement'
  );

  assert.match(tagalogEnriched, /need med cert if 5 days sick leave/i);
  assert.match(tagalogEnriched, /tagaloga daw na/i);

  const tagalogReply = buildFastEmployeeAssistantReply(
    tagalogEnriched,
    {
      leave_types: [
        {
          name: 'sickLeave',
          display_name: 'Sick Leave',
          employee_can_file: true,
          requires_attachment: false,
          requires_attachment_when_over_days: 5,
        },
      ],
    },
    'leave_attachment_requirement'
  );

  assert.match(tagalogReply, /Ito ang attachment rule/i);
  assert.match(tagalogReply, /kailangan ng attachment/i);
  assert.doesNotMatch(tagalogReply, /Mao ni ang attachment rule/i);
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

  const howToFilingMemory = assistantServiceTest.buildNextAssistantMemory(null, {
    intent: 'clarify_filing_topic',
    text: 'how can I file?',
    dateRange: {
      label: 'today',
      startDate: '2026-06-15',
      endDate: '2026-06-15',
    },
    modelProfile: 'tools_ollama',
  });

  assert.equal(
    assistantServiceTest.resolveIntentFromMemory('sick leave', howToFilingMemory),
    'leave_form_guidance'
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
  assert.equal(feedbackServiceTest.normalizeConfidence('0.82'), 0.82);
  assert.equal(feedbackServiceTest.normalizeConfidence('2'), 1);
  assert.equal(feedbackServiceTest.normalizeConfidence('-1'), 0);
  assert.equal(feedbackServiceTest.normalizeConfidence('bad'), null);
  assert.match(feedbackServiceTest.hashText('pila akong absent?'), /^[a-f0-9]{64}$/);
});

test('DTR assistant regression: replies use friendly dates and day counts', () => {
  const leaveReply = buildFastEmployeeAssistantReply(
    'pila ka leave request nako ang rejected?',
    {
      recent_leave_requests: [
        {
          leave_type: 'Sick leave',
          start_date: '2026-04-01',
          end_date: '2026-04-01',
          status: 'rejected_by_hr',
          days: '1.00',
          hr_remarks: 'dili madawat ang rason',
        },
      ],
    },
    'rejected_leave_requests'
  );

  assert.match(leaveReply, /sa April 1, 2026/);
  assert.match(leaveReply, /1 ka adlaw/);
  assert.doesNotMatch(leaveReply, /1\.00 day\(s\)/);

  const dtrReply = buildFastEmployeeAssistantReply(
    'pila present nako adtong april nga month?',
    {
      date_range: {
        label: 'april 2026',
        startDate: '2026-04-01',
        endDate: '2026-04-02',
      },
      dtr_records: [
        {
          attendance_date: '2026-04-01',
          status: 'present',
          total_hours: 8,
          time_in: '2026-04-01T00:00:00.000Z',
          break_out: '2026-04-01T04:00:00.000Z',
          break_in: '2026-04-01T05:00:00.000Z',
          time_out: '2026-04-01T09:00:00.000Z',
        },
      ],
      dtr_calendar_days: [
        {
          attendance_date: '2026-04-01',
          shift_id: 'shift-1',
          shift_name: 'Morning Shift',
          start_time: '08:00',
          end_time: '17:00',
          working_days: [1, 2, 3, 4, 5],
        },
        {
          attendance_date: '2026-04-02',
          shift_id: 'shift-1',
          shift_name: 'Morning Shift',
          start_time: '08:00',
          end_time: '17:00',
          working_days: [1, 2, 3, 4, 5],
        },
      ],
    },
    'dtr_range_summary'
  );

  assert.match(dtrReply, /April 2026/);
  assert.match(dtrReply, /1 ka present\/complete DTR day/);
  assert.match(dtrReply, /Total hours: 8 hr/);
  assert.doesNotMatch(dtrReply, /8\.00/);
});

test('DTR assistant regression: range DTR status questions summarize the full range', () => {
  const reply = buildFastEmployeeAssistantReply(
    'unsa akong dtr status adtun first week sa june?',
    {
      date_range: {
        label: 'first week of june',
        startDate: '2026-06-01',
        endDate: '2026-06-07',
      },
      dtr_records: [
        {
          attendance_date: '2026-06-02',
          status: 'absent',
          total_hours: 0,
          late_minutes: 0,
          undertime_minutes: 480,
        },
        {
          attendance_date: '2026-06-03',
          status: 'present',
          total_hours: 8,
          late_minutes: 0,
          undertime_minutes: 0,
        },
      ],
      dtr_calendar_days: [],
    },
    'dtr_status_explanation'
  );

  assert.match(reply, /DTR summary/i);
  assert.match(reply, /first week of june/i);
  assert.match(reply, /Saved DTR rows: 2/i);
  assert.match(reply, /Present\/complete days: 1/i);
  assert.match(reply, /Absent\/no-record days: 1/i);
  assert.doesNotMatch(reply, /DTR explanation for June 2, 2026/i);
});

test('DTR assistant regression: current shift reply is direct and friendly', () => {
  const reply = buildFastEmployeeAssistantReply(
    'what is my current shift?',
    {
      date_range: {
        label: 'today',
        startDate: '2026-06-18',
        endDate: '2026-06-18',
      },
      dtr_calendar_days: [
        {
          attendance_date: '2026-06-18',
          shift_id: 'shift-1',
          shift_name: 'Morning Shift',
          start_time: '08:00:00',
          end_time: '17:00:00',
          grace_period_minutes: 5,
          working_days: [1, 2, 3, 4, 5],
        },
      ],
    },
    'dtr_schedule_context'
  );

  assert.match(reply, /Your current shift is Morning Shift, 8:00 AM-5:00 PM/);
  assert.match(reply, /Expected logs: AM in, AM out, PM in, PM out/);
  assert.doesNotMatch(reply, /schedule\/holiday day/i);
  assert.doesNotMatch(reply, /08:00:00-17:00:00/);
});

test('DTR assistant regression: action metadata is generated for next-step work', () => {
  const leaveActions = assistantServiceTest.buildActions(
    'leave_availability_check',
    {
      date_range: {
        label: 'tomorrow',
        startDate: '2026-06-16',
        endDate: '2026-06-16',
      },
    },
    'can I file 1 day vacation leave tomorrow?',
    []
  );
  assert.equal(leaveActions[0].type, 'open_leave_form');
  assert.equal(leaveActions[0].payload.leaveType, 'vacation');
  assert.equal(leaveActions[0].payload.startDate, '2026-06-16');

  const locatorActions = assistantServiceTest.buildActions(
    'locator_availability_check',
    {
      date_range: {
        label: 'tomorrow',
        startDate: '2026-06-16',
        endDate: '2026-06-16',
      },
    },
    'can I file WFH tomorrow?',
    []
  );
  assert.equal(locatorActions[0].type, 'open_locator_form');
  assert.equal(locatorActions[0].payload.locatorType, 'work_from_home');

  const dtrActions = assistantServiceTest.buildActions(
    'dtr_missing_log_reason',
    {
      date_range: {
        label: 'June 10, 2026',
        startDate: '2026-06-10',
        endDate: '2026-06-10',
      },
      dtr_records: [
        {
          attendance_date: '2026-06-10',
          status: 'incomplete',
          time_in: '2026-06-10T00:00:00.000Z',
          break_out: '2026-06-10T04:00:00.000Z',
          break_in: '2026-06-10T05:00:00.000Z',
          time_out: null,
        },
      ],
    },
    'why is my dtr incomplete?',
    []
  );
  assert.equal(dtrActions[0].type, 'open_dtr_time_logs');
  assert.equal(dtrActions[1].type, 'send_prompt');
  assert.match(dtrActions[1].prompt, /PM out on 2026-06-10/);

  const exportActions = assistantServiceTest.buildActions(
    'dtr_export_guidance',
    {},
    'export my dtr',
    [
      {
        id: 'export-1',
        filename: 'dtr.xls',
        downloadUrl: '/api/dtr-assistant/exports/export-1',
      },
    ]
  );
  assert.equal(exportActions[0].type, 'download_attachment');
});

test('DTR assistant regression: direct open commands generate auto navigation actions', () => {
  const locatorCommand =
    assistantServiceTest.directOpenCommandForMessage('open my locator request');
  assert.equal(locatorCommand.intent, 'locator_status');
  assert.equal(locatorCommand.actions.length, 1);
  assert.equal(locatorCommand.actions[0].type, 'open_locator_page');
  assert.equal(locatorCommand.actions[0].autoExecute, true);
  assert.doesNotMatch(locatorCommand.content, /approved|pending|rejected/i);

  const leaveCommand =
    assistantServiceTest.directOpenCommandForMessage('open leave form');
  assert.equal(leaveCommand.intent, 'leave_guided_filing');
  assert.equal(leaveCommand.actions[0].type, 'open_leave_form');
  assert.equal(leaveCommand.actions[0].autoExecute, true);

  const attendanceCommand =
    assistantServiceTest.directOpenCommandForMessage('open my attendance');
  assert.equal(attendanceCommand.intent, 'dtr_daily_record');
  assert.equal(attendanceCommand.actions[0].type, 'open_dtr_time_logs');
  assert.equal(attendanceCommand.actions[0].label, 'Open My Attendance');
  assert.equal(attendanceCommand.actions[0].autoExecute, true);

  const question =
    assistantServiceTest.directOpenCommandForMessage('what are locator types?');
  assert.equal(question, null);
});
