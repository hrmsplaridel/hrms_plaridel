/**
 * EmailJS REST API (https://www.emailjs.com/docs/rest-api/send/).
 * Set EMAILJS_SERVICE_ID, EMAILJS_PUBLIC_KEY, and at least one template ID in .env.
 *
 * In EmailJS → Email Templates, map "To Email" to a variable (e.g. {{hr_email}}) or use a fixed HR inbox.
 * Template parameter names below must match what you use in the template body/subject.
 */

const https = require('https');
const { URL } = require('url');

const EMAILJS_SEND_URL = 'https://api.emailjs.com/api/v1.0/email/send';

/** POST JSON to EmailJS (no global fetch; works on Node 16+). */
function postEmailJsJson(jsonBody) {
  return new Promise((resolve, reject) => {
    const bodyBuf = Buffer.from(jsonBody, 'utf8');
    const u = new URL(EMAILJS_SEND_URL);
    const req = https.request(
      {
        hostname: u.hostname,
        path: `${u.pathname}${u.search}`,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': bodyBuf.length,
        },
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          const code = res.statusCode || 0;
          if (code >= 200 && code < 300) {
            resolve({ ok: true });
            return;
          }
          let msg = `EmailJS HTTP ${code}: ${text}`;
          if (
            code === 403 &&
            /non-browser|browser environments/i.test(text)
          ) {
            msg +=
              ' — Enable “Allow EmailJS API for non-browser applications” (or similar) under EmailJS Account → Security: https://dashboard.emailjs.com/admin/account/security';
          }
          if (
            code === 403 &&
            /strict mode|private key|Private Key|accessToken/i.test(text)
          ) {
            msg +=
              ' — Add EMAILJS_PRIVATE_KEY to the API .env (EmailJS → Account → API keys → Private Key; sent as accessToken).';
          }
          if (
            code === 412 &&
            /Gmail|insufficient authentication scopes|scopes/i.test(text)
          ) {
            msg +=
              ' — Reconnect Gmail in EmailJS → Email Services (disconnect service, add Gmail again, grant “Send email” / all requested permissions). Or use another EmailJS service (e.g. Outlook/custom SMTP).';
          }
          const err = new Error(msg);
          err.code = 'EMAILJS_HTTP_ERROR';
          err.httpStatus = code;
          reject(err);
        });
      }
    );
    req.on('error', reject);
    req.setTimeout(25_000, () => {
      req.destroy();
      const err = new Error('EmailJS request timeout');
      err.code = 'EMAILJS_TIMEOUT';
      reject(err);
    });
    req.write(bodyBuf);
    req.end();
  });
}

function getPrivateKey() {
  return (
    process.env.EMAILJS_PRIVATE_KEY ||
    process.env.EMAILJS_ACCESS_TOKEN ||
    ''
  ).trim();
}

function getConfig() {
  const serviceId = (process.env.EMAILJS_SERVICE_ID || '').trim();
  const publicKey = (process.env.EMAILJS_PUBLIC_KEY || '').trim();
  return { serviceId, publicKey };
}

function isEmailJsConfiguredForHr() {
  const { serviceId, publicKey } = getConfig();
  const templateId = (process.env.EMAILJS_TEMPLATE_NEW_APPLICATION_ID || '').trim();
  return !!(serviceId && publicKey && templateId);
}

function isEmailJsConfiguredForApplicant() {
  const { serviceId, publicKey } = getConfig();
  const templateId = (process.env.EMAILJS_TEMPLATE_APPLICANT_CONFIRM_ID || '').trim();
  return !!(serviceId && publicKey && templateId);
}

/**
 * @param {{ templateId: string, templateParams: Record<string, string> }} opts
 */
async function sendEmailJs(opts) {
  const { serviceId, publicKey } = getConfig();
  const templateId = opts.templateId?.trim();
  if (!serviceId || !publicKey || !templateId) {
    const err = new Error('EmailJS is not fully configured');
    err.code = 'EMAILJS_NOT_CONFIGURED';
    throw err;
  }

  const payload = {
    service_id: serviceId,
    template_id: templateId,
    user_id: publicKey,
    template_params: opts.templateParams,
  };
  const privateKey = getPrivateKey();
  if (privateKey) {
    payload.accessToken = privateKey;
  }

  const body = JSON.stringify(payload);

  await postEmailJsJson(body);
  return { ok: true };
}

/**
 * Optional non-blocking notifications after a new recruitment application is stored.
 * @param {import('pg').QueryResultRow} row — row from recruitment_applications RETURNING
 */
async function notifyNewRecruitmentApplication(row) {
  const hrTemplateId = (process.env.EMAILJS_TEMPLATE_NEW_APPLICATION_ID || '').trim();
  const applicantTemplateId = (
    process.env.EMAILJS_TEMPLATE_APPLICANT_CONFIRM_ID || ''
  ).trim();
  if (!hrTemplateId && !applicantTemplateId) return;

  const hrEmail = (process.env.EMAILJS_HR_NOTIFY_TO || '').trim();
  const submittedAt = row.created_at
    ? new Date(row.created_at).toLocaleString('en-PH', {
        timeZone: 'Asia/Manila',
        dateStyle: 'medium',
        timeStyle: 'short',
      })
    : new Date().toISOString();

  const baseParams = {
    applicant_name: String(row.full_name || '').trim(),
    applicant_email: String(row.email || '').trim(),
    applicant_phone: row.phone ? String(row.phone).trim() : '—',
    position_applied_for: row.position_applied_for
      ? String(row.position_applied_for).trim()
      : 'Not specified',
    application_id: String(row.id || ''),
    submitted_at: submittedAt,
  };

  if (hrEmail) {
    baseParams.hr_email = hrEmail;
  }

  if (hrTemplateId) {
    await sendEmailJs({
      templateId: hrTemplateId,
      templateParams: baseParams,
    });
  }

  if (applicantTemplateId && row.email) {
    await sendEmailJs({
      templateId: applicantTemplateId,
      templateParams: {
        ...baseParams,
        // Use in template "To Email" as {{to_email}} so the applicant receives the message
        to_email: String(row.email).trim(),
      },
    });
  }
}

/**
 * Hire credentials email (POST …/send-hire-email). Template must accept dynamic recipient.
 * Env: EMAILJS_TEMPLATE_HIRE_CREDENTIALS_ID + service + public key.
 */
function isEmailJsConfiguredForHireEmail() {
  const { serviceId, publicKey } = getConfig();
  const templateId = (process.env.EMAILJS_TEMPLATE_HIRE_CREDENTIALS_ID || '').trim();
  return !!(serviceId && publicKey && templateId);
}

/**
 * @param {{
 *   to: string,
 *   applicantName: string,
 *   username: string,
 *   password: string,
 *   accountNote: string,
 * }} opts
 */
async function sendHireCredentialsEmailJs(opts) {
  const templateId = (process.env.EMAILJS_TEMPLATE_HIRE_CREDENTIALS_ID || '').trim();
  await sendEmailJs({
    templateId,
    templateParams: {
      to_email: opts.to.trim(),
      applicant_name: opts.applicantName.trim(),
      username: opts.username,
      password: opts.password,
      account_note: opts.accountNote,
    },
  });
}

function isEmailJsContactConfigured() {
  const { serviceId, publicKey } = getConfig();
  const templateId = (process.env.EMAILJS_TEMPLATE_CONTACT_US_ID || '').trim();
  return !!(serviceId && publicKey && templateId);
}

function isEmailJsRspOtpConfigured() {
  const { serviceId, publicKey } = getConfig();
  const templateId = (process.env.EMAILJS_TEMPLATE_RSP_EMAIL_OTP_ID || '').trim();
  return !!(serviceId && publicKey && templateId);
}

/**
 * RSP Step 1 — applicant email OTP (Job Application / LGU Plaridel).
 *
 * EmailJS template (typical): "To Email" = {{to_email}} (applicant inbox).
 *
 * Recommended variables:
 *   {{subject}}        — Email subject text (duplicate in template Subject if EmailJS splits them)
 *   {{to_name}}        — Applicant greeting name (fallback "Applicant")
 *   {{otp_code}}       — six-digit code
 *   {{expiry_minutes}} — number as string (TTL from server minutes)
 *   {{expiry_note}}    — one-line sentence matching {{expiry_minutes}} (e.g. expiry in … minutes.)
 *
 * Legacy aliases still sent for older templates:
 *   {{verification_code}} — same value as otp_code
 */
async function sendRspEmailOtpEmailJs(opts) {
  const templateId = (process.env.EMAILJS_TEMPLATE_RSP_EMAIL_OTP_ID || '').trim();
  const otp = String(opts.verificationCode || '').trim();
  const mins =
    opts.expiryMinutes != null && Number(opts.expiryMinutes) > 0
      ? Math.round(Number(opts.expiryMinutes))
      : 10;
  const expiry_note = `This code will expire in ${mins} minute${mins === 1 ? '' : 's'}.`;
  const toNameRaw = opts.applicantName != null ? String(opts.applicantName).trim() : '';
  const to_name =
    toNameRaw.length > 0 ? toNameRaw.slice(0, 160) : 'Applicant';
  const subject = (
    process.env.EMAILJS_RSP_OTP_SUBJECT ||
    'Verify your email — LGU Plaridel recruitment application'
  )
    .trim()
    .slice(0, 200);

  await sendEmailJs({
    templateId,
    templateParams: {
      to_email: opts.to.trim(),
      subject,
      to_name,
      otp_code: otp,
      expiry_minutes: String(mins),
      expiry_note,
      verification_code: otp,
    },
  });
}

/**
 * Landing page "Contact Us" form — variables must match EmailJS template (title, name, email, message, time).
 */
async function sendContactUsEmailJs(opts) {
  const templateId = (process.env.EMAILJS_TEMPLATE_CONTACT_US_ID || '').trim();
  const time = new Date().toLocaleString('en-PH', {
    timeZone: 'Asia/Manila',
    dateStyle: 'medium',
    timeStyle: 'short',
  });
  await sendEmailJs({
    templateId,
    templateParams: {
      title: opts.title,
      name: opts.name,
      email: opts.email,
      message: opts.message,
      time,
    },
  });
}

module.exports = {
  sendEmailJs,
  isEmailJsConfiguredForHr,
  isEmailJsConfiguredForApplicant,
  isEmailJsConfiguredForHireEmail,
  sendHireCredentialsEmailJs,
  isEmailJsContactConfigured,
  sendContactUsEmailJs,
  isEmailJsRspOtpConfigured,
  sendRspEmailOtpEmailJs,
  notifyNewRecruitmentApplication,
};
