const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createOllamaProvider,
} = require('../src/services/llm/ollamaProvider');
const {
  createGroqProvider,
} = require('../src/services/llm/groqProvider');

function response({ ok = true, status = 200, body }) {
  const text = typeof body === 'string' ? body : JSON.stringify(body);
  return {
    ok,
    status,
    text: async () => text,
    json: async () => JSON.parse(text),
  };
}

test('Ollama provider sends bounded options and parses a valid answer', async (t) => {
  const previousFetch = global.fetch;
  let captured = null;
  global.fetch = async (url, options) => {
    captured = { url, options, body: JSON.parse(options.body) };
    return response({
      body: { message: { content: 'Maayo ang imong DTR.' } },
    });
  };
  t.after(() => {
    global.fetch = previousFetch;
  });

  const provider = createOllamaProvider({
    timeoutMs: 100,
    ollama: {
      baseUrl: 'http://127.0.0.1:11434',
      model: 'qwen-test',
    },
  });
  const result = await provider.chatCompletion({
    messages: [{ role: 'user', content: 'Kumusta akong DTR?' }],
    temperature: 0.2,
    options: { num_predict: 100, num_ctx: 2048 },
    keep_alive: '1h',
  });

  assert.equal(result.provider, 'ollama');
  assert.equal(result.content, 'Maayo ang imong DTR.');
  assert.equal(captured.url, 'http://127.0.0.1:11434/api/chat');
  assert.equal(captured.body.stream, false);
  assert.equal(captured.body.keep_alive, '1h');
  assert.equal(captured.body.options.num_predict, 100);
  assert.equal(captured.body.options.num_ctx, 2048);
});

test('Ollama provider classifies timeout, unavailable, model, and malformed failures', async (t) => {
  const previousFetch = global.fetch;
  t.after(() => {
    global.fetch = previousFetch;
  });
  const provider = createOllamaProvider({
    timeoutMs: 5,
    ollama: {
      baseUrl: 'http://127.0.0.1:11434',
      model: 'missing-model',
    },
  });

  global.fetch = async (_url, options) =>
    new Promise((_resolve, reject) => {
      options.signal.addEventListener('abort', () => {
        const error = new Error('aborted');
        error.name = 'AbortError';
        reject(error);
      });
    });
  await assert.rejects(
    provider.chatCompletion({ messages: [] }),
    (error) => error.code === 'AI_PROVIDER_TIMEOUT'
  );

  global.fetch = async () => {
    throw new Error('connection refused');
  };
  await assert.rejects(
    provider.chatCompletion({ messages: [] }),
    (error) => error.code === 'AI_LOCAL_UNAVAILABLE'
  );

  global.fetch = async () =>
    response({
      ok: false,
      status: 404,
      body: { error: 'model not found' },
    });
  await assert.rejects(
    provider.chatCompletion({ messages: [] }),
    (error) =>
      error.code === 'AI_PROVIDER_FAILED' &&
      error.providerCode === 'model_not_found' &&
      /ollama pull missing-model/i.test(error.providerMessage)
  );

  global.fetch = async () =>
    response({
      body: { unexpected: true },
    });
  await assert.rejects(
    provider.chatCompletion({ messages: [] }),
    (error) => error.code === 'AI_PROVIDER_MALFORMED_RESPONSE'
  );
});

test('Groq provider handles configuration and provider errors safely', async (t) => {
  const previousFetch = global.fetch;
  t.after(() => {
    global.fetch = previousFetch;
  });

  const unconfigured = createGroqProvider({
    timeoutMs: 50,
    groq: {
      baseUrl: 'https://api.groq.com/openai/v1',
      apiKey: '',
      model: 'llama-test',
    },
  });
  await assert.rejects(
    unconfigured.chatCompletion({ messages: [] }),
    (error) => error.code === 'AI_PROVIDER_NOT_CONFIGURED'
  );

  const configured = createGroqProvider({
    timeoutMs: 50,
    groq: {
      baseUrl: 'https://api.groq.com/openai/v1',
      apiKey: 'test-key',
      model: 'llama-test',
    },
  });
  global.fetch = async () =>
    response({
      ok: false,
      status: 429,
      body: {
        error: {
          code: 'rate_limit_exceeded',
          message: 'Too many requests',
        },
      },
    });
  await assert.rejects(
    configured.chatCompletion({ messages: [] }),
    (error) =>
      error.code === 'AI_PROVIDER_FAILED' &&
      error.providerCode === 'rate_limit_exceeded' &&
      error.providerMessage === 'Too many requests'
  );

  global.fetch = async () =>
    response({
      body: { choices: [] },
    });
  await assert.rejects(
    configured.chatCompletion({ messages: [] }),
    (error) => error.code === 'AI_PROVIDER_MALFORMED_RESPONSE'
  );
});
