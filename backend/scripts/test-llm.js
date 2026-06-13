require('dotenv').config();

const { chatCompletion } = require('../src/services/llm/llmClient');
const { getLlmConfig } = require('../src/services/llm/llmConfig');

async function main() {
  const config = getLlmConfig();
  const result = await chatCompletion({
    messages: [
      {
        role: 'system',
        content: 'You are a concise health check responder.',
      },
      {
        role: 'user',
        content: 'Reply with exactly: DTR Assistant ready',
      },
    ],
    temperature: 0,
  });

  console.log(JSON.stringify({
    ok: true,
    provider: result.provider,
    model: result.model,
    configuredProvider: config.provider,
    content: result.content.trim(),
  }, null, 2));
}

main().catch((err) => {
  console.error(JSON.stringify({
    ok: false,
    code: err.code || 'UNKNOWN_ERROR',
    provider: err.provider || null,
    status: err.status || null,
    providerCode: err.providerCode || null,
    providerMessage: err.providerMessage || err.message,
  }, null, 2));
  process.exit(1);
});
