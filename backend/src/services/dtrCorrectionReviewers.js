const { todayInHrmsTimezone } = require('../utils/dateRangeParser');

// Queries using this predicate must alias users as u. HR has inherent access;
// admins need an explicit, currently enabled corrections permission.
const reviewerAccessSql = `(u.role = 'hr' OR EXISTS (
  SELECT 1 FROM dtr_admin_access a
  WHERE a.admin_user_id = u.id AND a.corrections_allowed = true
))`;

async function resolveDtrCorrectionReviewers(db, date = todayInHrmsTimezone()) {
  const result = await db.query(`
    SELECT u.id, u.full_name AS name
      FROM dtr_correction_reviewer_configs c
      CROSS JOIN LATERAL unnest(c.reviewer_ids) WITH ORDINALITY AS assigned(id, rank)
      JOIN users u ON u.id = assigned.id
     WHERE c.id = (
       SELECT id FROM dtr_correction_reviewer_configs
        WHERE effective_from <= $1::date
        ORDER BY effective_from DESC, created_at DESC, id DESC LIMIT 1
     )
       AND u.is_active = true
       AND COALESCE(u.employment_status, 'active') = 'active'
       AND u.role IN ('admin', 'hr')
       AND ${reviewerAccessSql}
     ORDER BY assigned.rank`, [date]);
  return result.rows;
}

module.exports = { resolveDtrCorrectionReviewers, reviewerAccessSql };
