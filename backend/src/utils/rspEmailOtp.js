const crypto = require('crypto');

const OTP_TTL_MS = Number(process.env.RSP_EMAIL_OTP_TTL_MS || 600_000); // 10 min
const SEND_WINDOW_MS = Number(process.env.RSP_EMAIL_OTP_SEND_WINDOW_MS || 900_000); // 15 min
const MAX_SENDS_PER_WINDOW = Number(process.env.RSP_EMAIL_OTP_MAX_SENDS_PER_WINDOW || 4);
const MAX_VERIFY_ATTEMPTS = Number(process.env.RSP_EMAIL_OTP_MAX_VERIFY_ATTEMPTS || 10);

/** @typedef {{ codeHashHex: string, expiresAt: number, attempts: number }} OtpRecord */

/** @type {Map<string, OtpRecord>} */
const otpByEmail = new Map();
/** @type {Map<string, number[]>} */
const sendTimestampsByEmail = new Map();

function getOtpHmacSecret() {
  const s = (
    process.env.RSP_EMAIL_OTP_SECRET ||
    process.env.JWT_SECRET ||
    ''
  ).trim();
  return s || null;
}

function normalizeEmail(email) {
  return String(email || '')
    .trim()
    .toLowerCase();
}

function hashCode(emailNorm, rawCode) {
  const secret = getOtpHmacSecret();
  if (!secret) throw new Error('RSP_EMAIL_OTP_SECRET or JWT_SECRET is required for email OTP');
  return crypto
    .createHmac('sha256', secret)
    .update(`${emailNorm}:${String(rawCode).trim().replace(/\s+/g, '')}`)
    .digest('hex');
}

function generateSixDigitCode() {
  const n = crypto.randomInt(0, 1_000_000);
  return String(n).padStart(6, '0');
}

function pruneSendTimestamps(emailNorm, now = Date.now()) {
  let arr = sendTimestampsByEmail.get(emailNorm) || [];
  arr = arr.filter((t) => now - t < SEND_WINDOW_MS);
  sendTimestampsByEmail.set(emailNorm, arr);
  return arr;
}

/**
 * Issue a new OTP (overwrites prior). Throws if rate limited or secret missing (caller handles).
 * @returns {{ code: string, waitMs?: number }}
 */
function issueNewOtp(email) {
  const emailNorm = normalizeEmail(email);
  if (!emailNorm) {
    const err = new Error('email is required');
    err.code = 'BAD_EMAIL';
    throw err;
  }
  const secret = getOtpHmacSecret();
  if (!secret) {
    const err = new Error('Server is not configured for email OTP signing');
    err.code = 'OTP_SECRET_MISSING';
    throw err;
  }

  const now = Date.now();
  const timestamps = pruneSendTimestamps(emailNorm, now);
  if (timestamps.length >= MAX_SENDS_PER_WINDOW) {
    const oldestInWindow = Math.min(...timestamps);
    const waitMs = SEND_WINDOW_MS - (now - oldestInWindow);
    const err = new Error(`Too many codes sent. Try again in ${Math.ceil(waitMs / 1000)} seconds.`);
    err.code = 'RATE_LIMIT_SEND';
    err.waitMs = Math.max(0, waitMs);
    throw err;
  }

  const code = generateSixDigitCode();
  const codeHashHex = hashCode(emailNorm, code);

  otpByEmail.set(emailNorm, {
    codeHashHex,
    expiresAt: now + OTP_TTL_MS,
    attempts: 0,
  });

  timestamps.push(now);
  sendTimestampsByEmail.set(emailNorm, timestamps);

  return { code };
}

/**
 * Returns true only if code matches active OTP for this email.
 * @returns {boolean}
 */
function consumeOtpIfValid(email, rawCode) {
  const emailNorm = normalizeEmail(email);
  const rec = otpByEmail.get(emailNorm);
  if (!rec) return false;
  const now = Date.now();
  if (now > rec.expiresAt) {
    otpByEmail.delete(emailNorm);
    return false;
  }
  if (rec.attempts >= MAX_VERIFY_ATTEMPTS) {
    otpByEmail.delete(emailNorm);
    return false;
  }
  let expected;
  try {
    expected = hashCode(emailNorm, rawCode);
  } catch {
    return false;
  }
  try {
    const a = Buffer.from(expected, 'hex');
    const b = Buffer.from(rec.codeHashHex, 'hex');
    if (a.length !== b.length) {
      rec.attempts++;
      return false;
    }
    const ok = crypto.timingSafeEqual(a, b);
    if (!ok) {
      rec.attempts++;
      return false;
    }
    otpByEmail.delete(emailNorm);
    return true;
  } catch {
    rec.attempts++;
    return false;
  }
}

function clearOtpForEmail(email) {
  otpByEmail.delete(normalizeEmail(email));
}

/** Prune stale map entries periodically (restart-safe). */
function pruneExpiredOtps(now = Date.now()) {
  for (const [k, v] of otpByEmail) {
    if (now > v.expiresAt + 60_000) otpByEmail.delete(k);
  }
}

{
  const t = setInterval(() => pruneExpiredOtps(), 120_000);
  if (typeof t.unref === 'function') t.unref();
}

module.exports = {
  isRspEmailOtpCryptoConfigured() {
    return !!getOtpHmacSecret();
  },
  normalizeEmail,
  generateSixDigitCode,
  issueNewOtp,
  consumeOtpIfValid,
  clearOtpForEmail,
  OTP_TTL_MS,
};
