class LlmError extends Error {
  constructor(message, options = {}) {
    super(message);
    this.name = 'LlmError';
    this.code = options.code || 'AI_PROVIDER_FAILED';
    this.status = options.status || null;
    this.provider = options.provider || null;
    this.providerCode = options.providerCode || null;
    this.providerMessage = options.providerMessage || null;
    this.detail = options.detail || null;
    this.cause = options.cause;
  }
}

module.exports = { LlmError };
