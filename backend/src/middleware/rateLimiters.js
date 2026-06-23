const { rateLimit } = require('express-rate-limit');

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

module.exports = {
  generalApiLimiter,
  authLoginLimiter,
  authRegisterLimiter,
  authPasswordResetLimiter,
  authPasswordResetVerifyLimiter,
  authTokenLimiter,
  authPasswordChangeLimiter,
};
