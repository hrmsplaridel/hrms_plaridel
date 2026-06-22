const https = require('https');
const { URL, URLSearchParams } = require('url');

const SEMAPHORE_OTP_URL =
  process.env.SEMAPHORE_OTP_URL || 'https://api.semaphore.co/api/v4/otp';

function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function isSemaphoreConfigured() {
  return Boolean((process.env.SEMAPHORE_API_KEY || '').trim());
}

function normalizePhilippinesMobileNumber(value) {
  if (value == null) return null;
  let digits = String(value).trim();
  if (!digits) return null;

  digits = digits.replace(/[^\d+]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  if (digits.startsWith('00')) digits = digits.slice(2);

  if (/^09\d{9}$/.test(digits)) return `63${digits.slice(1)}`;
  if (/^9\d{9}$/.test(digits)) return `63${digits}`;
  if (/^639\d{9}$/.test(digits)) return digits;

  return null;
}

function buildPasswordResetTemplate(ttlMinutes) {
  const template =
    process.env.SEMAPHORE_PASSWORD_RESET_TEMPLATE ||
    process.env.SEMAPHORE_OTP_TEMPLATE ||
    'Your HRMS Plaridel password reset code is {otp}. It expires in {minutes} minutes. Do not share this code.';

  return template.replace(/\{minutes\}/g, String(ttlMinutes));
}

function postForm(url, params) {
  return new Promise((resolve, reject) => {
    const body = new URLSearchParams(params).toString();
    const bodyBuf = Buffer.from(body, 'utf8');
    const u = new URL(url);

    const req = https.request(
      {
        hostname: u.hostname,
        path: `${u.pathname}${u.search}`,
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': bodyBuf.length,
        },
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          const code = res.statusCode || 0;
          if (code >= 200 && code < 300) {
            try {
              resolve(text ? JSON.parse(text) : null);
            } catch (_) {
              resolve(text);
            }
            return;
          }

          const err = new Error(`Semaphore HTTP ${code}: ${text}`);
          err.code = 'SEMAPHORE_HTTP_ERROR';
          err.httpStatus = code;
          err.responseText = text;
          reject(err);
        });
      },
    );

    req.on('error', reject);
    req.setTimeout(parsePositiveInt(process.env.SEMAPHORE_TIMEOUT_MS, 20_000), () => {
      req.destroy();
      const err = new Error('Semaphore request timeout');
      err.code = 'SEMAPHORE_TIMEOUT';
      reject(err);
    });
    req.write(bodyBuf);
    req.end();
  });
}

async function sendPasswordResetOtpSms({ to, code, ttlMinutes }) {
  const apiKey = (process.env.SEMAPHORE_API_KEY || '').trim();
  if (!apiKey) {
    const err = new Error('Semaphore SMS is not configured. Set SEMAPHORE_API_KEY.');
    err.code = 'SEMAPHORE_NOT_CONFIGURED';
    throw err;
  }

  const number = normalizePhilippinesMobileNumber(to);
  if (!number) {
    const err = new Error('Recipient phone number is not a valid Philippine mobile number.');
    err.code = 'INVALID_PH_MOBILE_NUMBER';
    throw err;
  }

  const params = {
    apikey: apiKey,
    number,
    message: buildPasswordResetTemplate(ttlMinutes),
    code,
  };

  const senderName = (process.env.SEMAPHORE_SENDER_NAME || '').trim();
  if (senderName) params.sendername = senderName;

  const response = await postForm(SEMAPHORE_OTP_URL, params);
  return { provider: 'semaphore', number, response };
}

module.exports = {
  isSemaphoreConfigured,
  normalizePhilippinesMobileNumber,
  sendPasswordResetOtpSms,
};
