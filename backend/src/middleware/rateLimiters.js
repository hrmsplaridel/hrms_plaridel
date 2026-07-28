const { ipKeyGenerator, rateLimit } = require('express-rate-limit');
const {
  detectAssistantLanguage,
} = require('../services/dtrAssistant/dtrAssistantLanguage');

const FIVE_MINUTES_MS = 5 * 60 * 1000;
const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;
const ONE_HOUR_MS = 60 * 60 * 1000;

function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function createJsonLimiter({
  windowMs,
  limit,
  message,
  skipSuccessfulRequests = false,
}) {
  return rateLimit({
    windowMs,
    limit,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    skipSuccessfulRequests,
    message: { error: message },
  });
}

function authenticatedEmployeeKey(req) {
  const userId = String(req.user?.id || '').trim();
  if (userId) return `employee:${userId}`;
  return `ip:${ipKeyGenerator(req.ip)}`;
}

function assistantRequestLanguage(req) {
  const message = String(req.body?.message || req.body?.comment || '').trim();
  if (message) return detectAssistantLanguage(message);

  const accepted = String(req.get?.('accept-language') || '').toLowerCase();
  if (/\b(ceb|bisaya|cebuano)\b/.test(accepted)) return 'bisaya';
  if (/\b(tl|fil|tagalog|filipino)\b/.test(accepted)) return 'tagalog';
  return 'english';
}

function assistantRateLimitMessage(req, retryAfterSeconds) {
  const language = assistantRequestLanguage(req);
  if (language === 'bisaya') {
    return `Daghan ra kaayo ang imong chatbot requests. Palihug hulat ug ${retryAfterSeconds} segundos ug sulayi pag-usab.`;
  }
  if (language === 'tagalog') {
    return `Masyadong maraming chatbot requests. Maghintay ng ${retryAfterSeconds} segundo at subukan muli.`;
  }
  return `Too many chatbot requests. Please wait ${retryAfterSeconds} seconds and try again.`;
}

function createEmployeeAssistantLimiter({
  windowMs,
  limit,
  code = 'DTR_ASSISTANT_RATE_LIMITED',
}) {
  return rateLimit({
    windowMs,
    limit,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    keyGenerator: authenticatedEmployeeKey,
    handler: (req, res) => {
      const resetAt = req.rateLimit?.resetTime?.getTime?.() || Date.now() + windowMs;
      const retryAfterSeconds = Math.max(
        1,
        Math.ceil((resetAt - Date.now()) / 1000),
      );
      res.status(429).json({
        error: assistantRateLimitMessage(req, retryAfterSeconds),
        code,
        retryAfterSeconds,
      });
    },
  });
}

const generalApiLimiter = createJsonLimiter({
  windowMs: parsePositiveInt(process.env.RATE_LIMIT_WINDOW_MS, FIFTEEN_MINUTES_MS),
  limit: parsePositiveInt(process.env.RATE_LIMIT_MAX, 300),
  message: 'Too many API requests. Please wait and try again.',
});

const authLoginLimiter = createJsonLimiter({
  windowMs: parsePositiveInt(
    process.env.AUTH_LOGIN_RATE_LIMIT_WINDOW_MS,
    FIFTEEN_MINUTES_MS,
  ),
  limit: parsePositiveInt(process.env.AUTH_LOGIN_RATE_LIMIT_MAX, 5),
  message: 'Too many login attempts. Please wait and try again.',
  skipSuccessfulRequests: true,
});

const authRegisterLimiter = createJsonLimiter({
  windowMs: parsePositiveInt(
    process.env.AUTH_REGISTER_RATE_LIMIT_WINDOW_MS,
    ONE_HOUR_MS,
  ),
  limit: parsePositiveInt(process.env.AUTH_REGISTER_RATE_LIMIT_MAX, 5),
  message: 'Too many registration attempts. Please wait and try again.',
});

const authPasswordResetLimiter = createJsonLimiter({
  windowMs: parsePositiveInt(
    process.env.AUTH_PASSWORD_RESET_RATE_LIMIT_WINDOW_MS,
    FIFTEEN_MINUTES_MS,
  ),
  limit: parsePositiveInt(process.env.AUTH_PASSWORD_RESET_RATE_LIMIT_MAX, 3),
  message: 'Too many password reset attempts. Please wait and try again.',
});

const authPasswordResetVerifyLimiter = createJsonLimiter({
  windowMs: parsePositiveInt(
    process.env.AUTH_PASSWORD_RESET_VERIFY_RATE_LIMIT_WINDOW_MS,
    FIFTEEN_MINUTES_MS,
  ),
  limit: parsePositiveInt(process.env.AUTH_PASSWORD_RESET_VERIFY_RATE_LIMIT_MAX, 10),
  message: 'Too many password reset verification attempts. Please wait and try again.',
});

const authTokenLimiter = createJsonLimiter({
  windowMs: parsePositiveInt(
    process.env.AUTH_TOKEN_RATE_LIMIT_WINDOW_MS,
    FIFTEEN_MINUTES_MS,
  ),
  limit: parsePositiveInt(process.env.AUTH_TOKEN_RATE_LIMIT_MAX, 60),
  message: 'Too many authentication requests. Please wait and try again.',
});

const authPasswordChangeLimiter = createJsonLimiter({
  windowMs: parsePositiveInt(
    process.env.AUTH_PASSWORD_CHANGE_RATE_LIMIT_WINDOW_MS,
    FIFTEEN_MINUTES_MS,
  ),
  limit: parsePositiveInt(process.env.AUTH_PASSWORD_CHANGE_RATE_LIMIT_MAX, 5),
  message: 'Too many password change attempts. Please wait and try again.',
});

const publicSubmissionLimiter = createJsonLimiter({
  windowMs: ONE_HOUR_MS,
  limit: parsePositiveInt(process.env.PUBLIC_SUBMISSION_RATE_LIMIT_MAX, 10),
  message: 'Too many submissions. Please wait and try again.',
});

const publicLookupLimiter = createJsonLimiter({
  windowMs: FIFTEEN_MINUTES_MS,
  limit: parsePositiveInt(process.env.PUBLIC_LOOKUP_RATE_LIMIT_MAX, 30),
  message: 'Too many lookup requests. Please wait and try again.',
});

const dtrAssistantChatBurstLimiter = createEmployeeAssistantLimiter({
  windowMs: parsePositiveInt(
    process.env.DTR_ASSISTANT_CHAT_BURST_WINDOW_MS,
    FIVE_MINUTES_MS,
  ),
  limit: parsePositiveInt(process.env.DTR_ASSISTANT_CHAT_BURST_MAX, 30),
  code: 'DTR_ASSISTANT_CHAT_BURST_LIMITED',
});

const dtrAssistantChatHourlyLimiter = createEmployeeAssistantLimiter({
  windowMs: parsePositiveInt(
    process.env.DTR_ASSISTANT_CHAT_HOURLY_WINDOW_MS,
    ONE_HOUR_MS,
  ),
  limit: parsePositiveInt(process.env.DTR_ASSISTANT_CHAT_HOURLY_MAX, 150),
  code: 'DTR_ASSISTANT_CHAT_HOURLY_LIMITED',
});

const dtrAssistantResetLimiter = createEmployeeAssistantLimiter({
  windowMs: FIFTEEN_MINUTES_MS,
  limit: parsePositiveInt(process.env.DTR_ASSISTANT_RESET_RATE_LIMIT_MAX, 20),
  code: 'DTR_ASSISTANT_RESET_RATE_LIMITED',
});

const dtrAssistantFeedbackLimiter = createEmployeeAssistantLimiter({
  windowMs: FIFTEEN_MINUTES_MS,
  limit: parsePositiveInt(process.env.DTR_ASSISTANT_FEEDBACK_RATE_LIMIT_MAX, 60),
  code: 'DTR_ASSISTANT_FEEDBACK_RATE_LIMITED',
});

const dtrAssistantExportLimiter = createEmployeeAssistantLimiter({
  windowMs: FIFTEEN_MINUTES_MS,
  limit: parsePositiveInt(process.env.DTR_ASSISTANT_EXPORT_RATE_LIMIT_MAX, 30),
  code: 'DTR_ASSISTANT_EXPORT_RATE_LIMITED',
});

module.exports = {
  createEmployeeAssistantLimiter,
  generalApiLimiter,
  authLoginLimiter,
  authRegisterLimiter,
  authPasswordResetLimiter,
  authPasswordResetVerifyLimiter,
  authTokenLimiter,
  authPasswordChangeLimiter,
  publicSubmissionLimiter,
  publicLookupLimiter,
  dtrAssistantChatBurstLimiter,
  dtrAssistantChatHourlyLimiter,
  dtrAssistantResetLimiter,
  dtrAssistantFeedbackLimiter,
  dtrAssistantExportLimiter,
};
