'use strict';
const { insertNotification, publishNotification } = require('./notificationService');

// A configuration alert is not an approval task. Keep the request pending and
// tell the people who can assign a different reviewer; deliver once per request.
async function notifyMissingFinalReviewer(pool, kind, requestId) {
  const client = await pool.connect();
  const created = [];
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`final-review-alert:${kind}:${requestId}`]);
    const recipients = await client.query(
      `SELECT u.id FROM users u LEFT JOIN dtr_admin_access access ON access.admin_user_id = u.id
       WHERE u.is_active = true AND (u.role IN ('superadmin', 'hr')
         OR (u.role = 'admin' AND access.approvals_allowed = true))
       AND NOT EXISTS (SELECT 1 FROM user_notifications n
         WHERE n.user_id = u.id AND n.type = 'approval_configuration_required'
           AND n.reference_id = $1::uuid AND n.reference_type = $2)`,
      [requestId, kind === 'locator' ? 'locator_slip' : 'leave_request']);
    for (const user of recipients.rows) {
      created.push(await insertNotification(client, {
        userId: user.id, category: 'general', type: 'approval_configuration_required',
        title: 'Different final HR reviewer needed',
        body: `A ${kind} request remains pending. Assign an eligible final HR reviewer other than the applicant and department approver.`,
        referenceType: kind === 'locator' ? 'locator_slip' : 'leave_request', referenceId: requestId,
        metadata: { request_type: kind }, deferDelivery: true,
      }));
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
  for (const row of created) publishNotification(pool, row);
}
module.exports = { notifyMissingFinalReviewer };
