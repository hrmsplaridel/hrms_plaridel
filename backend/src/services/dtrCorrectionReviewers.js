const { todayInHrmsTimezone } = require('../utils/dateRangeParser');

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
     ORDER BY assigned.rank`, [date]);
  return result.rows;
}

module.exports = { resolveDtrCorrectionReviewers };
