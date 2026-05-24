const {
  insertNotificationForUsers,
  getHrAdminUserIds,
} = require('./notificationService');

/**
 * Employee submitted a daily training report — notify HR/admin.
 */
async function notifyReportSubmitted(pool, { reportId, employeeName, title }) {
  const hrIds = await getHrAdminUserIds(pool);
  if (!hrIds.length) return;

  const who = employeeName || 'An employee';
  const reportTitle = title?.trim() || 'Daily training report';

  await insertNotificationForUsers(pool, hrIds, {
    category: 'training',
    type: 'training_report_submitted',
    title: 'New training daily report',
    body: `${who} submitted “${reportTitle}”.`,
    referenceType: 'training_daily_report',
    referenceId: reportId,
    metadata: { title: reportTitle },
  });
}

module.exports = {
  notifyReportSubmitted,
};
