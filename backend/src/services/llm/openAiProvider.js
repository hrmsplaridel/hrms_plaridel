const { LlmError } = require('./llmErrors');

function createOpenAiProvider() {
  async function chatCompletion() {
    throw new LlmError('OpenAI provider is not implemented yet.', {
      code: 'AI_PROVIDER_UNSUPPORTED',
      provider: 'openai',
    });
  }

  return { chatCompletion };
}

module.exports = { createOpenAiProvider };
