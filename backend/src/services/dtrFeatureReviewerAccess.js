const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { resolveFinalLeaveReviewers } = require('./leaveFinalReviewerService');
const { resolveDtrCorrectionReviewers } = require('./dtrCorrectionReviewers');

async function activeReviewerFeatures(db, userId) {
  const date = todayInHrmsTimezone();
  const correctionReviewers = await resolveDtrCorrectionReviewers(db, date);
  const finalReviewers = await resolveFinalLeaveReviewers(db, date);
  const departmentReviewer = await db.query(`SELECT EXISTS (
      SELECT 1 FROM department_reviewer_backups b
       WHERE b.employee_id = $1::uuid AND b.is_active = true
         AND b.effective_from <= $2::date
         AND (b.effective_to IS NULL OR b.effective_to >= $2::date)
      UNION ALL
      SELECT 1 FROM assignments a
      JOIN positions p ON p.id = a.position_id
      JOIN position_department_head_periods h
        ON h.position_id = p.id AND h.department_id = a.department_id
      WHERE a.employee_id = $1::uuid AND a.is_active = true AND p.is_active = true
        AND h.is_active = true AND a.effective_from <= $2::date
        AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
        AND h.effective_from <= $2::date
        AND (h.effective_to IS NULL OR h.effective_to >= $2::date)
    ) AS assigned`, [userId, date]);
  const isAssigned = (rows) => rows.some((row) => String(row.id) === String(userId));
  const sharedReviewer = isAssigned(finalReviewers) || departmentReviewer.rows[0]?.assigned === true;
  return {
    corrections_allowed: isAssigned(correctionReviewers),
    leave_allowed: sharedReviewer,
    locator_allowed: sharedReviewer,
  };
}

module.exports = { activeReviewerFeatures };
