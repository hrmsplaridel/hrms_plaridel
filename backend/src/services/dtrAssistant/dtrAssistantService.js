const { chatCompletion } = require('../llm/llmClient');
const { loadEmployeeAssistantContext } = require('./dtrAssistantDataService');
const { buildFastEmployeeAssistantReply } = require('./dtrAssistantFastReply');
const {
  detectEmployeeAssistantIntent,
  normalizeIntent,
} = require('./dtrAssistantIntentService');
const { getEmployeeSelfScope } = require('./dtrAssistantPermissionService');
const { buildDtrAssistantMessages, buildDtrAssistantIntentMessages } = require('./dtrAssistantPrompt');

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

function buildAssistantResult({ content, provider, model, mode, context, intent }) {
  return {
    message: {
      role: 'assistant',
      content,
      createdAt: new Date().toISOString(),
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
      /\b(today_dtr|missing_logs|leave_balance|latest_leave_request|latest_locator_request|unknown)\b/i
    );
    return normalizeIntent(match?.[1]);
  }
}

function ollamaUnavailableMessage() {
  return 'Sorry, I could not generate an answer right now because the AI service is unavailable. You can still ask about your DTR status, missing logs, leave balance, leave requests, or locator slips.';
}

async function generateAnswerWithOllama(text, context) {
  try {
    const result = await chatCompletion({
      messages: buildDtrAssistantMessages({ message: text, context }),
      temperature: 0.3,
      options: {
        num_predict: 512,
        num_ctx: 4096,
      },
    });
    return {
      content: result.content.trim(),
      provider: result.provider,
      model: result.model,
    };
  } catch (err) {
    console.warn('[dtr-assistant] Ollama answer generation failed:', err.code || err.message);
    return {
      content: ollamaUnavailableMessage(),
      provider: err.provider || 'ollama',
      model: 'unavailable',
    };
  }
}

async function classifyIntentWithLocalAi(text) {
  try {
    const result = await chatCompletion({
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

async function chatWithDtrAssistant(pool, { user, message, intent }) {
  const text = normalizeMessage(message);
  const scope = getEmployeeSelfScope(user);
  const context = await loadEmployeeAssistantContext(pool, {
    userId: scope.userId,
    message: text,
  });

  let resolvedIntent = detectEmployeeAssistantIntent(text, intent);
  let model = 'hrms-intent-rules';
  let provider = 'hrms';

  if (!resolvedIntent) {
    const classified = await classifyIntentWithLocalAi(text);
    resolvedIntent = classified.intent;
    provider = classified.provider || provider;
    model = classified.model || model;
  }

  const fastReply = buildFastEmployeeAssistantReply(text, context, resolvedIntent);
  if (fastReply) {
    return buildAssistantResult({
      content: fastReply,
      provider: 'hrms',
      model,
      mode: scope.mode,
      context,
      intent: resolvedIntent,
    });
  }

  // No fast reply matched — use Ollama to generate a free-form answer.
  const llmAnswer = await generateAnswerWithOllama(text, context);
  return buildAssistantResult({
    content: llmAnswer.content,
    provider: llmAnswer.provider,
    model: llmAnswer.model,
    mode: scope.mode,
    context,
    intent: resolvedIntent,
  });
}

module.exports = { chatWithDtrAssistant };
