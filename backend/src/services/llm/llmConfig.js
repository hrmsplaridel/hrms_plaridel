const DEFAULT_PROVIDER = 'ollama';
const DEFAULT_OLLAMA_BASE_URL = 'http://127.0.0.1:11434';
const DEFAULT_OLLAMA_MODEL = 'qwen3:4b';
const DEFAULT_GROQ_BASE_URL = 'https://api.groq.com/openai/v1';
const DEFAULT_GROQ_MODEL = 'llama-3.1-8b-instant';
const DEFAULT_TIMEOUT_MS = 60000;

function stripTrailingSlash(value) {
  return String(value || '').replace(/\/+$/, '');
}

function readPositiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value || ''), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function getLlmConfig(env = process.env) {
  const provider = String(env.LLM_PROVIDER || DEFAULT_PROVIDER)
    .trim()
    .toLowerCase();

  return {
    provider,
    timeoutMs: readPositiveInt(env.LLM_TIMEOUT_MS, DEFAULT_TIMEOUT_MS),
    ollama: {
      baseUrl: stripTrailingSlash(env.OLLAMA_BASE_URL || DEFAULT_OLLAMA_BASE_URL),
      model: String(env.OLLAMA_MODEL || DEFAULT_OLLAMA_MODEL).trim(),
    },
    openai: {
      apiKey: String(env.OPENAI_API_KEY || '').trim(),
      model: String(env.OPENAI_MODEL || '').trim(),
    },
    groq: {
      baseUrl: stripTrailingSlash(env.GROQ_BASE_URL || DEFAULT_GROQ_BASE_URL),
      apiKey: String(env.GROQ_API_KEY || '').trim(),
      model: String(env.GROQ_MODEL || DEFAULT_GROQ_MODEL).trim(),
    },
  };
}

module.exports = {
  getLlmConfig,
  DEFAULT_PROVIDER,
  DEFAULT_OLLAMA_BASE_URL,
  DEFAULT_OLLAMA_MODEL,
  DEFAULT_GROQ_BASE_URL,
  DEFAULT_GROQ_MODEL,
  DEFAULT_TIMEOUT_MS,
};
