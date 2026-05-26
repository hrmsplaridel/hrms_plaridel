const {
  insertNotification,
  insertNotificationForUsers,
  getHrAdminUserIds,
} = require('./notificationService');

async function getReviewerUserIds(pool) {
  const r = await pool.query(
    `SELECT id FROM users WHERE role IN ('admin', 'hr', 'supervisor')`
  );
  return r.rows.map((row) => row.id);
}

/**
 * Employee filed overtime — notify reviewers (excludes submitter).
 */
async function notifyOvertimeSubmitted(pool, { requestId, employeeUserId, employeeName, otDate }) {
  const reviewerIds = (await getReviewerUserIds(pool)).filter((id) => id !== employeeUserId);
  if (!reviewerIds.length) return;

  const who = employeeName || 'An employee';
  const dateLabel = otDate ? String(otDate).slice(0, 10) : 'a date';

  await insertNotificationForUsers(pool, reviewerIds, {
    category: 'overtime',
    type: 'overtime_pending_review',
    title: 'Overtime request pending review',
    body: `${who} submitted overtime for ${dateLabel}.`,
    referenceType: 'overtime_request',
    referenceId: requestId,
    metadata: { employee_id: employeeUserId, ot_date: otDate },
  });
}

/**
 * Overtime approved or rejected — notify the employee.
 */
async function notifyOvertimeReviewed(pool, {
  requestId,
  employeeUserId,
  status,
  otDate,
  reviewNotes,
}) {
  if (!employeeUserId) return;

  const dateLabel = otDate ? String(otDate).slice(0, 10) : 'your request';
  const approved = status === 'approved';
  const title = approved ? 'Overtime approved' : 'Overtime rejected';
  let body = approved
    ? `Your overtime for ${dateLabel} was approved.`
    : `Your overtime for ${dateLabel} was rejected.`;
  if (reviewNotes?.trim()) {
    body += ` Note: ${reviewNotes.trim()}`;
  }

  await insertNotification(pool, {
    userId: employeeUserId,
    category: 'overtime',
    type: approved ? 'overtime_approved' : 'overtime_rejected',
    title,
    body,
    referenceType: 'overtime_request',
    referenceId: requestId,
    metadata: { status, ot_date: otDate },
  });
}

module.exports = {
  notifyOvertimeSubmitted,
  notifyOvertimeReviewed,
  getReviewerUserIds,
};
