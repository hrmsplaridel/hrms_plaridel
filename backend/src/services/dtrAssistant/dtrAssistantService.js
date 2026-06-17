const crypto = require('crypto');
const { chatCompletion } = require('../llm/llmClient');
const { getLlmConfig } = require('../llm/llmConfig');
const { loadEmployeeAssistantContext } = require('./dtrAssistantDataService');
const {
  buildFastEmployeeAssistantReply,
  requestedLeaveType,
  requestedLocatorType,
} = require('./dtrAssistantFastReply');
const {
  getAssistantMemory,
  setAssistantMemory,
} = require('./dtrAssistantMemoryService');
const {
  detectEmployeeAssistantIntent,
  normalizeIntent,
} = require('./dtrAssistantIntentService');
const { getEmployeeSelfScope } = require('./dtrAssistantPermissionService');
const { normalizeAssistantMessageForRules } = require('./dtrAssistantTextNormalizer');
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

const MAX_ASSISTANT_REPLY_CHARS = 900;
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
    dtrSummaryIds: context.dtr_records.map((r) => r.id),
    leaveRequestIds: context.recent_leave_requests.map((r) => r.id),
    locatorSlipIds: context.recent_locator_slips.map((r) => r.id),
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
    value === 'locator_availability_check' ||
    value === 'locator_rejection_reason' ||
    value === 'locator_approval_tracker'
  );
}

function topicForIntent(intent) {
  if (isStructuredDtrIntent(intent)) return 'dtr';
  if (isLeaveIntent(intent)) return 'leave';
  if (isLocatorIntent(intent)) return 'locator';
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
    ['dtr', 'leave', 'locator', 'direct'].includes(String(intentOrTopic || ''))
      ? intentOrTopic
      : topicForIntent(intentOrTopic || memory.intent);
  if (!topic) return memory;
  return memory.topics?.[topic] || (memory.topic === topic ? memory : null) || memory;
}

function strictMemoryTopicState(memory, topic) {
  if (!memory || !topic) return null;
  return memory.topics?.[topic] || (memory.topic === topic ? memory : null);
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
  return (
    requestedLocatorType(effectiveText) ||
    locatorMemory?.locatorType ||
    memory?.locatorType ||
    null
  );
}

function buildNextAssistantMemory(previous, next) {
  const topic = topicForIntent(next.intent);
  const previousTopicState = strictMemoryTopicState(previous, topic) || {};
  const leaveType =
    next.leaveType || (topic === 'leave' ? previousTopicState.leaveType : previous?.leaveType) || null;
  const locatorType =
    next.locatorType || (topic === 'locator' ? previousTopicState.locatorType : previous?.locatorType) || null;
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
    topics[topic] = {
      intent: next.intent || previousTopicState.intent || null,
      topic,
      dateRange: next.dateRange || previousTopicState.dateRange || null,
      leaveType: topic === 'leave' ? leaveType : previousTopicState.leaveType || null,
      locatorType: topic === 'locator' ? locatorType : previousTopicState.locatorType || null,
      toolData: next.toolData || previousTopicState.toolData || null,
      updatedAt: turn.createdAt,
    };
  }

  return {
    intent: next.intent || previous?.intent || null,
    topic,
    leaveType,
    locatorType,
    dateRange: next.dateRange || previous?.dateRange || null,
    toolData: next.toolData || null,
    modelProfile: next.modelProfile || previous?.modelProfile || null,
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
    intent === 'dtr_overtime_summary'
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
    intent === 'locator_availability_check' ||
    intent === 'locator_rejection_reason' ||
    intent === 'locator_approval_tracker' ||
    intent === 'dtr_locator_coverage_check'
  ) {
    return [
      { text: 'What is my locator status?', intent: 'locator_status' },
      { text: 'What locator types can I file?', intent: 'locator_types' },
      { text: 'Can I file locator tomorrow?', intent: 'locator_availability_check' },
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

function buildAssistantResult({ content, provider, model, mode, context, intent, attachments }) {
  return {
    message: {
      id: crypto.randomUUID(),
      role: 'assistant',
      content: compactAssistantContent(content),
      createdAt: new Date().toISOString(),
      intent: intent || null,
      provider: provider || null,
      model: model || null,
      suggestions: buildSuggestions(intent),
      attachments: attachments || [],
    },
    provider,
    model,
    mode,
    intent: intent || null,
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
      /\b(today_dtr|missing_logs|dtr_daily_record|dtr_range_summary|dtr_missing_logs|dtr_missing_log_reason|dtr_late_summary|dtr_late_reason|dtr_undertime_summary|dtr_overtime_summary|dtr_absent_summary|dtr_status_explanation|dtr_correction_guidance|dtr_leave_coverage_check|dtr_locator_coverage_check|dtr_holiday_check|dtr_schedule_context|dtr_export_guidance|leave_balance|pending_leave_requests|approved_leave_requests|rejected_leave_requests|leave_history|leave_availability_check|leave_attachment_requirement|leave_overlap_check|leave_pending_days_explanation|leave_balance_after_filing|leave_request_summary|leave_filing_policy|leave_form_guidance|leave_eligibility_check|leave_dtr_impact|leave_guideline_section|leave_type_compare|leave_guided_filing|leave_approval_history|leave_rejection_reason|leave_approval_tracker|leave_request_lookup|leave_types|leave_requirements|latest_leave_request|latest_locator_request|locator_status|locator_summary|locator_types|locator_requirements|locator_availability_check|locator_rejection_reason|locator_approval_tracker|unknown)\b/i
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
  };
}

function dateRangeLooksDefaultToday(dateRange, text) {
  if (!dateRange || dateRange.label !== 'today') return false;
  return !/\b(today|karong adlawa|karon nga adlaw|ngayon)\b/i.test(String(text || ''));
}

function shouldAskAiForToolPlan({ resolvedIntent, dateRange, text, profile }) {
  if (!profile || profile.engine === 'direct') return false;
  if (!resolvedIntent) return true;
  if (dateRangeLooksDefaultToday(dateRange, text)) return true;
  return false;
}

function fallbackContent() {
  return 'I can help only with your DTR, missing logs, late/undertime/overtime, absences, DTR correction guidance, leave balances, leave requests/history, leave availability checks, leave filing rules, leave attachments, leave overlaps, leave eligibility, leave form guidance, leave DTR impact, approval tracking, leave summaries, leave types, locator slip status, locator summaries, locator requirements, locator filing checks, locator rejection reasons, locator approval tracking, and locator DTR coverage.';
}

function isFollowUpQuestion(text) {
  return /\b(it|that|this|one|same|about|how about|what about|ana|ato|adto|niya|same day|same date|next day|following day|sunod adlaw|previous day|day before|today|tomorrow|yesterday|ugma|gahapon|kagahapon|week|month|semana|semanaha|bulan|bulana|buwan|buwana|aning|karong|ngayong|ngano|why|bakit|pila|unsa|ano|how many|status|approved|pending|rejected|requirements?|remarks?|reason|who|where|asa|kinsa|sino|can|file|pwede|puwede|allowed|eligible)\b/.test(
    lower(text)
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

function resolveIntentFromMemory(text, memory) {
  if (!memory || !isFollowUpQuestion(text)) return null;
  const value = lower(text);
  const memoryTopic = memory.topic || topicForIntent(memory.intent);
  const explicitTopic = explicitTopicFromText(text);
  if (explicitTopic && memoryTopic && explicitTopic !== memoryTopic) return null;
  const activeMemory = memoryTopicState(memory, explicitTopic || memoryTopic) || memory;
  const activeIntent = activeMemory.intent || memory.intent;
  const locatorTypeFollowUp =
    isLocatorIntent(activeIntent) &&
    /\b(types?|kinds?|options?|how about|what about|wfh|work from home|pass slip|official business|ob|on field|fieldwork|field work)\b/.test(value);
  if (!locatorTypeFollowUp && explicitTopic && explicitTopic !== memoryTopic) return null;
  if (isLocatorIntent(activeIntent)) {
    if (/\b(can file|can i file|pwede|puwede|allowed|eligible|qualified|available|tomorrow|ugma|karon|today|date|day|file)\b/.test(value)) {
      return 'locator_availability_check';
    }
    if (
      locatorTypeFollowUp &&
      !/\b(status|approved|approve|pending|rejected|returned|cancelled|canceled|latest|last|recent|remarks|reason|who|where|asa|kinsa|sino|holding|waiting)\b/.test(value)
    ) {
      return 'locator_types';
    }
    if (/\b(why|ngano|bakit|reason|remarks|comment|rejected|reject|declined|denied|gi reject|gireject|same reason)\b/.test(value)) {
      return 'locator_rejection_reason';
    }
    if (/\b(who|kinsa|sino|where|asa|kanino|holding|hold|pending with|waiting|awaiting)\b/.test(value)) {
      return 'locator_approval_tracker';
    }
    if (/\b(requirement|requirements|attachment|document|docs|need|needed|kinahanglan|kailangan|rule|rules|policy|how to file|unsaon|paano)\b/.test(value)) {
      return 'locator_requirements';
    }
    if (/\b(summary|total|count|counts|pila|ilan|how many|history|list|show)\b/.test(value)) {
      return 'locator_summary';
    }
    if (/\b(types?|kinds?|options?|available.*locator|locator.*available)\b/.test(value)) {
      return 'locator_types';
    }
    if (/\b(status|approved|approve|pending|rejected|cancelled|canceled|where|asa|kinsa|sino|who|holding|waiting|remarks|reason|ngano|bakit|why)\b/.test(value)) {
      return 'locator_status';
    }
    return activeIntent;
  }
  if (isStructuredDtrIntent(activeIntent)) {
    if (/\b(fix|correct|correction|buhaton|gagawin|resolve)\b/.test(value)) {
      return 'dtr_correction_guidance';
    }
    if (/\b(absent|absence|no record|walay record)\b/.test(value)) {
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
    if (/\b(status|same day|same date|that day|that date|ana|ato|adto|niya|today|tomorrow|yesterday|ugma|gahapon|kagahapon)\b/.test(value)) {
      return activeIntent;
    }
  }
  if (isLeaveIntent(activeIntent)) {
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
  if (/\b(leave|on leave|covered)\b/.test(lower(text))) {
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
  if (/\b(absent|absence|no record|walay record)\b/.test(lower(text))) {
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
  if (/\b(requirement|requirements|needed|need|kinahanglan|kailangan)\b/.test(lower(text))) {
    return 'leave_requirements';
  }
  if (/\b(fill|field|fields|form|details|what to put|i-fill|input)\b/.test(lower(text))) {
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
  const relativeDate = memoryRelativeDate(enriched, activeMemory);
  if (relativeDate) {
    enriched = `${enriched} (${relativeDate})`;
  }
  const hasDateHint =
    /\b(today|tomorrow|yesterday|ugma|kagahapon|gahapon|karon|week|semana|semanaha|month|bulan|bulana|buwan|buwana|aning bulana|sunod|miaging|niaging|adtong|adtung|atong|niadtong|niadtung|noong|nung|next day|following day|sunod adlaw|previous day|day before|same day|same date|ana|ato|adto|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\b/i.test(
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
    const canUseRememberedLocatorType =
      isFollowUpQuestion(text) || isLocatorIntent(activeIntent);
    const locatorType =
      requestedLocatorType(enriched) ||
      (canUseRememberedLocatorType
        ? activeMemory?.locatorType || (!explicitTopic ? memory?.locatorType : null)
        : null);
    if (locatorType && !requestedLocatorType(enriched)) {
      const locatorTypeLabel = locatorType.replace(/_/g, ' ');
      if (
        /locator_|locator\b|requirements?|attachment|types?|status|summary|approved|pending|rejected|how about|what about|can|file|pwede|puwede/i.test(
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
    intent === 'dtr_export_guidance'
  ) {
    return {
      dateRange: context.date_range,
      records: context.dtr_records || [],
      calendarDays: context.dtr_calendar_days || [],
      leaveRequests: context.recent_leave_requests || [],
      locatorSlips: context.recent_locator_slips || [],
    };
  }
  if (intent === 'leave_balance') {
    return {
      balances: context.leave_balances || [],
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
    };
  }
  if (
    intent === 'leave_types' ||
    intent === 'leave_attachment_requirement' ||
    intent === 'leave_filing_policy' ||
    intent === 'leave_form_guidance' ||
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
    };
  }
  if (intent === 'leave_requirements') {
    return {
      leaveTypes: context.leave_types || [],
      leaveGuidelines: context.leave_guidelines || [],
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
    intent === 'locator_availability_check' ||
    intent === 'locator_rejection_reason' ||
    intent === 'locator_approval_tracker'
  ) {
    return {
      dateRange: context.date_range,
      slips: context.recent_locator_slips || [],
      locatorTypes: context.locator_types || [],
      dtrRecords: context.dtr_records || [],
      calendarDays: context.dtr_calendar_days || [],
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
  const memoryIntent = resolveIntentFromMemory(normalizedTextForRules, memory);
  const effectiveText = enrichMessageWithMemory(
    normalizedTextForRules,
    memory,
    memoryIntent
  );
  let resolvedIntent =
    detectEmployeeAssistantIntent(effectiveText, intent) ||
    memoryIntent ||
    resolveIntentFromMemory(effectiveText, memory);
  let model = 'hrms-intent-rules';
  let provider = 'hrms';
  let plannedDateRange = parseAssistantDateRange(effectiveText);
  let plannedText = effectiveText;

  if (shouldAskAiForToolPlan({
    resolvedIntent,
    dateRange: plannedDateRange,
    text: effectiveText,
    profile,
  })) {
    const planned = await planToolWithLocalAi(effectiveText, profile);
    if (planned.intent) {
      resolvedIntent = resolvedIntent || planned.intent;
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
  }

  const context = await loadEmployeeAssistantContext(pool, {
    userId: scope.userId,
    message: plannedText,
    dateRange: plannedDateRange,
  });

  if (!resolvedIntent) {
    const classified = await classifyIntentWithLocalAi(plannedText, profile);
    resolvedIntent = classified.intent;
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
      mode: scope.mode,
      context,
      intent: 'direct_ai',
      attachments: [],
    });
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

    setAssistantMemory(scope.userId, buildNextAssistantMemory(memory, {
      intent: resolvedIntent,
      text: plannedText,
      leaveType: memoryLeaveTypeForIntent(resolvedIntent, plannedText, context, memory),
      locatorType: memoryLocatorTypeForIntent(resolvedIntent, plannedText, memory),
      dateRange: context.date_range,
      toolData,
      modelProfile: profile.id,
    }));

    return buildAssistantResult({
      content: compactAssistantContent(refined?.content || fastReply),
      provider: refined?.provider || 'hrms',
      model: refined?.model || model,
      mode: scope.mode,
      context,
      intent: resolvedIntent,
      attachments,
    });
  }

  return buildAssistantResult({
    content: fallbackContent(),
    provider,
    model,
    mode: scope.mode,
    context,
    intent: resolvedIntent,
    attachments: buildAttachments(resolvedIntent, context, scope.userId),
  });
}

module.exports = {
  chatWithDtrAssistant,
  getDtrAssistantModelProfiles,
  __test: {
    buildNextAssistantMemory,
    enrichMessageWithMemory,
    resolveIntentFromMemory,
    topicForIntent,
  },
};
