const { LlmError } = require('./llmErrors');

function compactText(value, max = 500) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1)}...`;
}

async function readProviderBody(response) {
  const text = await response.text().catch(() => '');
  if (!text) return { text: '', json: null };
  try {
    return { text, json: JSON.parse(text) };
  } catch (_) {
    return { text, json: null };
  }
}

function createGroqProvider(config) {
  const baseUrl = config.groq.baseUrl;
  const apiKey = config.groq.apiKey;
  const defaultModel = config.groq.model;
  const defaultTimeoutMs = config.timeoutMs;

  async function chatCompletion(options = {}) {
    if (!apiKey) {
      throw new LlmError('Groq API key is not configured.', {
        code: 'AI_PROVIDER_NOT_CONFIGURED',
        provider: 'groq',
        providerMessage: 'Set GROQ_API_KEY in backend/.env and restart PM2.',
      });
    }

    const model = String(options.model || defaultModel).trim();
    const timeoutMs = options.timeoutMs || defaultTimeoutMs;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    let response;
    try {
      response = await fetch(`${baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        signal: options.signal || controller.signal,
        body: JSON.stringify({
          model,
          messages: options.messages || [],
          temperature: options.temperature ?? 0.2,
          max_tokens: options.maxTokens ?? options.max_tokens ?? options.numPredict ?? 180,
          stream: false,
        }),
      });
    } catch (cause) {
      const timedOut = cause?.name === 'AbortError';
      throw new LlmError(
        timedOut ? 'Groq provider timed out.' : 'Groq provider is not available.',
        {
          code: timedOut ? 'AI_PROVIDER_TIMEOUT' : 'AI_PROVIDER_UNAVAILABLE',
          provider: 'groq',
          cause,
        }
      );
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      const body = await readProviderBody(response);
      throw new LlmError(`Groq provider failed (${response.status}).`, {
        code: 'AI_PROVIDER_FAILED',
        status: response.status,
        provider: 'groq',
        providerCode: body.json?.error?.code || null,
        providerMessage: compactText(body.json?.error?.message || body.text, 500),
        detail: compactText(body.text, 500),
      });
    }

    const data = await response.json().catch((cause) => {
      throw new LlmError('Groq provider returned invalid JSON.', {
        code: 'AI_PROVIDER_MALFORMED_RESPONSE',
        provider: 'groq',
        cause,
      });
    });

    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== 'string') {
      throw new LlmError('Groq provider returned an empty response.', {
        code: 'AI_PROVIDER_MALFORMED_RESPONSE',
        provider: 'groq',
        detail: compactText(JSON.stringify(data), 500),
      });
    }

    return {
      provider: 'groq',
      model,
      content,
      raw: data,
    };
  }

  return { chatCompletion };
}

module.exports = { createGroqProvider };
