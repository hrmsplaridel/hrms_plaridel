const {
  insertNotificationForUsers,
  getHrAdminUserIds,
} = require('./notificationService');

/**
 * New public recruitment application — notify HR/admin (in-app bell only; email stays separate).
 */
async function notifyNewApplication(pool, application) {
  const hrIds = await getHrAdminUserIds(pool);
  if (!hrIds.length) return;

  const name = application.full_name || application.email || 'Applicant';
  const position = application.position_applied_for
    ? ` for ${application.position_applied_for}`
    : '';

  await insertNotificationForUsers(pool, hrIds, {
    category: 'recruitment',
    type: 'recruitment_new_application',
    title: 'New recruitment application',
    body: `${name} submitted an application${position}.`,
    referenceType: 'recruitment_application',
    referenceId: application.id,
    metadata: {
      email: application.email,
      position: application.position_applied_for,
    },
  });
}

module.exports = {
  notifyNewApplication,
};
