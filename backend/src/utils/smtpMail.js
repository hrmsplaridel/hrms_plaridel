const nodemailer = require('nodemailer');

function getSmtpOptions() {
  const host = (process.env.SMTP_HOST || '').trim();
  const user = (process.env.SMTP_USER || '').trim();
  const pass = (process.env.SMTP_PASS || '').trim();
  const from = (process.env.SMTP_FROM || user).trim();
  if (!host || !user || !pass || !from) return null;
  const port = Number(process.env.SMTP_PORT || '587');
  const secure =
    process.env.SMTP_SECURE === 'true' ||
    process.env.SMTP_SECURE === '1' ||
    port === 465;
  return { host, port, secure, auth: { user, pass }, from };
}

function isSmtpConfigured() {
  return getSmtpOptions() != null;
}

/**
 * @param {{ to: string, subject: string, text: string }} opts
 */
async function sendSmtpMail(opts) {
  const cfg = getSmtpOptions();
  if (!cfg) {
    const err = new Error(
      'SMTP is not configured. Set SMTP_HOST, SMTP_USER, SMTP_PASS, and SMTP_FROM in .env (see .env.example).',
    );
    err.code = 'SMTP_NOT_CONFIGURED';
    throw err;
  }
  const transport = nodemailer.createTransport({
    host: cfg.host,
    port: cfg.port,
    secure: cfg.secure,
    auth: cfg.auth,
  });
  await transport.sendMail({
    from: cfg.from,
    to: opts.to,
    subject: opts.subject,
    text: opts.text,
  });
}

module.exports = { sendSmtpMail, isSmtpConfigured };
