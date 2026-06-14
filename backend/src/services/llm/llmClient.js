const { getLlmConfig } = require('./llmConfig');
const { LlmError } = require('./llmErrors');
const { createGroqProvider } = require('./groqProvider');
const { createOllamaProvider } = require('./ollamaProvider');
const { createOpenAiProvider } = require('./openAiProvider');

function createLlmClient(config = getLlmConfig()) {
  let provider;

  if (config.provider === 'ollama') {
    provider = createOllamaProvider(config);
  } else if (config.provider === 'groq') {
    provider = createGroqProvider(config);
  } else if (config.provider === 'openai') {
    provider = createOpenAiProvider(config);
  } else {
    throw new LlmError(`Unsupported LLM provider '${config.provider}'.`, {
      code: 'AI_PROVIDER_UNSUPPORTED',
      provider: config.provider,
    });
  }

  return {
    provider: config.provider,
    chatCompletion: provider.chatCompletion,
  };
}

async function chatCompletion(options) {
  const config = getLlmConfig();
  if (options?.provider) {
    config.provider = String(options.provider).trim().toLowerCase();
  }
  const client = createLlmClient(config);
  return client.chatCompletion(options);
}

module.exports = {
  createLlmClient,
  chatCompletion,
};
