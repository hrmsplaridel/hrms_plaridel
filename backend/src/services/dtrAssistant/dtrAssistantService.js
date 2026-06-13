const { chatCompletion } = require('../llm/llmClient');
const { getLlmConfig } = require('../llm/llmConfig');
const { loadEmployeeAssistantContext } = require('./dtrAssistantDataService');
const {
  buildFastEmployeeAssistantReply,
  requestedLeaveType,
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
const {
  buildDtrAssistantDirectMessages,
  buildDtrAssistantIntentMessages,
  buildDtrAssistantToolAnswerMessages,
} = require('./dtrAssistantPrompt');

const MAX_ASSISTANT_REPLY_CHARS = 900;

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
  const text = String(content || '').replace(/\s+/g, ' ').trim();
  if (text.length <= MAX_ASSISTANT_REPLY_CHARS) return text;
  return `${text.slice(0, MAX_ASSISTANT_REPLY_CHARS - 3).trim()}...`;
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
  if (intent === 'latest_leave_request' || intent === 'leave_approval_tracker') {
    return [
      { text: 'Who is holding my leave request?', intent: 'leave_approval_tracker' },
      { text: 'Why was my leave returned or rejected?', intent: 'leave_rejection_reason' },
      { text: 'Show my leave history this month', intent: 'leave_history' },
    ];
  }
  if (intent === 'leave_history' || intent === 'leave_request_summary') {
    return [
      { text: 'Summarize my leave this month', intent: 'leave_request_summary' },
      { text: 'Show approved leave this month', intent: 'approved_leave_requests' },
      { text: 'Show rejected leave requests', intent: 'rejected_leave_requests' },
    ];
  }
  return [
    { text: 'What is my leave balance?', intent: 'leave_balance' },
    { text: 'Show my pending leave requests', intent: 'pending_leave_requests' },
  ];
}

function buildAssistantResult({ content, provider, model, mode, context, intent }) {
  return {
    message: {
      role: 'assistant',
      content: compactAssistantContent(content),
      createdAt: new Date().toISOString(),
      suggestions: buildSuggestions(intent),
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
      /\b(today_dtr|missing_logs|leave_balance|pending_leave_requests|approved_leave_requests|rejected_leave_requests|leave_history|leave_availability_check|leave_attachment_requirement|leave_overlap_check|leave_pending_days_explanation|leave_balance_after_filing|leave_request_summary|leave_filing_policy|leave_rejection_reason|leave_approval_tracker|leave_types|leave_requirements|latest_leave_request|latest_locator_request|unknown)\b/i
    );
    return normalizeIntent(match?.[1]);
  }
}

function fallbackContent() {
  return 'I can help only with your DTR, missing logs, leave balances, leave requests/history, leave availability checks, leave filing rules, leave attachments, leave overlaps, leave approval tracking, leave summaries, leave types, and locator slip status. Try asking about your DTR today, missing logs this week, sick/vacation leave balance, pending leave requests, or locator status.';
}

function hasExplicitHrmsTopic(text) {
  return /\b(dtr|attendance|log|logs|leave|locator|pass slip|wfh|official business|sick|vacation|vl|sl)\b/.test(
    lower(text)
  );
}

function isFollowUpQuestion(text) {
  return /\b(it|that|this|one|same|about|how about|what about|ngano|why|bakit|pila|unsa|ano|how many|status|approved|pending|rejected|requirements?)\b/.test(
    lower(text)
  );
}

function resolveIntentFromMemory(text, memory) {
  if (!memory || hasExplicitHrmsTopic(text) || !isFollowUpQuestion(text)) return null;
  if (/\b(attachment|attachments|document|documents|docs|proof|supporting|medical certificate|med cert)\b/.test(lower(text))) {
    return 'leave_attachment_requirement';
  }
  if (/\b(policy|rule|rules|advance|before|deadline|max|maximum|limit|past date)\b/.test(lower(text))) {
    return 'leave_filing_policy';
  }
  if (/\b(who|kinsa|sino|where|asa|holding|waiting|awaiting|pending with)\b/.test(lower(text))) {
    return 'leave_approval_tracker';
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
  if (memory.intent === 'leave_balance' && /\b(why|ngano|bakit|gamay|low|small|nabilin|natira)\b/.test(lower(text))) {
    return 'leave_balance';
  }
  if (
    [
      'leave_balance',
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
      'leave_rejection_reason',
      'leave_approval_tracker',
      'leave_requirements',
      'leave_types',
    ].includes(memory.intent)
  ) {
    return memory.intent;
  }
  return null;
}

function enrichMessageWithMemory(text, memory) {
  const leaveType = requestedLeaveType(text) || memory?.leaveType;
  if (!leaveType) return text;
  if (requestedLeaveType(text)) return text;
  const leaveTypeLabel = /\bleave\b/i.test(leaveType)
    ? leaveType
    : `${leaveType} leave`;
  if (
    memory?.intent === 'leave_balance' &&
    /\b(why|ngano|bakit|gamay|low|small|nabilin|natira)\b/.test(lower(text))
  ) {
    return `${text} (${leaveTypeLabel})`;
  }
  if (/leave_|leave\b|requirements?|attachment|balance|pending|history|summary|overlap/i.test(memory?.intent || text)) {
    return `${text} (${leaveTypeLabel})`;
  }
  return text;
}

function buildToolData(intent, context) {
  if (intent === 'today_dtr') {
    return {
      dateRange: context.date_range,
      record: context.dtr_records?.[0] || null,
    };
  }
  if (intent === 'missing_logs') {
    return {
      dateRange: context.date_range,
      records: context.dtr_records || [],
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
    intent === 'leave_approval_tracker'
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
    };
  }
  if (
    intent === 'leave_types' ||
    intent === 'leave_attachment_requirement' ||
    intent === 'leave_filing_policy'
  ) {
    return {
      leaveTypes: context.leave_types || [],
    };
  }
  if (intent === 'leave_requirements') {
    return {
      leaveTypes: context.leave_types || [],
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
  const effectiveText = enrichMessageWithMemory(text, memory);
  const context = await loadEmployeeAssistantContext(pool, {
    userId: scope.userId,
    message: effectiveText,
  });

  if (profile.engine === 'direct') {
    const direct = await generateDirectAnswerWithAi({
      text: effectiveText,
      context,
      profile,
    });

    setAssistantMemory(scope.userId, {
      intent: 'direct_ai',
      leaveType:
        requestedLeaveType(effectiveText) ||
        inferLeaveTypeFromContext(effectiveText, context) ||
        memory?.leaveType ||
        null,
      dateRange: context.date_range,
      toolData: {
        modelProfile: profile.id,
      },
    });

    return buildAssistantResult({
      content: direct.content,
      provider: direct.provider,
      model: direct.model,
      mode: scope.mode,
      context,
      intent: 'direct_ai',
    });
  }

  let resolvedIntent =
    detectEmployeeAssistantIntent(effectiveText, intent) ||
    resolveIntentFromMemory(text, memory);
  let model = 'hrms-intent-rules';
  let provider = 'hrms';

  if (!resolvedIntent) {
    const classified = await classifyIntentWithLocalAi(effectiveText, profile);
    resolvedIntent = classified.intent;
    provider = classified.provider || provider;
    model = classified.model || model;
  }

  const fastReply = buildFastEmployeeAssistantReply(
    effectiveText,
    context,
    resolvedIntent
  );
  if (fastReply) {
    const toolData = buildToolData(resolvedIntent, context);
    const refined = await refineToolAnswerWithLocalAi({
      text,
      intent: resolvedIntent,
      toolAnswer: fastReply,
      toolData,
      profile,
    });

    setAssistantMemory(scope.userId, {
      intent: resolvedIntent,
      leaveType:
        requestedLeaveType(effectiveText) ||
        inferLeaveTypeFromContext(effectiveText, context) ||
        memory?.leaveType ||
        null,
      dateRange: context.date_range,
      toolData,
      modelProfile: profile.id,
    });

    return buildAssistantResult({
      content: refined?.content || fastReply,
      provider: refined?.provider || 'hrms',
      model: refined?.model || model,
      mode: scope.mode,
      context,
      intent: resolvedIntent,
    });
  }

  return buildAssistantResult({
    content: fallbackContent(),
    provider,
    model,
    mode: scope.mode,
    context,
    intent: resolvedIntent,
  });
}

module.exports = { chatWithDtrAssistant, getDtrAssistantModelProfiles };
