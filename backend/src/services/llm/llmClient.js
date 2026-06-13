const { getLlmConfig } = require('./llmConfig');
const { LlmError } = require('./llmErrors');
const { createOllamaProvider } = require('./ollamaProvider');
const { createOpenAiProvider } = require('./openAiProvider');

function createLlmClient(config = getLlmConfig()) {
  let provider;

  if (config.provider === 'ollama') {
    provider = createOllamaProvider(config);
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
  const client = createLlmClient();
  return client.chatCompletion(options);
}

module.exports = {
  createLlmClient,
  chatCompletion,
};
