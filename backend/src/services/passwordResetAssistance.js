const { pool } = require('../config/db');
const { notifyPasswordResetRequestsChanged } = require('./passwordResetEvents');
const { sendSmtpMail, isSmtpConfigured } = require('../utils/smtpMail');
const { createOtpCode, hashPasswordResetCode, PASSWORD_RESET_OTP_TTL_MS } = require('./passwordResetOtp');

const message = 'If this is an eligible account, your assistance request has been recorded. Contact your system administrator for verification. After approval, check your registered email for a reset code.';
const fail = (status, text) => Object.assign(new Error(text), { status });
async function audit(db, actor, target, action, details) {
  await db.query(`INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
    VALUES ($1, $2, 'user', $3, $4)`, [actor, action, target, JSON.stringify(details)]);
}

function createPasswordResetAssistance({ pool: db = pool, sendMail = sendSmtpMail, isMailConfigured = isSmtpConfigured, notify = notifyPasswordResetRequestsChanged } = {}) {
  async function transaction(work) {
    const client = await db.connect();
    let releaseError;
    try {
      await client.query('BEGIN');
      const result = await work(client);
      await client.query('COMMIT');
      if (result) { try { notify(); } catch (_) {} }
      return result;
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch (rollbackError) { releaseError = rollbackError; }
      throw error;
    } finally { client.release(releaseError); }
  }
  async function request(email) {
    if (typeof email !== 'string' || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) throw fail(400, 'A valid email is required');
    await transaction(async client => {
      const result = await client.query(`SELECT id FROM users WHERE LOWER(email) = $1
        AND role IN ('employee', 'admin') AND is_active = true
        AND employment_status = 'active' FOR UPDATE`, [email.trim().toLowerCase()]);
      const user = result.rows[0];
      if (!user) return;
      const existing = await client.query(`SELECT id FROM password_reset_requests WHERE user_id = $1
        AND (status IN ('pending', 'sent') OR created_at > now() - interval '15 minutes')`, [user.id]);
      if (existing.rowCount) return;
      const inserted = await client.query('INSERT INTO password_reset_requests (user_id) VALUES ($1) RETURNING id', [user.id]);
      // An unauthenticated submission is not proof that the account owner requested it.
      await audit(client, null, user.id, 'password_reset_assistance_requested', {
        request_id: inserted.rows[0].id, source: 'public_form', identity_verified: false,
      });
      return true;
    });
    return { message };
  }
  async function list({ status, page = 1 } = {}) {
    page = Number(page);
    if (!Number.isSafeInteger(page) || page < 1 || page > 100000) throw fail(400, 'Invalid page');
    if (status && !['pending', 'sent', 'closed'].includes(status)) throw fail(400, 'Invalid status');
    const result = await db.query(`SELECT r.id, r.user_id, r.status, r.created_at, r.sent_at, r.closed_at,
        r.completed_at, u.full_name, u.email, u.role, u.is_active,
        h.full_name AS handled_by_name
      FROM password_reset_requests r JOIN users u ON u.id = r.user_id
      LEFT JOIN users h ON h.id = r.handled_by
      WHERE ($1::text IS NULL OR r.status = $1)
      ORDER BY r.created_at DESC, r.id DESC LIMIT 51 OFFSET $2`, [status || null, (page - 1) * 50]);
    return { requests: result.rows.slice(0, 50), has_more: result.rows.length > 50, page };
  }
  async function handle(id, actor, sending, verified) {
    if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id)) throw fail(400, 'Invalid request ID');
    if (sending && verified !== true) throw fail(400, 'Verify the requester before sending a reset code');
    if (sending && !isMailConfigured()) throw fail(503, 'Reset email is not configured. Contact the system operator.');
    return transaction(async client => {
      const lookup = await client.query('SELECT user_id FROM password_reset_requests WHERE id = $1', [id]);
      if (!lookup.rowCount) throw fail(404, 'Request not found');
      // Same lock order as reset completion and public requests.
      const users = await client.query('SELECT id, email, role, is_active, employment_status FROM users WHERE id = $1 FOR UPDATE', [lookup.rows[0].user_id]);
      const user = users.rows[0];
      const requests = await client.query('SELECT *, sent_at > now() - interval \'60 seconds\' AS cooling_down FROM password_reset_requests WHERE id = $1 FOR UPDATE', [id]);
      const row = requests.rows[0];
      if (!user || !row) throw fail(404, 'Request not found');
      if (row.status === 'closed') throw fail(409, 'This request is already closed');
      if (!sending) {
        await client.query('UPDATE auth_password_reset_otps SET consumed_at = now() WHERE assistance_request_id = $1 AND consumed_at IS NULL', [id]);
        await client.query("UPDATE password_reset_requests SET status = 'closed', closed_at = now(), handled_by = $2 WHERE id = $1", [id, actor]);
        await audit(client, actor, user.id, 'password_reset_assistance_closed', { request_id: id });
        return { message: 'Request closed' };
      }
      if (!['employee', 'admin'].includes(user.role) || !user.is_active || user.employment_status !== 'active') throw fail(409, 'This account is not eligible for assisted reset');
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(user.email)) throw fail(409, 'The registered email is invalid');
      if (row.cooling_down) throw fail(429, 'Please wait 60 seconds before sending another code');
      const code = createOtpCode();
      await client.query('UPDATE auth_password_reset_otps SET consumed_at = now() WHERE user_id = $1 AND consumed_at IS NULL', [user.id]);
      await client.query(`INSERT INTO auth_password_reset_otps (user_id, code_hash, sent_to, expires_at, assistance_request_id)
        VALUES ($1, $2, $3, $4, $5)`, [user.id, hashPasswordResetCode(user.id, code), user.email, new Date(Date.now() + PASSWORD_RESET_OTP_TTL_MS), id]);
      await audit(client, actor, user.id, 'password_reset_assistance_sent', { request_id: id, channel: 'email', identity_verified: true });
      try {
        await sendMail({ to: user.email, subject: 'HRMS password reset code', timeoutMs: 20000,
          text: `Your HRMS reset code is ${code}. It expires in ${Math.ceil(PASSWORD_RESET_OTP_TTL_MS / 60000)} minutes and can be used once. Open Forgot Password, choose Enter a reset code, and set your own password. If you did not request this, contact your system administrator. Never share this code.` });
      } catch (_) { throw fail(502, 'Reset email could not be sent. Please retry.'); }
      await client.query("UPDATE password_reset_requests SET status = 'sent', sent_at = now(), handled_by = $2 WHERE id = $1", [id, actor]);
      return { message: 'Reset code sent to the registered email' };
    });
  }
  return { request, list, send: (id, actor, verified) => handle(id, actor, true, verified), close: (id, actor) => handle(id, actor, false) };
}
module.exports = { createPasswordResetAssistance };
