const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getDtrAssistantModelProfiles,
  __test: assistantServiceTest,
} = require('../src/services/dtrAssistant/dtrAssistantService');
const {
  buildDtrAssistantToolAnswerMessages,
} = require('../src/services/dtrAssistant/dtrAssistantPrompt');
const {
  EXTERNAL_AI_CONSENT_VERSION,
  assertExternalConsent,
  buildExternalDirectContext,
  buildExternalToolData,
  disclosureEvent,
} = require('../src/services/dtrAssistant/dtrAssistantExternalDataPolicy');

function contextFixture() {
  return {
    date_range: {
      label: 'August 2026',
      startDate: '2026-08-01',
      endDate: '2026-08-31',
    },
    employee: {
      id: 'employee-1',
      full_name: 'Edgar Employee',
      sex: 'male',
      civil_status: 'married',
      date_of_birth: '1990-01-01',
    },
    dtr_records: [
      {
        id: 'dtr-1',
        attendance_date: '2026-08-14',
        time_in: '2026-08-14T08:00:00+08:00',
        time_out: '2026-08-14T17:00:00+08:00',
        status: 'present',
        remarks: 'Private correction note',
      },
    ],
    dtr_calendar_days: [
      {
        attendance_date: '2026-08-14',
        assignment_id: 'assignment-1',
        shift_id: 'shift-1',
        shift_name: 'Day Shift',
        start_time: '08:00:00',
        end_time: '17:00:00',
      },
    ],
    dtr_policies: [{ code: 'late', summary: 'Late arrivals are recorded.' }],
    leave_balances: [
      {
        leave_type: 'vacationLeave',
        remaining_days: 8,
        available_days: 7,
      },
    ],
    recent_leave_requests: [
      {
        id: 'leave-1',
        leave_type: 'Sick Leave',
        start_date: '2026-08-10',
        end_date: '2026-08-10',
        days: 1,
        status: 'rejected',
        reason: 'Private medical diagnosis',
        details: { diagnosis: 'Private diagnosis' },
        attachment_name: 'medical-certificate.pdf',
        attachment_path: '/private/medical-certificate.pdf',
        disapproval_reason: 'Certificate needs a visible date.',
        reviewer_remarks: 'Please upload a clearer copy.',
        history: [{ remarks: 'Internal reviewer history' }],
      },
    ],
    leave_annual_usage: [{ leave_type_key: 'soloParentLeave', days: 2 }],
    leave_types: [
      {
        id: 'leave-type-1',
        name: 'sickLeave',
        display_name: 'Sick Leave',
        description: 'For illness.',
        requires_attachment: true,
      },
    ],
    leave_guidelines: [{ leaveType: 'Sick Leave', filing: 'Use the leave form.' }],
    leave_guideline_catalog: [],
    recent_locator_slips: [
      {
        id: 'locator-1',
        slip_date: '2026-08-12',
        request_type: 'locator',
        request_type_label: 'Official Business',
        office: 'Private destination',
        reason: 'Private meeting details',
        status: 'rejected',
        hr_remarks: 'Destination was not specific.',
      },
    ],
    locator_types: [
      { id: 'locator-type-1', code: 'locator', label: 'Official Business' },
    ],
    locator_policies: [{ code: 'approval', summary: 'Approval is required.' }],
    assistant_extraction: { leaveType: 'sickLeave' },
  };
}

function dataSentToModel(toolData) {
  const messages = buildDtrAssistantToolAnswerMessages({
    message: 'Test question',
    intent: 'test_intent',
    toolAnswer: 'Test answer',
    toolData,
  });
  const payload = JSON.parse(
    messages[1].content.replace(/\n\/no_think$/, '')
  );
  return payload.HRMS_TOOL_RESULT.data;
}

function assertIntentContracts(builder, groups) {
  const context = contextFixture();
  for (const group of groups) {
    for (const intent of group.intents) {
      const sent = dataSentToModel(builder(intent, context));
      assert.deepEqual(
        Object.keys(sent).sort(),
        [...group.keys].sort(),
        `${intent} sent an unexpected data category`
      );
    }
  }
  assert.deepEqual(dataSentToModel(builder('unknown', context)), {});
}

test('external model profiles require both administrator policy and consent metadata', () => {
  const disabled = getDtrAssistantModelProfiles({
    GROQ_API_KEY: 'configured-test-key',
  });
  assert.equal(disabled.models.find((item) => item.id === 'tools_groq').available, false);
  assert.match(
    disabled.models.find((item) => item.id === 'tools_groq').unavailableReason,
    /disabled by the HRMS administrator/i
  );

  const enabled = getDtrAssistantModelProfiles({
    GROQ_API_KEY: 'configured-test-key',
    DTR_ASSISTANT_ALLOW_EXTERNAL_LLM: 'true',
    DTR_ASSISTANT_ALLOW_DIRECT_LLM: 'true',
  });
  const groq = enabled.models.find((item) => item.id === 'tools_groq');
  const direct = enabled.models.find((item) => item.id === 'direct_groq');
  assert.equal(groq.available, true);
  assert.equal(groq.external, true);
  assert.equal(groq.requiresConsent, true);
  assert.equal(groq.consentVersion, EXTERNAL_AI_CONSENT_VERSION);
  assert.equal(direct.available, true);
});

test('external profiles reject missing or outdated consent versions', () => {
  const profile = { external: true };
  assert.throws(
    () => assertExternalConsent(profile, null),
    (error) =>
      error.statusCode === 400 && error.code === 'EXTERNAL_AI_CONSENT_REQUIRED'
  );
  assert.throws(
    () => assertExternalConsent(profile, 'old-version'),
    (error) => error.code === 'EXTERNAL_AI_CONSENT_REQUIRED'
  );
  assert.doesNotThrow(() =>
    assertExternalConsent(profile, EXTERNAL_AI_CONSENT_VERSION)
  );
  assert.doesNotThrow(() => assertExternalConsent({ external: false }, null));
});

test('external DTR policy payload excludes employee records and other HR domains', () => {
  const data = buildExternalToolData('dtr_policy_guidance', contextFixture());
  assert.deepEqual(Object.keys(data).sort(), ['dateRange', 'dtrPolicies']);
  assert.equal(JSON.stringify(data).includes('Private medical diagnosis'), false);
  assert.equal(JSON.stringify(data).includes('Private meeting details'), false);
});

test('external review payload keeps required decision remarks but removes private filing data', () => {
  const data = buildExternalToolData('leave_rejection_reason', contextFixture());
  const serialized = JSON.stringify(data);
  assert.match(serialized, /Certificate needs a visible date/);
  assert.match(serialized, /Please upload a clearer copy/);
  assert.doesNotMatch(serialized, /Private medical diagnosis/);
  assert.doesNotMatch(serialized, /Private diagnosis/);
  assert.doesNotMatch(serialized, /medical-certificate\.pdf/);
  assert.doesNotMatch(serialized, /Internal reviewer history/);
});

test('external direct context contains policies and catalogs but no employee records', () => {
  const data = buildExternalDirectContext(contextFixture());
  const serialized = JSON.stringify(data);
  assert.deepEqual(Object.keys(data).sort(), [
    'dateRange',
    'dtrPolicies',
    'leaveGuidelines',
    'leaveTypes',
    'locatorPolicies',
    'locatorTypes',
  ]);
  assert.doesNotMatch(serialized, /Edgar Employee|1990-01-01|Private/);
  assert.doesNotMatch(serialized, /employee-1|leave-1|locator-1|dtr-1/);
});

test('external disclosure audit metadata contains categories, not raw HR values', () => {
  const event = disclosureEvent({
    userId: 'employee-1',
    profile: { provider: 'groq', id: 'tools_groq' },
    purpose: 'tool_answer_refinement',
    intent: 'leave_balance',
    data: { balances: [{ available_days: 7 }] },
  });
  const serialized = JSON.stringify(event);
  assert.deepEqual(event.dataCategories, ['balances']);
  assert.match(event.subjectHash, /^[a-f0-9]{16}$/);
  assert.doesNotMatch(serialized, /employee-1|available_days|\"7\"/);
});

test('local tool profiles send the exact data categories for every intent family', () => {
  assertIntentContracts(assistantServiceTest.buildToolData, [
    { intents: ['today_dtr'], keys: ['dateRange', 'record'] },
    {
      intents: [
        'missing_logs',
        'dtr_daily_record',
        'dtr_range_summary',
        'dtr_missing_logs',
        'dtr_missing_log_reason',
        'dtr_late_summary',
        'dtr_late_reason',
        'dtr_undertime_summary',
        'dtr_overtime_summary',
        'dtr_absent_summary',
        'dtr_status_explanation',
        'dtr_correction_guidance',
        'dtr_leave_coverage_check',
        'dtr_locator_coverage_check',
        'dtr_holiday_check',
        'dtr_schedule_context',
        'dtr_export_guidance',
        'dtr_policy_guidance',
      ],
      keys: [
        'dateRange',
        'records',
        'calendarDays',
        'leaveRequests',
        'locatorSlips',
        'dtrPolicies',
        'locatorPolicies',
      ],
    },
    {
      intents: ['leave_balance', 'leave_balance_projection'],
      keys: ['balances'],
    },
    {
      intents: ['dtr_hours_summary'],
      keys: ['dateRange', 'records'],
    },
    {
      intents: [
        'pending_leave_requests',
        'approved_leave_requests',
        'rejected_leave_requests',
        'leave_history',
        'leave_overlap_check',
        'leave_pending_days_explanation',
        'leave_request_summary',
        'leave_rejection_reason',
        'leave_approval_tracker',
        'leave_approval_history',
        'leave_request_lookup',
      ],
      keys: ['dateRange', 'requests'],
    },
    {
      intents: ['leave_availability_check', 'leave_balance_after_filing'],
      keys: [
        'employee',
        'balances',
        'requests',
        'annualUsage',
        'leaveTypes',
        'leaveGuidelines',
        'leaveGuidelineCatalog',
        'extraction',
      ],
    },
    {
      intents: [
        'leave_types',
        'leave_attachment_requirement',
        'leave_filing_policy',
        'leave_form_guidance',
        'leave_form_field_help',
        'leave_eligibility_check',
        'leave_dtr_impact',
        'leave_guideline_section',
        'leave_type_compare',
        'leave_guided_filing',
      ],
      keys: [
        'employee',
        'balances',
        'requests',
        'leaveTypes',
        'leaveGuidelines',
        'leaveGuidelineCatalog',
      ],
    },
    {
      intents: ['leave_requirements'],
      keys: ['leaveTypes', 'leaveGuidelines', 'leaveGuidelineCatalog'],
    },
    { intents: ['latest_leave_request'], keys: ['request'] },
    {
      intents: ['latest_locator_request'],
      keys: ['slip', 'locatorTypes'],
    },
    {
      intents: [
        'locator_status',
        'locator_summary',
        'locator_types',
        'locator_requirements',
        'locator_form_field_help',
        'locator_guided_filing',
        'locator_availability_check',
        'locator_rejection_reason',
        'locator_approval_tracker',
      ],
      keys: [
        'dateRange',
        'slips',
        'locatorTypes',
        'locatorPolicies',
        'dtrRecords',
        'calendarDays',
        'dtrPolicies',
      ],
    },
  ]);
});

test('cloud tool profiles send the exact allowlisted categories for every intent family', () => {
  assertIntentContracts(buildExternalToolData, [
    { intents: ['today_dtr'], keys: ['dateRange', 'record'] },
    {
      intents: ['dtr_policy_guidance', 'dtr_export_guidance'],
      keys: ['dateRange', 'dtrPolicies'],
    },
    {
      intents: ['dtr_holiday_check', 'dtr_schedule_context'],
      keys: ['dateRange', 'calendarDays', 'dtrPolicies'],
    },
    {
      intents: ['dtr_leave_coverage_check'],
      keys: ['dateRange', 'records', 'calendarDays', 'leaveRequests'],
    },
    {
      intents: ['dtr_locator_coverage_check'],
      keys: [
        'dateRange',
        'records',
        'calendarDays',
        'locatorSlips',
        'locatorPolicies',
      ],
    },
    {
      intents: [
        'missing_logs',
        'dtr_daily_record',
        'dtr_range_summary',
        'dtr_missing_logs',
        'dtr_missing_log_reason',
        'dtr_late_summary',
        'dtr_late_reason',
        'dtr_undertime_summary',
        'dtr_overtime_summary',
        'dtr_absent_summary',
        'dtr_status_explanation',
        'dtr_correction_guidance',
        'dtr_hours_summary',
      ],
      keys: ['dateRange', 'records', 'calendarDays', 'dtrPolicies'],
    },
    {
      intents: ['leave_balance', 'leave_balance_projection'],
      keys: ['balances'],
    },
    {
      intents: [
        'leave_rejection_reason',
        'leave_approval_tracker',
        'leave_approval_history',
      ],
      keys: ['dateRange', 'requests'],
    },
    {
      intents: [
        'pending_leave_requests',
        'approved_leave_requests',
        'rejected_leave_requests',
        'leave_history',
        'leave_overlap_check',
        'leave_pending_days_explanation',
        'leave_request_summary',
        'leave_request_lookup',
        'latest_leave_request',
      ],
      keys: ['dateRange', 'requests'],
    },
    {
      intents: ['leave_availability_check', 'leave_balance_after_filing'],
      keys: [
        'balances',
        'requests',
        'annualUsage',
        'leaveTypes',
        'leaveGuidelines',
        'extraction',
      ],
    },
    {
      intents: [
        'leave_types',
        'leave_attachment_requirement',
        'leave_filing_policy',
        'leave_form_guidance',
        'leave_form_field_help',
        'leave_eligibility_check',
        'leave_dtr_impact',
        'leave_guideline_section',
        'leave_type_compare',
        'leave_guided_filing',
        'leave_requirements',
      ],
      keys: [
        'balances',
        'leaveTypes',
        'leaveGuidelines',
        'leaveGuidelineCatalog',
      ],
    },
    {
      intents: ['locator_rejection_reason', 'locator_approval_tracker'],
      keys: [
        'dateRange',
        'slips',
        'locatorTypes',
        'locatorPolicies',
      ],
    },
    {
      intents: [
        'latest_locator_request',
        'locator_status',
        'locator_summary',
        'locator_types',
        'locator_requirements',
        'locator_form_field_help',
        'locator_guided_filing',
        'locator_availability_check',
      ],
      keys: [
        'dateRange',
        'slips',
        'locatorTypes',
        'locatorPolicies',
      ],
    },
  ]);
});

test('cloud nested records exclude fields outside the allowlist before prompt creation', () => {
  const sent = dataSentToModel(
    buildExternalToolData('dtr_leave_coverage_check', contextFixture())
  );
  assert.deepEqual(Object.keys(sent.records[0]).sort(), [
    'attendance_date',
    'status',
    'time_in',
    'time_out',
  ]);
  assert.deepEqual(Object.keys(sent.leaveRequests[0]).sort(), [
    'days',
    'end_date',
    'leave_type',
    'start_date',
    'status',
  ]);
});
