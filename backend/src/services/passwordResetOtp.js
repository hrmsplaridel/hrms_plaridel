const crypto = require('crypto');
const PASSWORD_RESET_OTP_TTL_MS = parsePositiveInt(
  process.env.AUTH_PASSWORD_RESET_OTP_TTL_MS,
  5 * 60 * 1000
);
const PASSWORD_RESET_MAX_ATTEMPTS = parsePositiveInt(
  process.env.AUTH_PASSWORD_RESET_OTP_MAX_ATTEMPTS,
  5
);
const PASSWORD_RESET_MIN_PASSWORD_LENGTH = parsePositiveInt(
  process.env.AUTH_PASSWORD_RESET_MIN_PASSWORD_LENGTH,
  8
);
const PASSWORD_RESET_OTP_DIGITS = Math.min(
  8,
  Math.max(4, parsePositiveInt(process.env.AUTH_PASSWORD_RESET_OTP_DIGITS, 6))
);
function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function getPasswordResetSecret() {
  const secret = (
    process.env.AUTH_PASSWORD_RESET_OTP_SECRET ||
    process.env.JWT_SECRET ||
    ''
  ).trim();
  if (!secret) {
    const err = new Error('AUTH_PASSWORD_RESET_OTP_SECRET or JWT_SECRET is required');
    err.code = 'PASSWORD_RESET_SECRET_MISSING';
    throw err;
  }
  return secret;
}

function createOtpCode() {
  const upperBound = 10 ** PASSWORD_RESET_OTP_DIGITS;
  return String(crypto.randomInt(0, upperBound)).padStart(
    PASSWORD_RESET_OTP_DIGITS,
    '0'
  );
}

function hashPasswordResetCode(userId, code) {
  return crypto
    .createHmac('sha256', getPasswordResetSecret())
    .update(`${userId}:${String(code).trim()}`)
    .digest('hex');
}

function timingSafeEqualHex(left, right) {
  const leftBuf = Buffer.from(String(left || ''), 'hex');
  const rightBuf = Buffer.from(String(right || ''), 'hex');
  if (leftBuf.length !== rightBuf.length) return false;
  return crypto.timingSafeEqual(leftBuf, rightBuf);
}

function passwordResetTtlMinutes() {
  return Math.max(1, Math.ceil(PASSWORD_RESET_OTP_TTL_MS / 60_000));
}


module.exports = { createOtpCode, hashPasswordResetCode, timingSafeEqualHex, passwordResetTtlMinutes, PASSWORD_RESET_OTP_TTL_MS, PASSWORD_RESET_MAX_ATTEMPTS, PASSWORD_RESET_MIN_PASSWORD_LENGTH, PASSWORD_RESET_OTP_DIGITS };
