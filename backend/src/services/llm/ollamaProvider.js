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

function createOllamaProvider(config) {
  const baseUrl = config.ollama.baseUrl;
  const defaultModel = config.ollama.model;
  const defaultTimeoutMs = config.timeoutMs;

  async function chatCompletion(options = {}) {
    const model = String(options.model || defaultModel).trim();
    const timeoutMs = options.timeoutMs || defaultTimeoutMs;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    let response;
    try {
      response = await fetch(`${baseUrl}/api/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        signal: options.signal || controller.signal,
        body: JSON.stringify({
          model,
          stream: false,
          keep_alive: options.keepAlive ?? options.keep_alive ?? '1h',
          format: options.format,
          options: {
            temperature: options.temperature ?? 0.2,
            num_predict: options.numPredict ?? options.num_predict ?? 100,
            num_ctx: options.numCtx ?? options.num_ctx ?? 2048,
            ...(options.options || {}),
          },
          messages: options.messages || [],
        }),
      });
    } catch (cause) {
      const timedOut = cause?.name === 'AbortError';
      throw new LlmError(
        timedOut
          ? 'Local AI provider timed out.'
          : 'Local AI is not available. Start Ollama and pull the configured model.',
        {
          code: timedOut ? 'AI_PROVIDER_TIMEOUT' : 'AI_LOCAL_UNAVAILABLE',
          provider: 'ollama',
          cause,
        }
      );
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      const body = await readProviderBody(response);
      const modelNotFound =
        response.status === 404 ||
        /model.*not.*found|not found/i.test(body.text || body.json?.error || '');

      throw new LlmError(`Local AI provider failed (${response.status}).`, {
        code: 'AI_PROVIDER_FAILED',
        status: response.status,
        provider: 'ollama',
        providerCode: modelNotFound ? 'model_not_found' : null,
        providerMessage: modelNotFound
          ? `Ollama model '${model}' is not available. Run: ollama pull ${model}`
          : compactText(body.json?.error || body.text, 500),
        detail: compactText(body.text, 500),
      });
    }

    const data = await response.json().catch((cause) => {
      throw new LlmError('Local AI provider returned invalid JSON.', {
        code: 'AI_PROVIDER_MALFORMED_RESPONSE',
        provider: 'ollama',
        cause,
      });
    });

    const content = data?.message?.content;
    if (typeof content !== 'string') {
      throw new LlmError('Local AI provider returned an empty response.', {
        code: 'AI_PROVIDER_MALFORMED_RESPONSE',
        provider: 'ollama',
        detail: compactText(JSON.stringify(data), 500),
      });
    }

    return {
      provider: 'ollama',
      model,
      content,
      raw: data,
    };
  }

  return { chatCompletion };
}

module.exports = { createOllamaProvider };
