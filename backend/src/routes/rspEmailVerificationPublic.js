const express = require('express');
const {
  isEmailJsRspOtpConfigured,
  sendRspEmailOtpEmailJs,
} = require('../utils/emailJsMail');
const {
  isRspEmailOtpCryptoConfigured,
  normalizeEmail,
  issueNewOtp,
  consumeOtpIfValid,
  OTP_TTL_MS,
} = require('../utils/rspEmailOtp');
const {
  signRspEmailVerificationToken,
  getRspEmailVerifySecretConfigured,
} = require('../utils/rspEmailVerifyToken');

const router = express.Router();

const EMAIL_RE = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;

function otpFlowFullyConfigured() {
  return (
    isEmailJsRspOtpConfigured() &&
    isRspEmailOtpCryptoConfigured() &&
    getRspEmailVerifySecretConfigured()
  );
}

/** GET /api/rsp/email-verification/config */
router.get('/config', (_req, res) => {
  const configured = otpFlowFullyConfigured();
  return res.json({
    otpEnabled: configured,
    /** When true, client must verify email before POST /applications from Step 1. */
    requiresOtpForNewApplication: configured,
    otpTtlMs: OTP_TTL_MS,
  });
});

/** POST /api/rsp/email-verification/send */
router.post('/send', async (req, res) => {
  try {
    if (!otpFlowFullyConfigured()) {
      return res.status(503).json({
        error: 'Email verification is not configured on the server',
        code: 'EMAIL_OTP_NOT_CONFIGURED',
        details:
          'Set EMAILJS_SERVICE_ID, EMAILJS_PUBLIC_KEY, EMAILJS_TEMPLATE_RSP_EMAIL_OTP_ID, and JWT_SECRET (or RSP_EMAIL_OTP_SECRET + RSP_EMAIL_VERIFY_JWT_SECRET).',
      });
    }

    const raw = req.body?.email;
    const email =
      typeof raw === 'string' ? raw.trim() : '';

    if (!email || email.length > 254 || !EMAIL_RE.test(email)) {
      return res.status(400).json({ error: 'A valid email address is required' });
    }

    let code;
    try {
      ({ code } = issueNewOtp(email));
    } catch (err) {
      const codeHint = err?.code ? String(err.code) : '';
      if (codeHint === 'RATE_LIMIT_SEND' && typeof err.waitMs === 'number') {
        return res.status(429).json({
          error: err.message || 'Too many requests',
          retryAfterSeconds: Math.ceil(err.waitMs / 1000),
        });
      }
      console.error('[rspEmailVerification send]', err);
      return res.status(500).json({
        error: err?.message ? String(err.message) : 'Could not send code',
      });
    }

    const expiryMinutes = Math.max(1, Math.round(OTP_TTL_MS / 60_000));
    const rawName = req.body?.fullName ?? req.body?.applicantName;
    const applicantName =
      typeof rawName === 'string' ? rawName.trim().slice(0, 160) : '';

    await sendRspEmailOtpEmailJs({
      to: normalizeEmail(email),
      verificationCode: code,
      expiryMinutes,
      ...(applicantName ? { applicantName } : {}),
    });

    return res.json({ ok: true, expiresInSeconds: Math.round(OTP_TTL_MS / 1000) });
  } catch (err) {
    console.error('[rspEmailVerification send EmailJS]', err);
    const msg = err?.message ? String(err.message) : String(err);
    return res.status(500).json({
      error: 'Failed to send verification email',
      details: msg,
    });
  }
});

/** POST /api/rsp/email-verification/verify */
router.post('/verify', async (req, res) => {
  try {
    if (!otpFlowFullyConfigured()) {
      return res.status(503).json({
        error: 'Email verification is not configured on the server',
        code: 'EMAIL_OTP_NOT_CONFIGURED',
      });
    }

    const rawEmail = req.body?.email;
    const rawCode = req.body?.code;

    const email =
      typeof rawEmail === 'string' ? rawEmail.trim() : '';
    const code =
      typeof rawCode === 'string' ? rawCode.trim().replace(/\s+/g, '') : '';

    if (!email || !EMAIL_RE.test(email)) {
      return res.status(400).json({ error: 'A valid email address is required' });
    }
    if (!/^\d{6}$/.test(code)) {
      return res.status(400).json({
        error: 'Enter the 6-digit code from your email',
      });
    }

    const normalized = normalizeEmail(email);
    const ok = consumeOtpIfValid(normalized, code);
    if (!ok) {
      return res.status(400).json({
        error: 'Invalid or expired code. Request a new code and try again.',
        code: 'OTP_INVALID',
      });
    }

    let token;
    try {
      token = signRspEmailVerificationToken(normalized);
    } catch (e) {
      console.error('[rspEmailVerification verify sign]', e);
      return res.status(500).json({ error: 'Could not complete verification' });
    }

    return res.json({
      ok: true,
      emailVerificationToken: token,
      expiresInSeconds: 1800,
    });
  } catch (err) {
    console.error('[rspEmailVerification verify]', err);
    return res.status(500).json({
      error: err?.message ? String(err.message) : String(err),
    });
  }
});

module.exports = router;
module.exports.rspEmailOtpEnrollmentActive = otpFlowFullyConfigured;
