'use strict';
module.exports = function createLeaveComponent({}) {
  async function findAssignmentProfileByUserIdAtDate(db, userId, effectiveDate = null) {
    if (!userId) return null;
    const result = await db.query(
      `SELECT u.id AS user_id,
            u.full_name,
            p.name AS position_title,
            a.department_id,
            d.name AS department_name
     FROM users u
     LEFT JOIN LATERAL (
       SELECT a.department_id, a.position_id, a.effective_from
       FROM assignments a
       WHERE a.employee_id = u.id
         AND (a.effective_from IS NULL OR a.effective_from <= COALESCE($2::date, CURRENT_DATE))
         AND (a.effective_to IS NULL OR a.effective_to >= COALESCE($2::date, CURRENT_DATE))
       ORDER BY a.effective_from DESC NULLS LAST,
                a.created_at DESC NULLS LAST,
                a.id DESC
       LIMIT 1
     ) a ON true
     LEFT JOIN departments d ON d.id = a.department_id
     LEFT JOIN positions p ON p.id = a.position_id
     WHERE u.id = $1
     LIMIT 1`,
      [userId, effectiveDate],
    );
    return result.rows[0] || null;
  }

  function mapSignatoryProfile(row) {
    if (!row) return null;
    return {
      user_id: row.user_id || null,
      name: row.full_name || null,
      position_title: row.position_title || null,
      department_id: row.department_id || null,
      department_name: row.department_name || null,
    };
  }

  function mapOfficialSignatoryProfile(row) {
    if (!row) return null;
    return {
      user_id: row.employee_id || null,
      name: row.name || null,
      position_title: row.position_title || null,
      department_name: row.department_name || null,
    };
  }
  return { findAssignmentProfileByUserIdAtDate, mapSignatoryProfile, mapOfficialSignatoryProfile };
};
