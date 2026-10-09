const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { resolveFinalLeaveReviewers } = require('./leaveFinalReviewerService');

async function activeReviewerFeatures(db, userId) {
  const date = todayInHrmsTimezone();
  const finalReviewers = await resolveFinalLeaveReviewers(db, date);
  const isAssigned = (rows) => rows.some((row) => String(row.id) === String(userId));
  // Department approvals use personal portal endpoints and do not require
  // Leave/Locator management permissions. Only final HR review depends on them.
  const sharedReviewer = isAssigned(finalReviewers);
  return {
    leave_allowed: sharedReviewer,
    locator_allowed: sharedReviewer,
  };
}

module.exports = { activeReviewerFeatures };
