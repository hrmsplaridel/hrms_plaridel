const jwt = require('jsonwebtoken');

function getSecret() {
  return (process.env.RSP_EMAIL_VERIFY_JWT_SECRET || process.env.JWT_SECRET || '').trim();
}

/**
 * Short-lived token issued only after successful email OTP. Must be sent with application create.
 * @param {string} normalizedEmail
 */
function signRspEmailVerificationToken(normalizedEmail) {
  const secret = getSecret();
  if (!secret) {
    const err = new Error('RSP_EMAIL_VERIFY_JWT_SECRET or JWT_SECRET is required');
    err.code = 'VERIFY_JWT_SECRET_MISSING';
    throw err;
  }
  return jwt.sign(
    { typ: 'rsp_email_verify', email: normalizedEmail },
    secret,
    { expiresIn: '30m' },
  );
}

/**
 * @param {string} token
 * @param {string} normalizedEmail — must match token payload
 * @returns {boolean}
 */
function verifyRspEmailVerificationToken(token, normalizedEmail) {
  const secret = getSecret();
  if (!secret || !token || typeof token !== 'string') return false;
  const em = String(normalizedEmail || '')
    .trim()
    .toLowerCase();
  if (!em) return false;
  try {
    const p = jwt.verify(token.trim(), secret);
    if (!p || p.typ !== 'rsp_email_verify') return false;
    const tokenEmail =
      typeof p.email === 'string'
        ? p.email.trim().toLowerCase()
        : '';
    return tokenEmail === em && tokenEmail.length > 3;
  } catch {
    return false;
  }
}

function signRspApplicantAccessToken(applicationId, normalizedEmail) {
  const secret = getSecret();
  if (!secret) throw new Error('RSP applicant token secret is required');
  return jwt.sign(
    { typ: 'rsp_applicant', applicationId: String(applicationId), email: normalizedEmail },
    secret,
    { expiresIn: '24h' },
  );
}

function verifyRspApplicantAccessToken(token, applicationId, normalizedEmail) {
  const secret = getSecret();
  if (!secret || !token) return false;
  try {
    const payload = jwt.verify(String(token).trim(), secret);
    return payload.typ === 'rsp_applicant' &&
      String(payload.applicationId) === String(applicationId) &&
      String(payload.email || '').trim().toLowerCase() === String(normalizedEmail || '').trim().toLowerCase();
  } catch (_) {
    return false;
  }
}

module.exports = {
  signRspEmailVerificationToken,
  verifyRspEmailVerificationToken,
  signRspApplicantAccessToken,
  verifyRspApplicantAccessToken,
  getRspEmailVerifySecretConfigured: () => !!getSecret(),
};
