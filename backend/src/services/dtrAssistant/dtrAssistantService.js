const crypto = require('crypto');
const { chatCompletion } = require('../llm/llmClient');
const { getLlmConfig } = require('../llm/llmConfig');
const { loadEmployeeAssistantContext } = require('./dtrAssistantDataService');
const {
  assistantGreetingReply,
  buildFastEmployeeAssistantReply,
  requestedLeaveType,
  requestedLocatorType,
} = require('./dtrAssistantFastReply');
const {
  getAssistantMemory,
  setAssistantMemory,
  clearAssistantMemory,
} = require('./dtrAssistantMemoryService');
const {
  buildLeaveActionPayload,
  buildLocatorActionPayload,
  mergePrefill,
  nextTopicPrefill,
} = require('./dtrAssistantActionPrefill');
const {
  extractMessageEntities,
  extractDayCount,
  mergePlannerExtraction,
  normalizePlannerExtraction,
} = require('./dtrAssistantMessageExtraction');
const {
  combineMultiIntentReplies,
  detectMultipleIntents,
} = require('./dtrAssistantMultiIntent');
const {
  applyPendingClarificationAnswer,
  evaluateGuidedClarification,
} = require('./dtrAssistantGuidedClarification');
const {
  normalizeIntent,
  scoreEmployeeAssistantIntent,
} = require('./dtrAssistantIntentService');
const { getEmployeeSelfScope } = require('./dtrAssistantPermissionService');
const { normalizeAssistantMessageForRules } = require('./dtrAssistantTextNormalizer');
const { getLeaveFormFieldKey } = require('./leaveFilingGuidelines');
const { getLocatorFormFieldKey, isLocatorFormFieldHelpQuestion } = require('./locatorFilingGuidelines');
const {
  buildDtrAssistantDirectMessages,
  buildDtrAssistantIntentMessages,
  buildDtrAssistantToolPlanMessages,
  buildDtrAssistantToolAnswerMessages,
} = require('./dtrAssistantPrompt');
const { createDtrExportAttachment } = require('./dtrAssistantExportService');
const {
  addDays,
  parseAssistantDateRange,
  todayInHrmsTimezone,
} = require('../../utils/dateRangeParser');

const MAX_ASSISTANT_REPLY_CHARS = 4000;
const MAX_MEMORY_TURNS = 6;

const DEFAULT_MODEL_PROFILE_ID = 'tools_ollama';

function allowDirectLlm(env = process.env) {
  return /^(1|true|yes)$/i.test(String(env.DTR_ASSISTANT_ALLOW_DIRECT_LLM || ''));
}

function buildModelProfiles(env = process.env) {
  const config = getLlmConfig(env);
  const groqConfigured = !!config.groq.apiKey;
  const directEnabled = groqConfigured && allowDirectLlm(env);

  return [
    {
      id: 'tools_ollama',
      label: `Qwen + HRMS tools`,
      description: 'Safest: DB tools get exact HRMS facts, Qwen only refines language.',
      engine: 'tools',
      provider: 'ollama',
      model: config.ollama.model,
      available: true,
      recommended: true,
    },
    {
      id: 'tools_groq',
      label: 'Groq + HRMS tools',
      description: 'Fast API refinement while DB tools still protect exact HRMS facts.',
      engine: 'tools',
      provider: 'groq',
      model: config.groq.model,
      available: groqConfigured,
      recommended: false,
      unavailableReason: groqConfigured ? null : 'Set GROQ_API_KEY in backend/.env.',
    },
    {
      id: 'direct_groq',
      label: 'Groq direct',
      description: 'Experimental: Groq reasons over the HRMS context directly.',
      engine: 'direct',
      provider: 'groq',
      model: config.groq.model,
      available: directEnabled,
      recommended: false,
      unavailableReason: directEnabled
        ? null
        : groqConfigured
          ? 'Set DTR_ASSISTANT_ALLOW_DIRECT_LLM=true to enable direct mode.'
          : 'Set GROQ_API_KEY in backend/.env.',
    },
  ];
}

function getDtrAssistantModelProfiles(env = process.env) {
  const models = buildModelProfiles(env);
  return {
    defaultModelProfile: DEFAULT_MODEL_PROFILE_ID,
    models,
  };
}

function resolveModelProfile(modelProfileId, env = process.env) {
  const profiles = buildModelProfiles(env);
  const requested = String(modelProfileId || DEFAULT_MODEL_PROFILE_ID).trim();
  const profile =
    profiles.find((item) => item.id === requested) ||
    profiles.find((item) => item.id === DEFAULT_MODEL_PROFILE_ID);

  if (!profile.available) {
    const err = new Error(profile.unavailableReason || 'Selected assistant model is unavailable.');
    err.statusCode = 400;
    err.code = 'ASSISTANT_MODEL_UNAVAILABLE';
    throw err;
  }

  return profile;
}

function lower(value) {
  return String(value || '').toLowerCase();
}

function normalizeMessage(message) {
  const text = String(message || '').replace(/\s+/g, ' ').trim();
  if (!text) {
    const err = new Error('message is required');
    err.statusCode = 400;
    throw err;
  }
  if (text.length > 2000) {
    const err = new Error('message is too long');
    err.statusCode = 400;
    throw err;
  }
  return text;
}

function buildSources(context) {
  return {
    dateRange: context.date_range,
    dtrSummaryIds: (context.dtr_records || []).map((r) => r.id),
    leaveRequestIds: (context.recent_leave_requests || []).map((r) => r.id),
    locatorSlipIds: (context.recent_locator_slips || []).map((r) => r.id),
    dtrPolicyKeys: (context.dtr_policies || []).map((item) => item.key),
    locatorPolicyKeys: (context.locator_policies || []).map((item) => item.key),
  };
}

function emptyAssistantContext(dateRange = null) {
  return {
    date_range: dateRange || null,
    dtr_records: [],
    recent_leave_requests: [],
    recent_locator_slips: [],
  };
}

function compactAssistantContent(content) {
  const text = String(content || '')
    .replace(/\r\n/g, '\n')
    .split('\n')
    .map((line) => line.replace(/[ \t]+/g, ' ').trim())
    .filter(Boolean)
    .join('\n')
    .trim();
  if (text.length <= MAX_ASSISTANT_REPLY_CHARS) return text;
  return `${text.slice(0, MAX_ASSISTANT_REPLY_CHARS - 3).trim()}...`;
}

function isStructuredDtrIntent(intent) {
  return (
    intent === 'today_dtr' ||
    intent === 'missing_logs' ||
    /^dtr_/.test(String(intent || ''))
  );
}

function isLeaveIntent(intent) {
  const value = String(intent || '');
  return (
    value === 'leave_balance' ||
    value === 'pending_leave_requests' ||
    value === 'approved_leave_requests' ||
    value === 'rejected_leave_requests' ||
    value === 'latest_leave_request' ||
    /^leave_/.test(value)
  );
}

function isLocatorIntent(intent) {
  const value = String(intent || '');
  return (
    value === 'latest_locator_request' ||
    value === 'locator_status' ||
    value === 'locator_summary' ||
    value === 'locator_types' ||
    value === 'locator_requirements' ||
    value === 'locator_form_field_help' ||
    value === 'locator_guided_filing' ||
    value === 'locator_availability_check' ||
    value === 'locator_rejection_reason' ||
    value === 'locator_approval_tracker'
  );
}

function topicForIntent(intent) {
  if (isStructuredDtrIntent(intent)) return 'dtr';
  if (isLeaveIntent(intent)) return 'leave';
  if (isLocatorIntent(intent)) return 'locator';
  if (
    intent === 'clarify_filing_topic' ||
    intent === 'clarify_status_topic'
  ) {
    return 'clarify';
  }
  if (intent === 'direct_ai') return 'direct';
  return null;
}

function explicitTopicFromText(text) {
  const value = lower(text);
  if (/\b(locator|locator slip|pass slip|wfh|work from home|official business|ob|fieldwork|field work|out of office|travel order)\b/.test(value)) {
    return 'locator';
  }
  if (/\b(leave|leaves|sick|vacation|paternity|maternity|adoption|solo parent|vawc|calamity|mandatory|forced|vl|sl)\b/.test(value)) {
    return 'leave';
  }
  if (/\b(dtr|attendance|daily time|log|logs|time[\s-]?in|time[\s-]?out|late|undertime|overtime|absent|absence|present|shift|schedule|sched|missing|incomplete)\b/.test(value)) {
    return 'dtr';
  }
  return null;
}

function memoryTopicState(memory, intentOrTopic) {
  if (!memory) return null;
  const topic =
    ['dtr', 'leave', 'locator', 'clarify', 'direct'].includes(String(intentOrTopic || ''))
      ? intentOrTopic
      : topicForIntent(intentOrTopic || memory.intent);
  if (!topic) return memory;
  return memory.topics?.[topic] || (memory.topic === topic ? memory : null) || memory;
}

function strictMemoryTopicState(memory, topic) {
  if (!memory || !topic) return null;
  return memory.topics?.[topic] || (memory.topic === topic ? memory : null);
}

function requestedSpecificLocatorTypeForMemory(text) {
  const type = requestedLocatorType(text);
  if (type !== 'locator') return type;
  return /\b(official business|official|business|ob|on field|field|fieldwork|field work|out of office|outside office|travel order)\b/i.test(
    text
  )
    ? 'locator'
    : null;
}

function isBroadLocatorSummaryRequest(intent, text) {
  if (intent !== 'locator_summary') return false;
  if (requestedSpecificLocatorTypeForMemory(text)) return false;
  return /\b(summary|total|count|counts|pila|kabuok|ilan|how many|history|list|show|accepted|approved|pending|rejected)\b/i.test(
    text
  );
}

function memoryLeaveTypeForIntent(intent, effectiveText, context, memory) {
  if (!isLeaveIntent(intent)) return null;
  const leaveMemory = memoryTopicState(memory, 'leave');
  return (
    requestedLeaveType(effectiveText) ||
    inferLeaveTypeFromContext(effectiveText, context) ||
    leaveMemory?.leaveType ||
    memory?.leaveType ||
    null
  );
}

function memoryLocatorTypeForIntent(intent, effectiveText, memory) {
  if (!isLocatorIntent(intent)) return null;
  const locatorMemory = memoryTopicState(memory, 'locator');
  const requestedType = requestedSpecificLocatorTypeForMemory(effectiveText);
  if (requestedType) return requestedType;
  if (isBroadLocatorSummaryRequest(intent, effectiveText)) return null;
  return (
    locatorMemory?.locatorType ||
    memory?.locatorType ||
    null
  );
}

function memoryWithClarificationPatch(memory, patch) {
  if (!patch) return memory;
  const base = memory || {};
  return {
    ...base,
    leaveType: patch.leaveType || base.leaveType || null,
    locatorType: patch.locatorType || base.locatorType || null,
    dateRange: patch.dateRange || base.dateRange || null,
    pendingClarification: patch.pendingClarification ?? base.pendingClarification ?? null,
    dayCount: patch.dayCount ?? base.dayCount ?? null,
    leavePrefill: patch.leavePrefill
      ? mergePrefill(base.leavePrefill || {}, patch.leavePrefill)
      : base.leavePrefill || null,
    locatorPrefill: patch.locatorPrefill
      ? mergePrefill(base.locatorPrefill || {}, patch.locatorPrefill)
      : base.locatorPrefill || null,
  };
}

function buildNextAssistantMemory(previous, next) {
  const topic = topicForIntent(next.intent);
  const previousTopicState = strictMemoryTopicState(previous, topic) || {};
  const shouldCarryPreviousLocatorType =
    topic === 'locator' && !isBroadLocatorSummaryRequest(next.intent, next.text);
  const leaveType =
    next.leaveType || (topic === 'leave' ? previousTopicState.leaveType : previous?.leaveType) || null;
  const locatorType =
    next.locatorType ||
    (shouldCarryPreviousLocatorType ? previousTopicState.locatorType : null) ||
    (topic !== 'locator' ? previous?.locatorType : null) ||
    null;
  const turn = {
    intent: next.intent || null,
    topic,
    text: String(next.text || '').slice(0, 500),
    dateRange: next.dateRange || null,
    leaveType,
    locatorType,
    modelProfile: next.modelProfile || null,
    createdAt: new Date().toISOString(),
  };
  const history = [turn, ...(previous?.history || [])]
    .filter((item) => item && item.intent)
    .slice(0, MAX_MEMORY_TURNS);
  const topics = {
    ...(previous?.topics || {}),
  };

  if (topic) {
    const leavePrefill =
      topic === 'leave' ? nextTopicPrefill('leave', next.text, previous, previousTopicState) : null;
    const locatorPrefill =
      topic === 'locator' ? nextTopicPrefill('locator', next.text, previous, previousTopicState) : null;
    topics[topic] = {
      intent: next.intent || previousTopicState.intent || null,
      topic,
      text: turn.text || previousTopicState.text || null,
      dateRange: next.dateRange || previousTopicState.dateRange || null,
      leaveType: topic === 'leave' ? leaveType : previousTopicState.leaveType || null,
      locatorType: topic === 'locator' ? locatorType : previousTopicState.locatorType || null,
      leavePrefill:
        topic === 'leave'
          ? leavePrefill || previousTopicState.leavePrefill || null
          : previousTopicState.leavePrefill || null,
      locatorPrefill:
        topic === 'locator'
          ? locatorPrefill || previousTopicState.locatorPrefill || null
          : previousTopicState.locatorPrefill || null,
      toolData: next.toolData || previousTopicState.toolData || null,
      updatedAt: turn.createdAt,
    };
  }

  return {
    intent: next.intent || previous?.intent || null,
    topic,
    leaveType,
    locatorType,
    leavePrefill:
      topic === 'leave'
        ? topics.leave?.leavePrefill || previous?.leavePrefill || null
        : previous?.leavePrefill || null,
    locatorPrefill:
      topic === 'locator'
        ? topics.locator?.locatorPrefill || previous?.locatorPrefill || null
        : previous?.locatorPrefill || null,
    dateRange: next.dateRange || previous?.dateRange || null,
    toolData: next.toolData || null,
    modelProfile: next.modelProfile || previous?.modelProfile || null,
    pendingClarification:
      next.pendingClarification !== undefined
        ? next.pendingClarification
        : previous?.pendingClarification || null,
    lastUserMessage: turn.text,
    history,
    topics,
  };
}

function shouldSkipToolRefinement(intent) {
  return isStructuredDtrIntent(intent) || isLeaveIntent(intent) || isLocatorIntent(intent);
}

function normalizedText(value) {
  return lower(value).replace(/[^a-z0-9]+/g, '');
}

function inferLeaveTypeFromContext(text, context) {
  const normalizedMessage = normalizedText(text);
  if (!normalizedMessage) return null;

  let best = null;
  let bestScore = 0;
  for (const type of context.leave_types || []) {
    const label = `${type.display_name || ''} ${type.name || ''} ${type.description || ''}`;
    const normalizedLabel = normalizedText(label);
    if (!normalizedLabel) continue;

    const words = lower(label)
      .split(/[^a-z0-9]+/)
      .filter((word) => word.length >= 3 && word !== 'leave');
    const uniqueWords = [...new Set(words)];
    const score = uniqueWords.reduce((total, word) => {
      return total + (normalizedMessage.includes(word) ? 1 : 0);
    }, normalizedMessage.includes(normalizedLabel) ? 3 : 0);

    if (score > bestScore) {
      best = type;
      bestScore = score;
    }
  }

  return bestScore > 0 ? best.display_name || best.name || null : null;
}

function buildSuggestions(intent) {
  if (intent === 'dtr_hours_summary') {
    return [
      { text: 'Show my late days this month', intent: 'dtr_late_summary' },
      { text: 'Show undertime this month', intent: 'dtr_undertime_summary' },
      { text: 'Show missing logs this week', intent: 'dtr_missing_logs' },
    ];
  }
  if (intent === 'leave_balance_projection') {
    return [
      { text: 'What is my leave balance?', intent: 'leave_balance' },
      { text: 'Can I file sick leave tomorrow?', intent: 'leave_availability_check' },
      { text: 'Show leave requirements', intent: 'leave_requirements' },
    ];
  }
  if (intent === 'leave_form_field_help') {
    return [
      {
        text: 'What should I put in the reason field?',
        intent: 'leave_form_field_help',
      },
      {
        text: 'Give me an example for the location field',
        intent: 'leave_form_field_help',
      },
      {
        text: 'What attachment should I upload?',
        intent: 'leave_form_field_help',
      },
    ];
  }
  if (intent === 'locator_form_field_help') {
    return [
      {
        text: 'What should I put in the locator reason field?',
        intent: 'locator_form_field_help',
      },
      {
        text: 'Give me an example for the destination field',
        intent: 'locator_form_field_help',
      },
      {
        text: 'Which DTR slots should I select?',
        intent: 'locator_form_field_help',
      },
    ];
  }
  if (intent === 'locator_guided_filing') {
    return [
      { text: 'What locator types can I file?', intent: 'locator_types' },
      {
        text: 'What should I put in the reason field?',
        intent: 'locator_form_field_help',
      },
      { text: 'Can I file locator tomorrow?', intent: 'locator_availability_check' },
    ];
  }
  if (intent === 'clarify_filing_topic') {
    return [
      { text: 'File a leave request', intent: 'leave_guided_filing' },
      { text: 'File a locator / WFH', intent: 'locator_guided_filing' },
      { text: 'Check leave balance first', intent: 'leave_balance' },
    ];
  }
  if (intent === 'clarify_status_topic') {
    return [
      { text: 'Check DTR status', intent: 'today_dtr' },
      { text: 'Check leave request status', intent: 'latest_leave_request' },
      { text: 'Check locator status', intent: 'locator_status' },
    ];
  }
  if (
    intent === 'today_dtr' ||
    intent === 'missing_logs' ||
    intent === 'dtr_daily_record' ||
    intent === 'dtr_status_explanation'
  ) {
    return [
      { text: 'Show missing logs this week', intent: 'dtr_missing_logs' },
      { text: 'Why is my DTR incomplete?', intent: 'dtr_missing_log_reason' },
      { text: 'Check locator coverage', intent: 'dtr_locator_coverage_check' },
    ];
  }
  if (
    intent === 'dtr_missing_logs' ||
    intent === 'dtr_missing_log_reason' ||
    intent === 'dtr_absent_summary'
  ) {
    return [
      { text: 'How do I fix missing logs?', intent: 'dtr_correction_guidance' },
      { text: 'Check leave coverage', intent: 'dtr_leave_coverage_check' },
      { text: 'Check locator coverage', intent: 'dtr_locator_coverage_check' },
    ];
  }
  if (
    intent === 'dtr_range_summary' ||
    intent === 'dtr_late_summary' ||
    intent === 'dtr_late_reason' ||
    intent === 'dtr_undertime_summary' ||
    intent === 'dtr_overtime_summary' ||
    intent === 'dtr_policy_guidance'
  ) {
    return [
      { text: 'Show all late records this month', intent: 'dtr_late_summary' },
      { text: 'Show undertime this month', intent: 'dtr_undertime_summary' },
      { text: 'How do I fix DTR issues?', intent: 'dtr_correction_guidance' },
    ];
  }
  if (
    intent === 'latest_locator_request' ||
    intent === 'locator_status' ||
    intent === 'locator_summary' ||
    intent === 'locator_types' ||
    intent === 'locator_requirements' ||
    intent === 'locator_form_field_help' ||
    intent === 'locator_guided_filing' ||
    intent === 'locator_availability_check' ||
    intent === 'locator_rejection_reason' ||
    intent === 'locator_approval_tracker' ||
    intent === 'dtr_locator_coverage_check'
  ) {
    return [
      { text: 'What is my locator status?', intent: 'locator_status' },
      { text: 'What locator types can I file?', intent: 'locator_types' },
      { text: 'What should I put in the reason field?', intent: 'locator_form_field_help' },
    ];
  }
  if (
    intent === 'locator_form_field_help' ||
    intent === 'locator_guided_filing'
  ) {
    return [
      { text: 'Can I file locator tomorrow?', intent: 'locator_availability_check' },
      { text: 'What locator types can I file?', intent: 'locator_types' },
      { text: 'Open locator form', intent: 'locator_guided_filing' },
    ];
  }
  if (intent === 'leave_availability_check') {
    return [
      { text: 'Check leave requirements', intent: 'leave_requirements' },
      { text: 'Do I have overlapping leave?', intent: 'leave_overlap_check' },
      { text: 'What attachment do I need?', intent: 'leave_attachment_requirement' },
    ];
  }
  if (intent === 'leave_balance') {
    return [
      { text: 'Why is my leave balance low?', intent: 'leave_balance' },
      { text: 'If I file 1 day vacation, how much remains?', intent: 'leave_balance_after_filing' },
      { text: 'Show my leave history this month', intent: 'leave_history' },
    ];
  }
  if (intent === 'leave_requirements' || intent === 'leave_filing_policy') {
    return [
      { text: 'What attachment is required?', intent: 'leave_attachment_requirement' },
      { text: 'Can I file 1 day vacation leave tomorrow?', intent: 'leave_availability_check' },
      { text: 'Show available leave types', intent: 'leave_types' },
    ];
  }
  if (
    intent === 'leave_form_guidance' ||
    intent === 'leave_eligibility_check' ||
    intent === 'leave_dtr_impact' ||
    intent === 'leave_guided_filing' ||
    intent === 'leave_type_compare' ||
    intent === 'leave_guideline_section'
  ) {
    return [
      { text: 'Can I file 1 day vacation leave tomorrow?', intent: 'leave_availability_check' },
      { text: 'What attachment do I need?', intent: 'leave_attachment_requirement' },
      { text: 'Does this affect my DTR?', intent: 'leave_dtr_impact' },
    ];
  }
  if (intent === 'latest_leave_request' || intent === 'leave_approval_tracker') {
    return [
      { text: 'Who is holding my leave request?', intent: 'leave_approval_tracker' },
      { text: 'Show approval timeline', intent: 'leave_approval_history' },
      { text: 'Why was my leave returned or rejected?', intent: 'leave_rejection_reason' },
    ];
  }
  if (intent === 'leave_history' || intent === 'leave_request_summary') {
    return [
      { text: 'Summarize my leave this month', intent: 'leave_request_summary' },
      { text: 'Show approved leave this month', intent: 'approved_leave_requests' },
      { text: 'Show rejected leave requests', intent: 'rejected_leave_requests' },
    ];
  }
  if (intent === 'leave_request_lookup') {
    return [
      { text: 'Show my leave history this month', intent: 'leave_history' },
      { text: 'Check leave requirements', intent: 'leave_requirements' },
      { text: 'Who is holding my leave request?', intent: 'leave_approval_tracker' },
    ];
  }
  return [
    { text: 'What is my leave balance?', intent: 'leave_balance' },
    { text: 'Show my pending leave requests', intent: 'pending_leave_requests' },
  ];
}

function buildAttachments(intent, context, userId) {
  if (intent === 'dtr_export_guidance') {
    return [createDtrExportAttachment(context, userId, 'xls')];
  }
  return [];
}

function action(id, label, type, { icon, intent, prompt, payload, autoExecute } = {}) {
  return {
    id,
    label,
    type,
    icon: icon || null,
    intent: intent || null,
    prompt: prompt || null,
    payload: payload || {},
    autoExecute: autoExecute === true,
  };
}

function dateRangePayload(context) {
  const range = context?.date_range || {};
  return {
    dateRangeLabel: range.label || null,
    startDate: range.startDate || null,
    endDate: range.endDate || null,
  };
}

function actionLeaveType(text) {
  const type = requestedLeaveType(text);
  if (type === 'sick') return 'sick';
  if (type === 'vacation') return 'vacation';
  return null;
}

function actionLocatorType(text) {
  return requestedLocatorType(text);
}

function dtrRecordMissingSlots(record) {
  if (!record) return ['no DTR record'];
  const status = lower(record.status);
  if (status === 'on_leave' || status === 'holiday' || record.leave_type || record.holiday_name) {
    return [];
  }
  const missing = [];
  if (!record.time_in) missing.push('AM in');
  if (!record.break_out) missing.push('AM out');
  if (!record.break_in) missing.push('PM in');
  if (!record.time_out) missing.push('PM out');
  return missing;
}

function firstDtrIssueForAction(context) {
  const records = context?.dtr_records || [];
  const record = records.find((item) => {
    const status = lower(item.status);
    return (
      status === 'absent' ||
      status === 'no_record' ||
      status === 'missing' ||
      status === 'incomplete' ||
      dtrRecordMissingSlots(item).length > 0
    );
  });
  if (record) {
    const slots = dtrRecordMissingSlots(record);
    return {
      date: String(record.attendance_date || '').slice(0, 10),
      slots,
    };
  }

  const recordDates = new Set(records.map((item) => String(item.attendance_date || '').slice(0, 10)));
  const today = todayInHrmsTimezone();
  const noRecordDay = (context?.dtr_calendar_days || []).find((day) => {
    const date = String(day.attendance_date || '').slice(0, 10);
    if (!date || date > today || recordDates.has(date)) return false;
    return !!day.shift_id && !!day.start_time && day.holiday_coverage !== 'whole_day';
  });
  if (!noRecordDay) return null;
  return {
    date: String(noRecordDay.attendance_date || '').slice(0, 10),
    slots: ['no DTR record'],
  };
}

function correctionPromptForAction(context) {
  const issue = firstDtrIssueForAction(context);
  if (!issue?.date) return null;
  const slotText =
    issue.slots && issue.slots.length > 0
      ? issue.slots.join(', ')
      : 'DTR issue';
  return `How do I fix ${slotText} on ${issue.date}?`;
}

function uniqueActions(actions) {
  const seen = new Set();
  return actions.filter((item) => {
    if (!item || !item.id || !item.label || !item.type) return false;
    if (seen.has(item.id)) return false;
    seen.add(item.id);
    return true;
  }).slice(0, 4);
}

function buildActions(intent, context, text, attachments = [], memory = null) {
  const value = String(intent || '');
  const actions = [];
  const rangePayload = dateRangePayload(context);
  const leaveType = actionLeaveType(text);
  const locatorType = actionLocatorType(text);
  const exportAttachment = attachments.find((item) => item?.downloadUrl || item?.contentBase64);

  if (exportAttachment) {
    actions.push(
      action('download_dtr_export', 'Download DTR export', 'download_attachment', {
        icon: 'download',
        payload: {
          attachmentId: exportAttachment.id || null,
          filename: exportAttachment.filename || null,
          downloadUrl: exportAttachment.downloadUrl || null,
        },
      })
    );
  }

  if (isLeaveIntent(value)) {
    const payload = buildLeaveActionPayload({
      text,
      memory,
      leaveType,
      rangePayload,
    });
    if (
      value === 'leave_availability_check' ||
      value === 'leave_guided_filing' ||
      value === 'leave_balance_after_filing' ||
      value === 'leave_form_guidance' ||
      value === 'leave_form_field_help'
    ) {
      actions.push(
        action('open_leave_form', 'Open leave form', 'open_leave_form', {
          icon: 'event_available',
          payload,
        })
      );
    }
    actions.push(
      action('open_leave_page', 'Open My Leave', 'open_leave_page', {
        icon: 'event_note',
        payload,
      })
    );
  }

  if (isLocatorIntent(value) || value === 'dtr_locator_coverage_check') {
    const payload = buildLocatorActionPayload({
      text,
      memory,
      locatorType,
      rangePayload,
    });
    if (
      value === 'locator_types' ||
      value === 'locator_requirements' ||
      value === 'locator_form_field_help' ||
      value === 'locator_guided_filing' ||
      value === 'locator_availability_check'
    ) {
      actions.push(
        action('open_locator_form', 'Open locator form', 'open_locator_form', {
          icon: 'add_location',
          payload,
        })
      );
    }
    actions.push(
      action('open_locator_page', 'Open Locator Requests', 'open_locator_page', {
        icon: 'pin_drop',
        payload,
      })
    );
  }

  if (isStructuredDtrIntent(value)) {
    const correctionPrompt = correctionPromptForAction(context);
    actions.push(
      action('open_dtr_time_logs', 'Open My Attendance', 'open_dtr_time_logs', {
        icon: 'schedule',
        payload: rangePayload,
      })
    );
    if (
      correctionPrompt &&
      (
        value === 'dtr_missing_logs' ||
        value === 'dtr_missing_log_reason' ||
        value === 'dtr_absent_summary' ||
        value === 'dtr_status_explanation' ||
        value === 'dtr_daily_record' ||
        value === 'today_dtr' ||
        value === 'missing_logs'
      )
    ) {
      actions.push(
        action('show_correction_steps', 'Show correction steps', 'send_prompt', {
          icon: 'build',
          intent: 'dtr_correction_guidance',
          prompt: correctionPrompt,
          payload: rangePayload,
        })
      );
    }
    if (value !== 'dtr_export_guidance') {
      actions.push(
        action('generate_dtr_export', 'Generate DTR export', 'send_prompt', {
          icon: 'file_download',
          intent: 'dtr_export_guidance',
          prompt: 'Generate my DTR export for this period.',
          payload: rangePayload,
        })
      );
    }
  }

  return uniqueActions(actions);
}

function directOpenCommandForMessage(text) {
  const value = lower(text);
  const hasNavigationCommand =
    /\b(open|navigate|go to|take me to|buksan|puntahan|punta sa|adto sa|adto ko sa|dalha ko sa)\b/.test(
      value
    );
  if (!hasNavigationCommand) return null;

  const wantsForm =
    /\b(form|create|new|start|fill|apply|submit|file|filing|mag file|mag-file|i-file|i file)\b/.test(
      value
    );
  const rangePayload = dateRangePayload({
    date_range: parseAssistantDateRange(text),
  });
  const language = simpleLanguageOf(text);
  const say = (english, bisaya, tagalog) => {
    if (language === 'bisaya') return bisaya;
    if (language === 'tagalog') return tagalog;
    return english;
  };

  if (
    /\b(locator|locator slip|locator request|locator requests|pass slip|wfh|work from home|official business|ob|fieldwork|field work|travel order)\b/.test(
      value
    )
  ) {
    const payload = {
      ...rangePayload,
      locatorType: actionLocatorType(text),
    };
    if (wantsForm) {
      return {
        intent: 'locator_availability_check',
        content: say(
          'Opening the locator form now.',
          'Sige, akong ablihan ang locator form.',
          'Sige, bubuksan ko ang locator form.'
        ),
        actions: uniqueActions([
          action('open_locator_form', 'Open locator form', 'open_locator_form', {
            icon: 'add_location',
            payload,
            autoExecute: true,
          }),
        ]),
      };
    }
    return {
      intent: 'locator_status',
      content: say(
        'Opening your locator requests now.',
        'Sige, akong ablihan imong locator requests.',
        'Sige, bubuksan ko ang locator requests mo.'
      ),
      actions: uniqueActions([
        action('open_locator_page', 'Open Locator Requests', 'open_locator_page', {
          icon: 'pin_drop',
          payload,
          autoExecute: true,
        }),
      ]),
    };
  }

  if (/\b(leave|leave request|leave requests|sick leave|vacation leave|vl|sl)\b/.test(value)) {
    const payload = {
      ...rangePayload,
      leaveType: actionLeaveType(text),
    };
    if (wantsForm) {
      return {
        intent: 'leave_guided_filing',
        content: say(
          'Opening the leave form now.',
          'Sige, akong ablihan ang leave form.',
          'Sige, bubuksan ko ang leave form.'
        ),
        actions: uniqueActions([
          action('open_leave_form', 'Open leave form', 'open_leave_form', {
            icon: 'event_available',
            payload,
            autoExecute: true,
          }),
        ]),
      };
    }
    return {
      intent: 'leave_history',
      content: say(
        'Opening My Leave now.',
        'Sige, akong ablihan ang My Leave.',
        'Sige, bubuksan ko ang My Leave.'
      ),
      actions: uniqueActions([
        action('open_leave_page', 'Open My Leave', 'open_leave_page', {
          icon: 'event_note',
          payload,
          autoExecute: true,
        }),
      ]),
    };
  }

  if (
    /\b(dtr|attendance|daily time|time log|time logs|logs|report|reports)\b/.test(
      value
    )
  ) {
    const openReports = /\b(report|reports|print|export)\b/.test(value);
    return {
      intent: openReports ? 'dtr_export_guidance' : 'dtr_daily_record',
      content: openReports
        ? say(
            'Opening DTR reports now.',
            'Sige, akong ablihan ang DTR reports.',
            'Sige, bubuksan ko ang DTR reports.'
          )
        : say(
            'Opening My Attendance now.',
            'Sige, akong ablihan imong My Attendance.',
            'Sige, bubuksan ko ang My Attendance mo.'
          ),
      actions: uniqueActions([
        action(
          openReports ? 'open_dtr_reports' : 'open_dtr_time_logs',
          openReports ? 'Open DTR reports' : 'Open My Attendance',
          openReports ? 'open_dtr_reports' : 'open_dtr_time_logs',
          {
            icon: openReports ? 'file_download' : 'schedule',
            payload: rangePayload,
            autoExecute: true,
          }
        ),
      ]),
    };
  }

  return null;
}

function numericConfidence(value) {
  if (value == null || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : null;
}

function buildAssistantResult({
  content,
  provider,
  model,
  modelProfile,
  mode,
  context,
  intent,
  intentConfidence,
  intentSource,
  attachments,
  text,
  actions,
  memory,
}) {
  const safeAttachments = attachments || [];
  const safeIntentConfidence = numericConfidence(intentConfidence);
  return {
    message: {
      id: crypto.randomUUID(),
      role: 'assistant',
      content: compactAssistantContent(content),
      createdAt: new Date().toISOString(),
      intent: intent || null,
      intentConfidence: safeIntentConfidence,
      intentSource: intentSource || null,
      provider: provider || null,
      model: model || null,
      modelProfile: modelProfile || null,
      promptPreview: text || null,
      suggestions: buildSuggestions(intent),
      attachments: safeAttachments,
      actions: actions || buildActions(intent, context, text || '', safeAttachments, memory),
    },
    provider,
    model,
    modelProfile: modelProfile || null,
    mode,
    intent: intent || null,
    intentConfidence: safeIntentConfidence,
    intentSource: intentSource || null,
    sources: buildSources(context),
  };
}

function parseIntentClassifierResponse(content) {
  const text = String(content || '').trim();
  if (!text) return null;

  try {
    const parsed = JSON.parse(text);
    return normalizeIntent(parsed.intent);
  } catch (_) {
    const match = text.match(
      /\b(today_dtr|missing_logs|dtr_daily_record|dtr_range_summary|dtr_missing_logs|dtr_missing_log_reason|dtr_late_summary|dtr_late_reason|dtr_undertime_summary|dtr_overtime_summary|dtr_absent_summary|dtr_status_explanation|dtr_correction_guidance|dtr_leave_coverage_check|dtr_locator_coverage_check|dtr_holiday_check|dtr_schedule_context|dtr_export_guidance|dtr_policy_guidance|leave_balance|pending_leave_requests|approved_leave_requests|rejected_leave_requests|leave_history|leave_availability_check|leave_attachment_requirement|leave_overlap_check|leave_pending_days_explanation|leave_balance_after_filing|leave_request_summary|leave_filing_policy|leave_form_guidance|leave_form_field_help|leave_eligibility_check|leave_dtr_impact|leave_guideline_section|leave_type_compare|leave_guided_filing|leave_approval_history|leave_rejection_reason|leave_approval_tracker|leave_request_lookup|leave_types|leave_requirements|latest_leave_request|latest_locator_request|locator_status|locator_summary|locator_types|locator_requirements|locator_form_field_help|locator_guided_filing|locator_availability_check|locator_rejection_reason|locator_approval_tracker|unknown)\b/i
    );
    return normalizeIntent(match?.[1]);
  }
}

function extractJsonObject(content) {
  const text = String(content || '').trim();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch (__) {
      return null;
    }
  }
}

function isIsoDate(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(value || ''));
}

function normalizePlannedDateRange(dateRange) {
  if (!dateRange || typeof dateRange !== 'object') return null;
  const startDate = String(dateRange.startDate || '').slice(0, 10);
  const endDate = String(dateRange.endDate || startDate).slice(0, 10);
  if (!isIsoDate(startDate) || !isIsoDate(endDate)) return null;
  if (startDate > endDate) return null;
  return {
    label: String(dateRange.label || (startDate === endDate ? startDate : `${startDate} to ${endDate}`)).trim(),
    startDate,
    endDate,
  };
}

function parseToolPlanResponse(content) {
  const parsed = extractJsonObject(content);
  if (!parsed) return null;
  return {
    intent: normalizeIntent(parsed.intent),
    dateRange: normalizePlannedDateRange(parsed.dateRange),
    normalizedQuestion:
      typeof parsed.normalizedQuestion === 'string'
        ? parsed.normalizedQuestion.slice(0, 500).trim()
        : '',
    extraction: normalizePlannerExtraction(parsed.extraction),
  };
}

function dateRangeLooksDefaultToday(dateRange, text) {
  if (!dateRange || dateRange.label !== 'today') return false;
  return !/\b(today|karong adlawa|karon nga adlaw|ngayon)\b/i.test(String(text || ''));
}

function intentUsuallyNeedsDateRange(intent) {
  return [
    'today_dtr',
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
    // Calculated intents that need a date range
    'dtr_hours_summary',
    'leave_history',
    'leave_availability_check',
    'leave_overlap_check',
    'leave_balance_after_filing',
    'leave_request_summary',
    'leave_approval_history',
    'leave_rejection_reason',
    'leave_approval_tracker',
    'leave_request_lookup',
    'latest_leave_request',
    'pending_leave_requests',
    'approved_leave_requests',
    'rejected_leave_requests',
    'latest_locator_request',
    'locator_status',
    'locator_summary',
    'locator_availability_check',
    'locator_rejection_reason',
    'locator_approval_tracker',
  ].includes(String(intent || ''));
}

function shouldAskAiForToolPlan({
  resolvedIntent,
  dateRange,
  text,
  profile,
  intentConfidence = 1,
  intentNeedsAiPlan = false,
}) {
  if (!profile || profile.engine === 'direct') return false;
  if (!resolvedIntent) return true;
  if (intentNeedsAiPlan || intentConfidence < 0.62) return true;
  if (
    dateRangeLooksDefaultToday(dateRange, text) &&
    intentUsuallyNeedsDateRange(resolvedIntent)
  ) {
    return true;
  }
  return false;
}

function simpleLanguageOf(text) {
  const value = lower(text);
  if (/\b(tagaloga?|tagalog|filipino)\b/.test(value)) return 'tagalog';
  if (/\b(bisayaa?|binisayaa?|cebuano)\b/.test(value)) return 'bisaya';
  if (/\b(unsa|unsaon|unsay|ngano|pila|naa|akong|nako|imong|nimo|ug|karon|pwede|adto|ato|ana|bulana|semanaha|daw|apil|ila|nga)\b/.test(value)) {
    return 'bisaya';
  }
  if (/\b(tagalog|filipino|ano|paano|pano|bakit|ilan|ngayon|kailangan|puwede|pwede|ako|ko|ba|may|wala)\b/.test(value)) {
    return 'tagalog';
  }
  return 'english';
}

function hasDateOrAvailabilityHint(text) {
  return /\b(today|tomorrow|yesterday|ugma|kagahapon|gahapon|karon|ngayon|date|day|adlaw|pay\s*period|payroll\s*period|cutoff|cut-off|cut off|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b|\b(?:sa|pag|noong|nung|adtong|adtung|atong|niadtong|niadtung)\s+\d{1,2}\b/i.test(
    text
  );
}

function isHowToFileInstructionQuestion(text) {
  const value = lower(text);
  if (
    /\b(requirements?|requirement|attachment|attachments?|document|documents|docs|proof|supporting|need|needed|kinahanglan|kailangan)\b/.test(
      value
    )
  ) {
    return false;
  }
  return /\b(how can i file|how do i file|how to file|how can i apply|how do i apply|how to apply|steps? to file|procedure.*file|guide.*file|paano.*file|paano.*apply|unsaon.*file|unsaon.*apply|paunsa.*file|pag file|pag-file)\b/.test(
    value
  );
}

function isLeaveGuidelineSectionQuestion(text) {
  return /\b(general rules?|filing deadlines?|deadlines?|supporting documents?|attachments?|leave credits?|monthly credits?|monthly accrual|earned credits?|earned leave|credits and limits?|commutation|monetization|monetisation|terminal leave|guidelines?|guideline sections?|guidelines?.*(?:leave types?|types of leave)|leave types?.*guidelines?|types of leave.*guidelines?|explain.*guidelines?|explain.*deadlines?|explain.*credits?|explain.*documents?)\b|1\.25(?:0)?/.test(
    lower(text)
  );
}

function isLeaveTypeExplanationQuestion(text) {
  const value = lower(text);
  const hasExplainWord =
    /\b(explain|describe|details?|detail|tell me about|what is|what are|meaning|pasabot|ibig sabihin|i-explain|explain daw|explain na)\b/.test(
      value
    );
  if (!hasExplainWord) return false;
  if (/\b(dtr|attendance|locator|pass slip|wfh|official business|ob)\b/.test(value)) return false;
  return /\b(leave|leaves|sick|vacation|paternity|maternity|adoption|solo parent|vawc|calamity|mandatory|forced|vl|sl|leave types?|types of leave|all leaves?|available leaves?)\b/.test(
    value
  );
}

function isExplainFollowUpQuestion(text) {
  return /\b(explain|describe|details?|detail|pasabot|meaning|ibig sabihin|daw na sila|na sila|them|those|that|it)\b/.test(
    lower(text)
  );
}

function isAllLeaveTypesFollowUpQuestion(text) {
  const value = lower(text);
  return /\b(all|complete|full|tanang|tanan|lahat)\b/.test(value) &&
    /\b(leave|leaves|types?|klase|uri)\b/.test(value);
}

function requestedRestyleLanguage(text) {
  const value = lower(text);
  if (/\b(bisayaa?|binisayaa?|cebuano)\b/.test(value)) return 'bisaya';
  if (/\b(tagaloga?|tagalog|filipino)\b/.test(value)) return 'tagalog';
  if (/\b(english|ingles)\b/.test(value)) return 'english';
  return null;
}

function isLanguageRestyleRequest(text) {
  const value = lower(text);
  if (!requestedRestyleLanguage(value)) return false;
  if (explicitTopicFromText(value)) return false;
  const words = value.split(/[^a-z0-9]+/).filter(Boolean);
  if (words.length <= 6) return true;
  return /\b(translate|answer|reply|say|again|daw|please|pls|lang|only|in|sa|into|to|make|i)\b/.test(
    value
  );
}

function isAmbiguousFilingQuestion(text) {
  const value = lower(text);
  if (explicitTopicFromText(value)) return false;
  if (isLeaveGuidelineSectionQuestion(value)) return false;
  const hasFilingIntent =
    /\b(file|filing|apply|submit|avail|can file|can i file|pwede.*file|puwede.*file|pwede ba|puwede ba|allowed|eligible|qualified|mag file|mag-file|i file|i-file)\b/.test(
      value
    );
  if (!hasFilingIntent) return false;
  return !/\b(dtr correction|correction|correct|adjustment|manual log)\b/.test(value);
}

function isAmbiguousStatusQuestion(text) {
  const value = lower(text);
  if (explicitTopicFromText(value)) return false;
  return /\b(status|approved|approve|accepted|na-approve|pending|rejected|returned|cancelled|canceled|where|asa|kinsa|sino|who|holding|waiting|remarks|reason|approved na|na approve)\b/.test(
    value
  );
}

function clarificationIntentForMessage(text, explicitIntent, memoryIntent) {
  if (normalizeIntent(explicitIntent) || memoryIntent) return null;
  if (isAmbiguousFilingQuestion(text)) return 'clarify_filing_topic';
  if (isAmbiguousStatusQuestion(text)) return 'clarify_status_topic';
  return null;
}

function clarificationContent(intent, text) {
  const language = simpleLanguageOf(text);
  if (intent === 'clarify_filing_topic') {
    if (language === 'bisaya') {
      return 'Unsay gusto nimo i-file: leave request ba, or locator slip/WFH?';
    }
    if (language === 'tagalog') {
      return 'Alin ang gusto mong i-file: leave request o locator slip/WFH?';
    }
    return 'Which one do you want to file: a leave request or a locator slip/WFH?';
  }
  if (language === 'bisaya') {
    return 'Unsa nga status imong gusto i-check: DTR, leave request, or locator slip?';
  }
  if (language === 'tagalog') {
    return 'Aling status ang gusto mong i-check: DTR, leave request, o locator slip?';
  }
  return 'Which status do you want to check: DTR, leave request, or locator slip?';
}

function gracefulFallbackContent(text) {
  const language = simpleLanguageOf(text);
  if (language === 'bisaya') {
    return 'Pasensya, wala nako masabti imong question. Mao ang akong mahimong tabangon:\n\n- DTR status ug attendance logs\n- Missing o incomplete logs\n- Late, undertime, overtime summary\n- Total hours worked this month\n- DTR correction guidance\n- Leave balance ug projections (e.g. "If I take 3 days, how many left?")\n- Leave requests, history, ug approval\n- Leave eligibility, requirements, ug form guidance\n- Locator slip status ug summary\n\nPwede ka magtanong ug ingon ani, o pili sa mga suggestions sa ubos.';
  }
  if (language === 'tagalog') {
    return 'Pasensya, hindi ko naintindihan ang iyong tanong. Narito ang mga maitutulong ko:\n\n- DTR status at attendance logs\n- Missing o incomplete logs\n- Late, undertime, overtime summary\n- Kabuuang oras na nagtrabaho ngayong buwan\n- DTR correction guidance\n- Leave balance at projections (e.g. "If I take 3 days, how many left?")\n- Leave requests, history, at approval\n- Leave eligibility, requirements, at form guidance\n- Locator slip status at summary\n\nPwede kang magtanong ng ganito, o pumili sa mga suggestions sa ibaba.';
  }
  return "I'm not sure what you're asking about. Here is what I can help you with:\n\n- DTR status and attendance logs\n- Missing or incomplete logs\n- Late, undertime, and overtime summary\n- Total hours worked this month\n- DTR correction guidance\n- Leave balances and projections (e.g. \"If I take 3 days, how many days are left?\")\n- Leave requests, history, and approval tracking\n- Leave eligibility, requirements, and form guidance\n- Locator slip status and summary\n\nTry asking one of the above, or tap a suggestion below.";
}

function isFollowUpQuestion(text) {
  return /\b(it|that|this|one|same|about|how about|what about|what happens?|what will happen|mahitabo|mangyayari|translate|answer|reply|say|again|another|more|example|sample|input|field|check|checked|checking|checkbox|chineck|enable|enabled|turn on|bisayaa?|binisayaa?|cebuano|tagalog|filipino|english|ingles|daw|explain|guidelines?|deadlines?|supporting|documents?|credits?|commutation|monetization|monetisation|terminal leave|ana|ato|adto|niya|same day|same date|next day|following day|sunod adlaw|previous day|day before|today|tomorrow|yesterday|ugma|gahapon|kagahapon|week|month|pay\s*period|payroll\s*period|cutoff|cut-off|cut off|ago|from|to|semana|semanaha|bulan|bulana|buwan|buwana|aning|karong|ngayong|ngano|why|bakit|pila|unsa|ano|how many|status|approved|accepted|pending|rejected|requirements?|remarks?|reason|who|where|asa|kinsa|sino|can|file|pwede|puwede|allowed|eligible|instead|only|make it|absent|absence|late|tardy|undertime|under time|overtime|over time|ot|missing|incomplete|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo)\b/.test(
    lower(text)
  );
}

function isShortDurationAnswer(text) {
  const value = lower(text).trim();
  return (
    value.split(/\s+/).filter(Boolean).length <= 5 &&
    (/\b\d+(?:\.\d+)?\s*(?:day|days|adlaw|ka adlaw|araw)?\b/.test(value) ||
      extractDayCount(value) != null)
  );
}

function isShortLeaveTypeAnswer(text) {
  const value = lower(text).trim();
  if (value.split(/\s+/).filter(Boolean).length > 6) return false;
  if (/\b(how|what|which|why|ngano|unsa|unsay|ano|pila|can|pwede|puwede)\b/.test(value)) {
    return false;
  }
  return (
    /\b(?:sick|vacation|maternity|paternity|adoption|mandatory|forced|solo parent|vawc|calamity|study|rehabilitation|special privilege|special leave|others?)\s+leave\b/.test(
      value
    ) || /^(?:sl|vl)$/.test(value)
  );
}

function isShortLocatorTypeAnswer(text) {
  const value = lower(text).trim();
  if (value.split(/\s+/).filter(Boolean).length > 6) return false;
  if (/\b(how|what|which|why|ngano|unsa|unsay|ano|pila|can|pwede|puwede)\b/.test(value)) {
    return false;
  }
  return /\b(wfh|work from home|official business|ob|pass slip|locator|fieldwork|field work)\b/.test(
    value
  );
}

function isShortDtrSlotAnswer(text) {
  const value = lower(text).trim();
  return (
    value.split(/\s+/).filter(Boolean).length <= 5 &&
    /\b(am in|am out|pm in|pm out|time in|time out)\b/.test(value)
  );
}

function memoryRelativeDate(text, memory) {
  if (!memory?.dateRange?.startDate) return null;
  const value = lower(text);
  if (/\b(next day|following day|sunod adlaw|sunod nga adlaw|kinabukasan)\b/.test(value)) {
    return addDays(memory.dateRange.startDate, 1);
  }
  if (/\b(previous day|day before|miaging adlaw|niaging adlaw|nakaraang araw)\b/.test(value)) {
    return addDays(memory.dateRange.startDate, -1);
  }
  if (/\b(same day|same date|that day|that date|ana|ato|adto|niya)\b/.test(value)) {
    return memory.dateRange.startDate;
  }
  return null;
}

function hasRangeDateHint(text) {
  return /\b(this week|current week|last week|previous week|next week|week|semana|semanaha|this month|current month|last month|previous month|next month|month|pay\s*period|payroll\s*period|cutoff|cut-off|cut off|bulan|bulana|buwan|buwana|aning bulana|karong bulana|karong buwan)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b|\b(?:from\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo)\s*(?:to|until|through|-|–)\s*(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo)\b/.test(
    lower(text)
  );
}

function dtrAbsenceQuestionText(text) {
  return /\b(absent|absents|absence|absences|no record|no-record|walay record|wala.*record|wala.*dtr|pasabot)\b/.test(
    lower(text)
  );
}

function recentMemoryMatches(memory, topic, matcher) {
  const items = [
    memory?.lastUserMessage,
    ...(memory?.history || [])
      .filter((item) => !topic || item.topic === topic)
      .map((item) => item.text),
  ].filter(Boolean);
  return items.some((item) => matcher(item));
}

function rangeCorrectionIntentForDtr(activeIntent, text, memory) {
  if (!hasRangeDateHint(text)) return null;
  if (activeIntent === 'dtr_late_reason' || activeIntent === 'dtr_late_summary') {
    return 'dtr_late_summary';
  }
  if (activeIntent === 'dtr_undertime_summary') return 'dtr_undertime_summary';
  if (activeIntent === 'dtr_overtime_summary') return 'dtr_overtime_summary';
  if (
    activeIntent === 'dtr_absent_summary' ||
    recentMemoryMatches(memory, 'dtr', dtrAbsenceQuestionText)
  ) {
    return 'dtr_absent_summary';
  }
  if (
    activeIntent === 'dtr_missing_logs' ||
    activeIntent === 'dtr_missing_log_reason' ||
    activeIntent === 'missing_logs'
  ) {
    return 'dtr_missing_logs';
  }
  return 'dtr_range_summary';
}

function resolveIntentFromMemory(text, memory) {
  if (!memory) return null;
  const value = lower(text);
  if (memory.pendingClarification?.intent) {
    const wordCount = value.split(/\s+/).filter(Boolean).length;
    if (wordCount <= 12 && !explicitTopicFromText(text)) {
      return memory.pendingClarification.intent;
    }
  }
  const memoryTopic = memory.topic || topicForIntent(memory.intent);
  const explicitTopic = explicitTopicFromText(text);
  if (isLanguageRestyleRequest(value)) {
    const recent = (memory.history || []).find(
      (item) => item?.intent && !['clarify_filing_topic', 'clarify_status_topic', 'direct_ai'].includes(item.intent)
    );
    return recent?.intent || memory.intent || null;
  }
  const guidelineFollowUp =
    (isLeaveGuidelineSectionQuestion(value) ||
      isLeaveTypeExplanationQuestion(value) ||
      isAllLeaveTypesFollowUpQuestion(value)) &&
    (memory.intent === 'leave_guideline_section' ||
      memory.intent === 'leave_types' ||
      memoryTopicState(memory, 'leave')?.intent === 'leave_guideline_section');
  if (guidelineFollowUp) return 'leave_guideline_section';
  if (
    memoryTopic === 'clarify' ||
    memory.intent === 'clarify_filing_topic' ||
    memory.intent === 'clarify_status_topic'
  ) {
    if (memory.intent === 'clarify_filing_topic') {
      if (explicitTopic === 'leave') {
        if (
          isHowToFileInstructionQuestion(value) ||
          isHowToFileInstructionQuestion(memory.lastUserMessage)
        ) {
          return 'leave_form_guidance';
        }
        return hasDateOrAvailabilityHint(value)
          ? 'leave_availability_check'
          : 'leave_guided_filing';
      }
      if (explicitTopic === 'locator') {
        return hasDateOrAvailabilityHint(value)
          ? 'locator_availability_check'
          : 'locator_types';
      }
      if (explicitTopic === 'dtr') return 'dtr_correction_guidance';
    }
    if (memory.intent === 'clarify_status_topic') {
      if (explicitTopic === 'dtr') return 'today_dtr';
      if (explicitTopic === 'leave') return 'latest_leave_request';
      if (explicitTopic === 'locator') return 'locator_status';
    }
  }
  const leaveTopicMemory = memoryTopicState(memory, 'leave');
  if (
    isShortLeaveTypeAnswer(value) &&
    leaveTopicMemory?.intent &&
    [
      'leave_availability_check',
      'leave_form_guidance',
      'leave_guided_filing',
      'leave_requirements',
      'leave_attachment_requirement',
      'leave_eligibility_check',
      'leave_balance',
      'leave_balance_projection',
      'leave_balance_after_filing',
      'leave_guideline_section',
      'leave_form_field_help',
      'leave_types',
    ].includes(leaveTopicMemory.intent) &&
    value.split(/\s+/).filter(Boolean).length <= 4
  ) {
    return leaveTopicMemory.intent === 'leave_types'
      ? 'leave_guideline_section'
      : leaveTopicMemory.intent;
  }
  if (
    isShortDurationAnswer(value) &&
    leaveTopicMemory?.intent &&
    [
      'leave_availability_check',
      'leave_attachment_requirement',
      'leave_balance_projection',
      'leave_balance_after_filing',
      'leave_guided_filing',
    ].includes(leaveTopicMemory.intent)
  ) {
    return leaveTopicMemory.intent;
  }
  const locatorTopicMemory = memoryTopicState(memory, 'locator');
  if (
    (isShortLocatorTypeAnswer(value) || isShortDtrSlotAnswer(value)) &&
    locatorTopicMemory?.intent &&
    [
      'locator_types',
      'locator_requirements',
      'locator_form_field_help',
      'locator_guided_filing',
      'locator_availability_check',
      'locator_status',
      'locator_summary',
      'locator_rejection_reason',
      'locator_approval_tracker',
      'latest_locator_request',
    ].includes(locatorTopicMemory.intent)
  ) {
    return locatorTopicMemory.intent;
  }
  if (!isFollowUpQuestion(text)) return null;
  if (explicitTopic && memoryTopic && explicitTopic !== memoryTopic) return null;
  const activeMemory = memoryTopicState(memory, explicitTopic || memoryTopic) || memory;
  const activeIntent = activeMemory.intent || memory.intent;
  const locatorTypeFollowUp =
    isLocatorIntent(activeIntent) &&
    /\b(types?|kinds?|options?|how about|what about|wfh|work from home|pass slip|official business|ob|on field|fieldwork|field work)\b/.test(value);
  if (!locatorTypeFollowUp && explicitTopic && explicitTopic !== memoryTopic) return null;
  if (isLocatorIntent(activeIntent)) {
    if (
      activeIntent === 'locator_form_field_help' &&
      (getLocatorFormFieldKey(value) ||
        /\b(another|more|example|sample|input|same field|this field|that field|bisayaa?|binisayaa?|cebuano|tagalog|filipino|english)\b/.test(
          value
        ))
    ) {
      return 'locator_form_field_help';
    }
    if (/\b(can file|can i file|pwede|puwede|allowed|eligible|qualified|available|tomorrow|ugma|karon|today|date|day|file)\b/.test(value)) {
      return 'locator_availability_check';
    }
    if (/\b(requirement|requirements|attachment|document|docs|need|needed|kinahanglan|kailangan|rule|rules|policy|how to file|unsaon|paano)\b/.test(value)) {
      if (isLocatorFormFieldHelpQuestion(value)) return 'locator_form_field_help';
      return 'locator_requirements';
    }
    if (
      locatorTypeFollowUp &&
      !/\b(status|approved|approve|accepted|pending|rejected|returned|cancelled|canceled|latest|last|recent|remarks|reason|who|where|asa|kinsa|sino|holding|waiting)\b/.test(value)
    ) {
      return 'locator_types';
    }
    if (
      /\b(remarks?|comment)\b/.test(value) &&
      activeIntent !== 'locator_rejection_reason'
    ) {
      return activeIntent;
    }
    if (/\b(why.*(?:reject|declin|deni)|ngano.*(?:reject|declin|deni)|bakit.*(?:reject|declin|deni)|rejected|reject|declined|denied|gi reject|gireject|same reason)\b/.test(value)) {
      return 'locator_rejection_reason';
    }
    if (/\b(who|kinsa|sino|where|asa|kanino|holding|hold|pending with|waiting|awaiting)\b/.test(value)) {
      return 'locator_approval_tracker';
    }
    if (/\b(summary|total|count|counts|pila|ilan|how many|history|list|show)\b/.test(value)) {
      return 'locator_summary';
    }
    if (/\b(types?|kinds?|options?|available.*locator|locator.*available)\b/.test(value)) {
      return 'locator_types';
    }
    if (/\b(status|approved|approve|accepted|pending|rejected|cancelled|canceled|where|asa|kinsa|sino|who|holding|waiting|remarks|reason|ngano|bakit|why)\b/.test(value)) {
      return 'locator_status';
    }
    if (
      activeIntent === 'locator_availability_check' &&
      (hasDateOrAvailabilityHint(value) ||
        isShortLocatorTypeAnswer(value) ||
        isShortDtrSlotAnswer(value) ||
        /\b(instead|only|make it)\b/.test(value))
    ) {
      return 'locator_availability_check';
    }
    return activeIntent;
  }
  if (isStructuredDtrIntent(activeIntent)) {
    const rangeCorrectionIntent = rangeCorrectionIntentForDtr(
      activeIntent,
      value,
      memory
    );
    if (rangeCorrectionIntent) return rangeCorrectionIntent;
    if (/\b(fix|correct|correction|buhaton|gagawin|resolve)\b/.test(value)) {
      return 'dtr_correction_guidance';
    }
    if (dtrAbsenceQuestionText(value)) {
      return 'dtr_absent_summary';
    }
    if (/\b(missing|incomplete|kulang|kuwang|what.*missing|unsa.*kulang)\b/.test(value)) {
      return 'dtr_missing_log_reason';
    }
    if (/\b(late|tardy)\b/.test(value)) {
      return 'dtr_late_summary';
    }
    if (/\b(undertime|under time)\b/.test(value)) {
      return 'dtr_undertime_summary';
    }
    if (/\b(overtime|over time|ot)\b/.test(value)) {
      return 'dtr_overtime_summary';
    }
    if (
      /^(why|ngano|bakit)\??$/.test(value.trim()) &&
      [
        'today_dtr',
        'dtr_daily_record',
        'dtr_status_explanation',
      ].includes(activeIntent)
    ) {
      return 'dtr_status_explanation';
    }
    if (memoryRelativeDate(value, activeMemory || memory)) {
      return activeIntent;
    }
    if (/\b(status|same day|same date|that day|that date|ana|ato|adto|niya|today|tomorrow|yesterday|ugma|gahapon|kagahapon)\b/.test(value)) {
      return activeIntent;
    }
  }
  if (isLeaveIntent(activeIntent)) {
    if (
      activeIntent === 'leave_form_field_help' &&
      (getLeaveFormFieldKey(value) ||
        isShortLeaveTypeAnswer(value) ||
        /\b(another|more|example|sample|input|same field|this field|that field|what happens?|what will happen|mahitabo|mangyayari|check|checked|checking|checkbox|chineck|enable|enabled|turn on|bisayaa?|binisayaa?|cebuano|tagalog|filipino|english)\b/.test(
          value
        ))
    ) {
      return 'leave_form_field_help';
    }
    if (
      isLeaveGuidelineSectionQuestion(value) ||
      isLeaveTypeExplanationQuestion(value) ||
      isAllLeaveTypesFollowUpQuestion(value) ||
      (activeIntent === 'leave_types' && isExplainFollowUpQuestion(value))
    ) {
      return 'leave_guideline_section';
    }
    if (isHowToFileInstructionQuestion(value)) {
      return 'leave_form_guidance';
    }
    if (
      activeIntent === 'leave_balance' &&
      /\b(why|ngano|bakit|gamay|low|small|mababa|maliit|nabilin|natira|remaining)\b/.test(
        value
      )
    ) {
      return 'leave_balance';
    }
    if (
      isShortLeaveTypeAnswer(value) ||
      (isShortDurationAnswer(value) &&
        [
          'leave_availability_check',
          'leave_attachment_requirement',
          'leave_balance_projection',
          'leave_balance_after_filing',
          'leave_guided_filing',
        ].includes(activeIntent))
    ) {
      return activeIntent;
    }
    if (/\b(can file|can i file|pwede|puwede|allowed|eligible|qualified|available|tomorrow|ugma|karon|today|date|day|file)\b/.test(value)) {
      return 'leave_availability_check';
    }
    if (/\b(why|ngano|bakit|reason|remarks|returned|rejected|declined|denied|same reason)\b/.test(value)) {
      return 'leave_rejection_reason';
    }
    if (/\b(requirement|requirements|needed|need|kinahanglan|kailangan)\b/.test(value)) {
      return 'leave_requirements';
    }
    if (/\b(attachment|attachments|document|documents|docs|proof|supporting|medical certificate|med cert)\b/.test(value)) {
      return 'leave_attachment_requirement';
    }
    if (/\b(who|kinsa|sino|where|asa|holding|waiting|awaiting|pending with)\b/.test(value)) {
      return 'leave_approval_tracker';
    }
    if (/\b(status|approved|approve|pending|latest|last|recent)\b/.test(value)) {
      return 'latest_leave_request';
    }
    if (/\b(summary|summarize|summarise|overview|recap|total|count|counts|history|list|show)\b/.test(value)) {
      return 'leave_request_summary';
    }
  }
  if (/\b(fix|correct|correction|buhaton|gagawin|resolve)\b/.test(lower(text))) {
    return 'dtr_correction_guidance';
  }
  if (/\b(locator|pass slip|wfh|official business|ob|covered)\b/.test(lower(text))) {
    return 'dtr_locator_coverage_check';
  }
  if (
    /\b(covered|cover|coverage|sakop|on leave)\b/.test(lower(text)) &&
    /\b(dtr|attendance|absent|absence|missing|incomplete|log|logs|date|day|today|tomorrow|yesterday|ugma|gahapon|kagahapon)\b/.test(
      lower(text)
    )
  ) {
    return 'dtr_leave_coverage_check';
  }
  if (/\b(late|tardy)\b/.test(lower(text))) {
    return 'dtr_late_summary';
  }
  if (/\b(undertime|under time)\b/.test(lower(text))) {
    return 'dtr_undertime_summary';
  }
  if (/\b(overtime|over time|ot)\b/.test(lower(text))) {
    return 'dtr_overtime_summary';
  }
  if (dtrAbsenceQuestionText(text)) {
    return 'dtr_absent_summary';
  }
  if (/\b(missing|incomplete|kulang|kuwang|what.*missing|unsa.*kulang)\b/.test(lower(text))) {
    return 'dtr_missing_log_reason';
  }
  if (/\b(attachment|attachments|document|documents|docs|proof|supporting|medical certificate|med cert)\b/.test(lower(text))) {
    return 'leave_attachment_requirement';
  }
  if (/\b(policy|rule|rules|advance|before|deadline|max|maximum|limit|past date)\b/.test(lower(text))) {
    return 'leave_filing_policy';
  }
  if (isLeaveGuidelineSectionQuestion(text) || isLeaveTypeExplanationQuestion(text)) {
    return 'leave_guideline_section';
  }
  if (/\b(requirement|requirements|needed|need|kinahanglan|kailangan)\b/.test(lower(text))) {
    return 'leave_requirements';
  }
  if (/\b(fill|field|fields|form|details|what to put|i-fill|input)\b/.test(lower(text))) {
    return 'leave_form_guidance';
  }
  if (isHowToFileInstructionQuestion(text)) {
    return 'leave_form_guidance';
  }
  if (/\b(eligible|eligibility|qualified|avail|entitled|pwede|puwede)\b/.test(lower(text))) {
    return 'leave_eligibility_check';
  }
  if (/\b(dtr|attendance|effect|impact|mark|on leave)\b/.test(lower(text))) {
    return 'leave_dtr_impact';
  }
  if (/\b(compare|difference|versus| vs |kalahi|pagkaiba)\b/.test(` ${lower(text)} `)) {
    return 'leave_type_compare';
  }
  if (/\b(guideline|guidelines|supporting documents|credits|commutation|monetization|terminal leave)\b/.test(lower(text))) {
    return 'leave_guideline_section';
  }
  if (/\b(help|guide|assist|tabangi).*\b(file|filing)\b/.test(lower(text))) {
    return 'leave_guided_filing';
  }
  if (/\b(timeline|approval history|review history|who approved|who reviewed)\b/.test(lower(text))) {
    return 'leave_approval_history';
  }
  if (/\b(who|kinsa|sino|where|asa|holding|waiting|awaiting|pending with)\b/.test(lower(text))) {
    return 'leave_approval_tracker';
  }
  if (/\b(what|which|unsa|unsay|ano|gi file|g-file|filed|leave type|that|to)\b/.test(lower(text))) {
    return 'leave_request_lookup';
  }
  if (/\b(why|ngano|bakit|reason|remarks|returned|rejected|declined|denied)\b/.test(lower(text))) {
    return 'leave_rejection_reason';
  }
  if (/\b(summary|summarize|summarise|overview|recap|total|count|counts)\b/.test(lower(text))) {
    return 'leave_request_summary';
  }
  if (/\b(overlap|conflict|same date|already|existing|naa|may)\b/.test(lower(text))) {
    return 'leave_overlap_check';
  }
  if (/\b(after filing|mabilin|matira|nabilin|natira|remaining after|balance after|pila.*mabilin|pila.*nabilin|how much.*remain|what.*remain)\b/.test(lower(text))) {
    return 'leave_balance_after_filing';
  }
  if (activeIntent === 'leave_balance' && /\b(why|ngano|bakit|gamay|low|small|nabilin|natira)\b/.test(lower(text))) {
    return 'leave_balance';
  }
  if (
    [
      'leave_balance',
      'today_dtr',
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
      'leave_history',
      'pending_leave_requests',
      'approved_leave_requests',
      'rejected_leave_requests',
      'latest_leave_request',
      'leave_availability_check',
      'leave_attachment_requirement',
      'leave_overlap_check',
      'leave_pending_days_explanation',
      'leave_balance_after_filing',
      'leave_request_summary',
      'leave_filing_policy',
      'leave_form_guidance',
      'leave_form_field_help',
      'leave_eligibility_check',
      'leave_dtr_impact',
      'leave_guideline_section',
      'leave_type_compare',
      'leave_guided_filing',
      'leave_approval_history',
      'leave_rejection_reason',
      'leave_approval_tracker',
      'leave_request_lookup',
      'leave_requirements',
      'leave_types',
      'latest_locator_request',
      'locator_status',
      'locator_summary',
      'locator_types',
      'locator_requirements',
      'locator_form_field_help',
      'locator_guided_filing',
      'locator_availability_check',
      'locator_rejection_reason',
      'locator_approval_tracker',
    ].includes(activeIntent)
  ) {
    return activeIntent;
  }
  return null;
}

function enrichMessageWithMemory(text, memory, memoryIntent = null) {
  let enriched = text;
  const explicitTopic = explicitTopicFromText(enriched);
  const topicMemory = explicitTopic
    ? strictMemoryTopicState(memory, explicitTopic)
    : memoryTopicState(memory, memoryIntent || memory?.intent);
  const activeIntent =
    memoryIntent || topicMemory?.intent || (!explicitTopic ? memory?.intent : null);
  const activeMemory = topicMemory || (!explicitTopic ? memory : null);
  const restyleSourceText =
    activeMemory?.text ||
    (memory?.history || []).find((item) => item?.intent === activeIntent)?.text ||
    memory?.lastUserMessage;
  const shortLeaveTypeAnswer =
    memoryIntent &&
    isLeaveIntent(memoryIntent) &&
    isShortLeaveTypeAnswer(enriched);
  if (
    shortLeaveTypeAnswer &&
    activeMemory?.text &&
    lower(activeMemory.text) !== lower(enriched)
  ) {
    enriched = `${enriched} (${activeMemory.text})`;
  }
  if (
    memoryIntent &&
    isLeaveIntent(memoryIntent) &&
    isShortDurationAnswer(enriched) &&
    activeMemory?.text &&
    lower(activeMemory.text) !== lower(enriched)
  ) {
    enriched = `${enriched} (${activeMemory.text})`;
  }
  if (
    memoryIntent &&
    isLocatorIntent(memoryIntent) &&
    (isShortLocatorTypeAnswer(enriched) || isShortDtrSlotAnswer(enriched)) &&
    activeMemory?.text &&
    lower(activeMemory.text) !== lower(enriched)
  ) {
    enriched = `${enriched} (${activeMemory.text})`;
  }
  if (
    isLanguageRestyleRequest(enriched) &&
    restyleSourceText &&
    lower(restyleSourceText) !== lower(enriched)
  ) {
    enriched = `${restyleSourceText} (${enriched})`;
  }
  if (
    memoryIntent === 'leave_form_field_help' &&
    activeMemory?.text &&
    !getLeaveFormFieldKey(enriched) &&
    /\b(another|more|example|sample|input|same field|this field|that field|what happens?|what will happen|mahitabo|mangyayari|check|checked|checking|checkbox|chineck|enable|enabled|turn on|bisayaa?|binisayaa?|cebuano|tagalog|filipino|english)\b/i.test(
      enriched
    )
  ) {
    enriched = `${activeMemory.text} (${enriched})`;
  }
  if (
    memoryIntent === 'leave_guideline_section' &&
    activeMemory?.text &&
    isExplainFollowUpQuestion(enriched) &&
    !isAllLeaveTypesFollowUpQuestion(enriched) &&
    !isLeaveTypeExplanationQuestion(enriched) &&
    (
      activeMemory.intent === 'leave_types' ||
      isLeaveTypeExplanationQuestion(activeMemory.text) ||
      isLeaveGuidelineSectionQuestion(activeMemory.text)
    )
  ) {
    enriched = `${activeMemory.text} (${enriched})`;
  }
  if (
    memoryIntent === 'leave_guideline_section' &&
    activeMemory?.text &&
    isAllLeaveTypesFollowUpQuestion(enriched) &&
    !isLeaveGuidelineSectionQuestion(enriched)
  ) {
    enriched = `${activeMemory.text} (${enriched})`;
  }
  const relativeDate = memoryRelativeDate(enriched, activeMemory);
  if (relativeDate) {
    enriched = `${enriched} (${relativeDate})`;
  }
  const hasDateHint =
    /\b(today|tomorrow|yesterday|ugma|kagahapon|gahapon|karon|week|semana|semanaha|month|pay\s*period|payroll\s*period|cutoff|cut-off|cut off|ago|from|to|bulan|bulana|buwan|buwana|aning bulana|sunod|miaging|niaging|adtong|adtung|atong|niadtong|niadtung|noong|nung|next day|following day|sunod adlaw|previous day|day before|same day|same date|ana|ato|adto|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\b/i.test(
      enriched
    );
  if (
    !hasDateHint &&
    activeMemory?.dateRange?.startDate &&
    isStructuredDtrIntent(activeIntent) &&
    isFollowUpQuestion(enriched)
  ) {
    enriched = `${enriched} (${activeMemory.dateRange.startDate}${
      activeMemory.dateRange.endDate &&
      activeMemory.dateRange.endDate !== activeMemory.dateRange.startDate
        ? ` to ${activeMemory.dateRange.endDate}`
        : ''
    })`;
  }
  if (
    !hasDateHint &&
    activeMemory?.dateRange?.startDate &&
    isLeaveIntent(activeIntent) &&
    /\b(what|which|unsa|unsay|ano|that|to|gi file|g-file|filed|leave type)\b/i.test(
      enriched
    )
  ) {
    enriched = `${enriched} (${activeMemory.dateRange.startDate}${
      activeMemory.dateRange.endDate &&
      activeMemory.dateRange.endDate !== activeMemory.dateRange.startDate
        ? ` to ${activeMemory.dateRange.endDate}`
        : ''
    })`;
  }
  if (
    !hasDateHint &&
    activeMemory?.dateRange?.startDate &&
    isLocatorIntent(activeIntent) &&
    isFollowUpQuestion(enriched)
  ) {
    enriched = `${enriched} (${activeMemory.dateRange.startDate}${
      activeMemory.dateRange.endDate &&
      activeMemory.dateRange.endDate !== activeMemory.dateRange.startDate
        ? ` to ${activeMemory.dateRange.endDate}`
        : ''
    })`;
  }

  if (isLocatorIntent(activeIntent) || /\b(locator|pass slip|wfh|work from home|official business|ob)\b/i.test(enriched)) {
    const broadLocatorSummaryFollowUp =
      activeIntent === 'locator_summary' &&
      /\b(summary|total|count|counts|pila|ilan|how many|history|list|show|accepted|approved|pending|rejected)\b/i.test(
        enriched
      ) &&
      !/\b(same type|same locator|same one|that type|ana|ato|adto)\b/i.test(enriched);
    const canUseRememberedLocatorType =
      !broadLocatorSummaryFollowUp &&
      (isFollowUpQuestion(text) || isLocatorIntent(activeIntent));
    const locatorType =
      requestedLocatorType(enriched) ||
      (canUseRememberedLocatorType
        ? activeMemory?.locatorType || (!explicitTopic ? memory?.locatorType : null)
        : null);
    if (locatorType && !requestedLocatorType(enriched)) {
      const locatorTypeLabel = locatorType.replace(/_/g, ' ');
      if (
        /locator_|locator\b|requirements?|attachment|types?|status|summary|approved|accepted|pending|rejected|how about|what about|can|file|pwede|puwede/i.test(
          activeIntent || enriched
        )
      ) {
        enriched = `${enriched} (${locatorTypeLabel})`;
      }
    }
  }

  if (!isLeaveIntent(activeIntent) && !/\b(leave|sick|vacation|vl|sl)\b/i.test(enriched)) {
    return enriched;
  }
  const leaveType =
    requestedLeaveType(enriched) ||
    (isFollowUpQuestion(text) || (!explicitTopic && isLeaveIntent(activeIntent))
      ? activeMemory?.leaveType || (!explicitTopic ? memory?.leaveType : null)
      : null);
  if (!leaveType) return enriched;
  if (requestedLeaveType(enriched)) return enriched;
  const leaveTypeLabel = /\bleave\b/i.test(leaveType)
    ? leaveType
    : `${leaveType} leave`;
  if (
    activeIntent === 'leave_balance' &&
    /\b(why|ngano|bakit|gamay|low|small|nabilin|natira)\b/.test(lower(text))
  ) {
    return `${enriched} (${leaveTypeLabel})`;
  }
  if (/leave_|leave\b|requirements?|attachment|balance|pending|history|summary|overlap/i.test(activeIntent || enriched)) {
    return `${enriched} (${leaveTypeLabel})`;
  }
  return enriched;
}

function buildToolData(intent, context) {
  if (intent === 'today_dtr') {
    return {
      dateRange: context.date_range,
      record: context.dtr_records?.[0] || null,
    };
  }
  if (
    intent === 'missing_logs' ||
    intent === 'dtr_daily_record' ||
    intent === 'dtr_range_summary' ||
    intent === 'dtr_missing_logs' ||
    intent === 'dtr_missing_log_reason' ||
    intent === 'dtr_late_summary' ||
    intent === 'dtr_late_reason' ||
    intent === 'dtr_undertime_summary' ||
    intent === 'dtr_overtime_summary' ||
    intent === 'dtr_absent_summary' ||
    intent === 'dtr_status_explanation' ||
    intent === 'dtr_correction_guidance' ||
    intent === 'dtr_leave_coverage_check' ||
    intent === 'dtr_locator_coverage_check' ||
    intent === 'dtr_holiday_check' ||
    intent === 'dtr_schedule_context' ||
    intent === 'dtr_export_guidance' ||
    intent === 'dtr_policy_guidance'
  ) {
    return {
      dateRange: context.date_range,
      records: context.dtr_records || [],
      calendarDays: context.dtr_calendar_days || [],
      leaveRequests: context.recent_leave_requests || [],
      locatorSlips: context.recent_locator_slips || [],
      dtrPolicies: context.dtr_policies || [],
      locatorPolicies: context.locator_policies || [],
    };
  }
  if (intent === 'leave_balance' || intent === 'leave_balance_projection') {
    return {
      balances: context.leave_balances || [],
    };
  }
  if (intent === 'dtr_hours_summary') {
    return {
      dateRange: context.date_range,
      records: context.dtr_records || [],
    };
  }
  if (
    intent === 'pending_leave_requests' ||
    intent === 'approved_leave_requests' ||
    intent === 'rejected_leave_requests' ||
    intent === 'leave_history' ||
    intent === 'leave_overlap_check' ||
    intent === 'leave_pending_days_explanation' ||
    intent === 'leave_request_summary' ||
    intent === 'leave_rejection_reason' ||
    intent === 'leave_approval_tracker' ||
    intent === 'leave_approval_history' ||
    intent === 'leave_request_lookup'
  ) {
    return {
      dateRange: context.date_range,
      requests: context.recent_leave_requests || [],
    };
  }
  if (intent === 'leave_availability_check' || intent === 'leave_balance_after_filing') {
    return {
      balances: context.leave_balances || [],
      leaveTypes: context.leave_types || [],
      leaveGuidelines: context.leave_guidelines || [],
      leaveGuidelineCatalog: context.leave_guideline_catalog || [],
    };
  }
  if (
    intent === 'leave_types' ||
    intent === 'leave_attachment_requirement' ||
    intent === 'leave_filing_policy' ||
    intent === 'leave_form_guidance' ||
    intent === 'leave_form_field_help' ||
    intent === 'leave_eligibility_check' ||
    intent === 'leave_dtr_impact' ||
    intent === 'leave_guideline_section' ||
    intent === 'leave_type_compare' ||
    intent === 'leave_guided_filing'
  ) {
    return {
      employee: context.employee || null,
      balances: context.leave_balances || [],
      requests: context.recent_leave_requests || [],
      leaveTypes: context.leave_types || [],
      leaveGuidelines: context.leave_guidelines || [],
      leaveGuidelineCatalog: context.leave_guideline_catalog || [],
    };
  }
  if (intent === 'leave_requirements') {
    return {
      leaveTypes: context.leave_types || [],
      leaveGuidelines: context.leave_guidelines || [],
      leaveGuidelineCatalog: context.leave_guideline_catalog || [],
    };
  }
  if (intent === 'latest_leave_request') {
    return {
      request: context.recent_leave_requests?.[0] || null,
    };
  }
  if (intent === 'latest_locator_request') {
    return {
      slip: context.recent_locator_slips?.[0] || null,
      locatorTypes: context.locator_types || [],
    };
  }
  if (
    intent === 'locator_status' ||
    intent === 'locator_summary' ||
    intent === 'locator_types' ||
    intent === 'locator_requirements' ||
    intent === 'locator_form_field_help' ||
    intent === 'locator_guided_filing' ||
    intent === 'locator_availability_check' ||
    intent === 'locator_rejection_reason' ||
    intent === 'locator_approval_tracker'
  ) {
    return {
      dateRange: context.date_range,
      slips: context.recent_locator_slips || [],
      locatorTypes: context.locator_types || [],
      locatorPolicies: context.locator_policies || [],
      dtrRecords: context.dtr_records || [],
      calendarDays: context.dtr_calendar_days || [],
      dtrPolicies: context.dtr_policies || [],
    };
  }
  return {};
}

async function refineToolAnswerWithLocalAi({ text, intent, toolAnswer, toolData, profile }) {
  try {
    const result = await chatCompletion({
      provider: profile?.provider,
      model: profile?.model,
      messages: buildDtrAssistantToolAnswerMessages({
        message: text,
        intent,
        toolAnswer,
        toolData,
      }),
      temperature: 0.2,
      timeoutMs: 12000,
      options: {
        num_predict: 140,
        num_ctx: 1024,
      },
    });
    const content = compactAssistantContent(result.content);
    if (!content) return null;
    return {
      content,
      provider: result.provider,
      model: result.model,
    };
  } catch (err) {
    console.warn(
      '[dtr-assistant] Tool-answer refinement failed:',
      err.code || err.message
    );
    return null;
  }
}

async function classifyIntentWithLocalAi(text, profile) {
  try {
    const result = await chatCompletion({
      provider: profile?.provider,
      model: profile?.model,
      messages: buildDtrAssistantIntentMessages({ message: text }),
      temperature: 0,
      timeoutMs: 15000,
      options: {
        num_predict: 32,
        num_ctx: 512,
      },
    });
    return {
      intent: parseIntentClassifierResponse(result.content),
      provider: result.provider,
      model: result.model,
    };
  } catch (err) {
    return {
      intent: null,
      provider: err.provider || 'ollama',
      model: 'intent-classifier-unavailable',
      error: err.code || err.message,
    };
  }
}

async function planToolWithLocalAi(text, profile) {
  try {
    const result = await chatCompletion({
      provider: profile?.provider,
      model: profile?.model,
      messages: buildDtrAssistantToolPlanMessages({
        message: text,
        today: todayInHrmsTimezone(),
      }),
      temperature: 0,
      timeoutMs: 9000,
      options: {
        num_predict: 140,
        num_ctx: 1024,
      },
      maxTokens: 140,
    });
    const plan = parseToolPlanResponse(result.content);
    return {
      intent: plan?.intent || null,
      dateRange: plan?.dateRange || null,
      normalizedQuestion: plan?.normalizedQuestion || '',
      extraction: plan?.extraction || null,
      provider: result.provider,
      model: result.model,
    };
  } catch (err) {
    return {
      intent: null,
      dateRange: null,
      normalizedQuestion: '',
      provider: err.provider || profile?.provider || 'ollama',
      model: 'tool-planner-unavailable',
      error: err.code || err.message,
    };
  }
}

async function generateDirectAnswerWithAi({ text, context, profile }) {
  const result = await chatCompletion({
    provider: profile.provider,
    model: profile.model,
    messages: buildDtrAssistantDirectMessages({ message: text, context }),
    temperature: 0.2,
    timeoutMs: 20000,
    options: {
      num_predict: 240,
      num_ctx: 2048,
    },
    maxTokens: 240,
  });

  return {
    content: compactAssistantContent(result.content),
    provider: result.provider,
    model: result.model,
  };
}

async function chatWithDtrAssistant(pool, { user, message, intent, modelProfile }) {
  const text = normalizeMessage(message);
  const profile = resolveModelProfile(modelProfile);
  const scope = getEmployeeSelfScope(user);
  const memory = getAssistantMemory(scope.userId);
  const normalizedTextForRules = normalizeAssistantMessageForRules(text);
  const clarificationPatch = memory?.pendingClarification
    ? applyPendingClarificationAnswer(normalizedTextForRules, memory)
    : null;
  const workingMemory = memoryWithClarificationPatch(memory, clarificationPatch);
  const greetingReply = assistantGreetingReply(normalizedTextForRules);
  if (greetingReply) {
    return buildAssistantResult({
      content: greetingReply,
      provider: 'hrms',
      model: 'hrms-greeting-rules',
      modelProfile: profile.id,
      mode: scope.mode,
      context: emptyAssistantContext(
        parseAssistantDateRange(normalizedTextForRules)
      ),
      intent: 'assistant_greeting',
      intentConfidence: 1,
      intentSource: 'greeting_rules',
      attachments: [],
      text: normalizedTextForRules,
      memory,
    });
  }
  const memoryIntent = resolveIntentFromMemory(normalizedTextForRules, workingMemory);
  const effectiveText = enrichMessageWithMemory(
    normalizedTextForRules,
    workingMemory,
    memoryIntent
  );
  const clarificationIntent = workingMemory?.pendingClarification
    ? null
    : clarificationIntentForMessage(
        normalizedTextForRules,
        intent,
        memoryIntent
      );
  if (clarificationIntent) {
    const clarificationContext = emptyAssistantContext(
      parseAssistantDateRange(normalizedTextForRules)
    );
    setAssistantMemory(scope.userId, buildNextAssistantMemory(memory, {
      intent: clarificationIntent,
      text: normalizedTextForRules,
      dateRange: clarificationContext.date_range,
      toolData: {
        reason: clarificationIntent,
      },
      modelProfile: profile.id,
    }));

    return buildAssistantResult({
      content: clarificationContent(clarificationIntent, normalizedTextForRules),
      provider: 'hrms',
      model: 'hrms-clarification-rules',
      modelProfile: profile.id,
      mode: scope.mode,
      context: clarificationContext,
      intent: clarificationIntent,
      intentConfidence: 1,
      intentSource: 'clarification_rules',
      attachments: [],
      text: normalizedTextForRules,
      memory: getAssistantMemory(scope.userId),
    });
  }

  const directOpenCommand = directOpenCommandForMessage(normalizedTextForRules);
  if (directOpenCommand) {
    const actionContext = emptyAssistantContext(
      parseAssistantDateRange(normalizedTextForRules)
    );
    setAssistantMemory(scope.userId, buildNextAssistantMemory(memory, {
      intent: directOpenCommand.intent,
      text: normalizedTextForRules,
      dateRange: actionContext.date_range,
      toolData: {
        reason: 'direct_open_command',
      },
      modelProfile: profile.id,
    }));

    return buildAssistantResult({
      content: directOpenCommand.content,
      provider: 'hrms',
      model: 'hrms-action-rules',
      modelProfile: profile.id,
      mode: scope.mode,
      context: actionContext,
      intent: directOpenCommand.intent,
      intentConfidence: 1,
      intentSource: 'direct_open_command',
      attachments: [],
      text: normalizedTextForRules,
      actions: directOpenCommand.actions,
      memory: getAssistantMemory(scope.userId),
    });
  }

  const scoredIntent = scoreEmployeeAssistantIntent(effectiveText, intent);
  const fallbackMemoryIntent =
    memoryIntent || resolveIntentFromMemory(effectiveText, memory);
  const forcedIntent = normalizeIntent(intent);
  const shouldPreferMemoryIntent = Boolean(fallbackMemoryIntent && !forcedIntent);
  let resolvedIntent = shouldPreferMemoryIntent
    ? fallbackMemoryIntent
    : scoredIntent.intent || fallbackMemoryIntent;
  let intentConfidence = shouldPreferMemoryIntent
    ? 0.9
    : scoredIntent.intent
      ? scoredIntent.confidence
      : fallbackMemoryIntent
        ? 0.72
        : 0;
  let intentNeedsAiPlan = shouldPreferMemoryIntent
    ? false
    : scoredIntent.intent
      ? scoredIntent.needsAiPlan
      : !fallbackMemoryIntent;
  let intentSource = shouldPreferMemoryIntent
    ? 'memory'
    : scoredIntent.intent
      ? scoredIntent.source
      : fallbackMemoryIntent
        ? 'memory'
        : 'unclear';
  let model = 'hrms-intent-rules';
  let provider = 'hrms';
  let plannedDateRange = parseAssistantDateRange(effectiveText);
  let plannedText = effectiveText;
  let plannerExtraction = null;

  if (shouldAskAiForToolPlan({
    resolvedIntent,
    dateRange: plannedDateRange,
    text: effectiveText,
    profile,
    intentConfidence,
    intentNeedsAiPlan,
  })) {
    const planned = await planToolWithLocalAi(effectiveText, profile);
    if (planned.intent) {
      if (!resolvedIntent || intentNeedsAiPlan || intentConfidence < 0.72) {
        resolvedIntent = planned.intent;
        intentConfidence = 0.82;
        intentSource = 'llm_planner';
        intentNeedsAiPlan = false;
      }
      provider = planned.provider || provider;
      model = planned.model || model;
    }
    if (planned.dateRange) {
      plannedDateRange = planned.dateRange;
      provider = planned.provider || provider;
      model = planned.model || model;
    }
    if (planned.normalizedQuestion) {
      plannedText = `${effectiveText} (${planned.normalizedQuestion})`;
    }
    if (planned.extraction) {
      plannerExtraction = planned.extraction;
    }
  }

  const context = await loadEmployeeAssistantContext(pool, {
    userId: scope.userId,
    message: plannedText,
    dateRange: plannedDateRange,
  });

  const mergedExtraction = mergePlannerExtraction(
    extractMessageEntities(plannedText, workingMemory),
    plannerExtraction
  );
  const extractionMemory = memoryWithClarificationPatch(workingMemory, {
    leaveType: mergedExtraction.leaveType,
    locatorType: mergedExtraction.locatorType,
    dateRange: mergedExtraction.dateRange,
    leavePrefill: mergedExtraction.leavePrefill,
    locatorPrefill: mergedExtraction.locatorPrefill,
    pendingClarification: workingMemory?.pendingClarification ?? null,
  });
  if (mergedExtraction.dateRange?.startDate) {
    context.date_range = mergedExtraction.dateRange;
  }

  if (!resolvedIntent) {
    const classified = await classifyIntentWithLocalAi(plannedText, profile);
    resolvedIntent = classified.intent;
    if (resolvedIntent) {
      intentConfidence = 0.76;
      intentSource = 'llm_classifier';
    }
    provider = classified.provider || provider;
    model = classified.model || model;
  }

  if (profile.engine === 'direct' && !resolvedIntent) {
    const direct = await generateDirectAnswerWithAi({
      text: plannedText,
      context,
      profile,
    });

    setAssistantMemory(scope.userId, buildNextAssistantMemory(memory, {
      intent: 'direct_ai',
      text: plannedText,
      leaveType: memoryLeaveTypeForIntent('direct_ai', plannedText, context, memory),
      locatorType: memoryLocatorTypeForIntent('direct_ai', plannedText, memory),
      dateRange: context.date_range,
      toolData: {
        modelProfile: profile.id,
      },
      modelProfile: profile.id,
    }));

    return buildAssistantResult({
      content: direct.content,
      provider: direct.provider,
      model: direct.model,
      modelProfile: profile.id,
      mode: scope.mode,
      context,
      intent: 'direct_ai',
      intentConfidence: 1,
      intentSource: 'direct_ai',
      attachments: [],
      text: plannedText,
      memory: getAssistantMemory(scope.userId),
    });
  }

  const guided = evaluateGuidedClarification({
    intent: resolvedIntent,
    text: plannedText,
    context,
    memory: extractionMemory,
  });
  if (guided?.content) {
    setAssistantMemory(
      scope.userId,
      buildNextAssistantMemory(extractionMemory, {
        intent: resolvedIntent,
        text: plannedText,
        dateRange: context.date_range,
        leaveType:
          guided.pendingClarification?.leaveType ||
          mergedExtraction.leaveType ||
          extractionMemory.leaveType,
        locatorType:
          guided.pendingClarification?.locatorType ||
          mergedExtraction.locatorType ||
          extractionMemory.locatorType,
        pendingClarification: guided.pendingClarification,
        modelProfile: profile.id,
      })
    );

    return buildAssistantResult({
      content: guided.content,
      provider: 'hrms',
      model: 'hrms-guided-clarification',
      modelProfile: profile.id,
      mode: scope.mode,
      context,
      intent: resolvedIntent,
      intentConfidence: Math.max(intentConfidence, 0.85),
      intentSource: 'guided_clarification',
      attachments: [],
      text: plannedText,
      memory: getAssistantMemory(scope.userId),
    });
  }

  const multi = detectMultipleIntents(effectiveText, { explicitIntent: intent });
  if (multi.isMulti && multi.intents.length >= 2 && !workingMemory?.pendingClarification) {
    const multiReplies = [];
    for (const item of multi.intents) {
      const segmentText = item.segment || plannedText;
      const reply = buildFastEmployeeAssistantReply(segmentText, context, item.intent);
      if (reply) {
        multiReplies.push({ intent: item.intent, content: reply });
      }
    }
    if (multiReplies.length >= 2) {
      const combined = combineMultiIntentReplies(multiReplies, effectiveText);
      const primaryIntent = multiReplies[0].intent;
      setAssistantMemory(
        scope.userId,
        buildNextAssistantMemory(extractionMemory, {
          intent: primaryIntent,
          text: plannedText,
          leaveType: memoryLeaveTypeForIntent(
            primaryIntent,
            plannedText,
            context,
            extractionMemory
          ),
          locatorType: memoryLocatorTypeForIntent(
            primaryIntent,
            plannedText,
            extractionMemory
          ),
          dateRange: context.date_range,
          toolData: { reason: 'multi_intent' },
          modelProfile: profile.id,
          pendingClarification: null,
        })
      );

      return buildAssistantResult({
        content: compactAssistantContent(combined),
        provider: 'hrms',
        model: 'hrms-multi-intent',
        modelProfile: profile.id,
        mode: scope.mode,
        context,
        intent: primaryIntent,
        intentConfidence: Math.max(intentConfidence, 0.8),
        intentSource: 'multi_intent',
        attachments: [],
        text: plannedText,
        memory: getAssistantMemory(scope.userId),
      });
    }
  }

  const fastReply = buildFastEmployeeAssistantReply(
    plannedText,
    context,
    resolvedIntent
  );
  if (fastReply) {
    const toolData = buildToolData(resolvedIntent, context);
    const attachments = buildAttachments(resolvedIntent, context, scope.userId);
    const refined = shouldSkipToolRefinement(resolvedIntent)
      ? null
      : await refineToolAnswerWithLocalAi({
          text,
          intent: resolvedIntent,
          toolAnswer: fastReply,
          toolData,
          profile,
        });

    setAssistantMemory(scope.userId, buildNextAssistantMemory(extractionMemory, {
      intent: resolvedIntent,
      text: plannedText,
      leaveType: memoryLeaveTypeForIntent(
        resolvedIntent,
        plannedText,
        context,
        extractionMemory
      ),
      locatorType: memoryLocatorTypeForIntent(
        resolvedIntent,
        plannedText,
        extractionMemory
      ),
      dateRange: context.date_range,
      toolData,
      modelProfile: profile.id,
      pendingClarification: null,
    }));

    return buildAssistantResult({
      content: compactAssistantContent(refined?.content || fastReply),
      provider: refined?.provider || 'hrms',
      model: refined?.model || model,
      modelProfile: profile.id,
      mode: scope.mode,
      context,
      intent: resolvedIntent,
      intentConfidence,
      intentSource,
      attachments,
      text: plannedText,
      memory: getAssistantMemory(scope.userId),
    });
  }

  const fallbackAttachments = buildAttachments(resolvedIntent, context, scope.userId);
  return buildAssistantResult({
    content: gracefulFallbackContent(normalizedTextForRules),
    provider: 'hrms',
    model: 'hrms-graceful-fallback',
    modelProfile: profile.id,
    mode: scope.mode,
    context,
    intent: resolvedIntent,
    intentConfidence,
    intentSource,
    attachments: fallbackAttachments,
    text: plannedText,
    memory,
  });
}

function resetDtrAssistantChat(user) {
  const scope = getEmployeeSelfScope(user);
  clearAssistantMemory(scope.userId);
  return {
    ok: true,
    mode: scope.mode,
  };
}

module.exports = {
  chatWithDtrAssistant,
  resetDtrAssistantChat,
  getDtrAssistantModelProfiles,
  __test: {
    buildActions,
    buildNextAssistantMemory,
    clarificationContent,
    clarificationIntentForMessage,
    directOpenCommandForMessage,
    enrichMessageWithMemory,
    isAmbiguousFilingQuestion,
    isAmbiguousStatusQuestion,
    resolveIntentFromMemory,
    topicForIntent,
  },
};
