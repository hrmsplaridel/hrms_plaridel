const { resolveActiveMayor } = require('./officialSignatoryService');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');

// Mayor-role privilege is tied to today's authority, independently of the
// historical printed signatories. Ownership/reviewer access is checked separately.
async function canReadLocatorAsMayor(db, user, finalReviewRoute) {
  if (String(user?.role || '').trim().toLowerCase() !== 'mayor' ||
      finalReviewRoute !== 'mayor_direct' || !user?.id) return false;
  const mayor = await resolveActiveMayor(db, todayInHrmsTimezone());
  return Boolean(mayor?.employee_id) && String(mayor.employee_id) === String(user.id);
}

module.exports = { canReadLocatorAsMayor };
