const https = require('https');
const { URL } = require('url');

const UNISMS_SEND_URL =
  process.env.UNISMS_SEND_URL || 'https://unismsapi.com/api/sms';

function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function isUniSmsConfigured() {
  return Boolean((process.env.UNISMS_API_SECRET_KEY || '').trim());
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

function toE164PhilippinesNumber(normalizedDigits) {
  if (!normalizedDigits) return null;
  return `+${normalizedDigits}`;
}

function buildPasswordResetMessage(code, ttlMinutes) {
  const template =
    process.env.UNISMS_PASSWORD_RESET_TEMPLATE ||
    'Your HRMS Plaridel password reset code is {otp}. It expires in {minutes} minutes. Do not share this code.';

  return template
    .replace(/\{otp\}/g, String(code))
    .replace(/\{minutes\}/g, String(ttlMinutes));
}

function postJson(url, body, apiSecretKey) {
  return new Promise((resolve, reject) => {
    const bodyBuf = Buffer.from(JSON.stringify(body), 'utf8');
    const u = new URL(url);
    const basicAuth = Buffer.from(`${apiSecretKey}:`).toString('base64');

    const req = https.request(
      {
        hostname: u.hostname,
        path: `${u.pathname}${u.search}`,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          Authorization: `Basic ${basicAuth}`,
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

          const err = new Error(`UniSMS HTTP ${code}: ${text}`);
          err.code = 'UNISMS_HTTP_ERROR';
          err.httpStatus = code;
          err.responseText = text;
          reject(err);
        });
      },
    );

    req.on('error', reject);
    req.setTimeout(parsePositiveInt(process.env.UNISMS_TIMEOUT_MS, 20_000), () => {
      req.destroy();
      const err = new Error('UniSMS request timeout');
      err.code = 'UNISMS_TIMEOUT';
      reject(err);
    });
    req.write(bodyBuf);
    req.end();
  });
}

async function sendPasswordResetOtpSms({ to, code, ttlMinutes }) {
  const apiSecretKey = (process.env.UNISMS_API_SECRET_KEY || '').trim();
  if (!apiSecretKey) {
    const err = new Error('UniSMS is not configured. Set UNISMS_API_SECRET_KEY.');
    err.code = 'UNISMS_NOT_CONFIGURED';
    throw err;
  }

  const number = normalizePhilippinesMobileNumber(to);
  const recipient = toE164PhilippinesNumber(number);
  if (!recipient) {
    const err = new Error('Recipient phone number is not a valid Philippine mobile number.');
    err.code = 'INVALID_PH_MOBILE_NUMBER';
    throw err;
  }

  const payload = {
    recipient,
    content: buildPasswordResetMessage(code, ttlMinutes),
  };

  const senderId = (process.env.UNISMS_SENDER_ID || '').trim().slice(0, 11);
  if (senderId) payload.sender_id = senderId;

  const response = await postJson(UNISMS_SEND_URL, payload, apiSecretKey);
  return { provider: 'unisms', number, recipient, response };
}

module.exports = {
  isUniSmsConfigured,
  normalizePhilippinesMobileNumber,
  sendPasswordResetOtpSms,
};
