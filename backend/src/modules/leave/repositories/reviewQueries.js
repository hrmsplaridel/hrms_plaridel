'use strict';
module.exports = function createLeaveComponent({ SQL_LEAVE_ASSIGNMENT_DEPT_JOIN }) {
  // GET /api/leave (admin/HR list)
  // Query params: status, leave_type, user_id, limit,
  //               start_date_from, start_date_to, created_from, created_to
  const HR_REVIEW_SCOPE_SQL = `(
  lr.status IN ('pending', 'pending_hr')
  OR EXISTS (
    SELECT 1 FROM leave_request_history review_history
    WHERE review_history.leave_request_id = lr.id
      AND (review_history.to_status IN ('pending', 'pending_hr')
           OR review_history.from_status IN ('pending', 'pending_hr'))
  )
)`;

  function finalReviewScope(req, actor) {
    if (req.user?.role === 'mayor')
      return `(lr.workflow_snapshot IS NOT NULL AND lr.final_review_route='mayor_direct'
 AND (lr.status='pending_mayor' OR EXISTS(SELECT 1 FROM leave_request_history mh WHERE mh.leave_request_id=lr.id
 AND (mh.from_status='pending_mayor' OR mh.to_status='pending_mayor'))))`;
    return `((COALESCE(lr.final_review_route,'hr')='hr' OR (lr.workflow_snapshot IS NOT NULL AND ${HR_REVIEW_SCOPE_SQL})) AND ${HR_REVIEW_SCOPE_SQL})`;
  }

  async function listLeaveReviewFilterOptions(db, scopeSql, params) {
    const result = await db.query(
      `SELECT DISTINCT COALESCE(lr.user_id, lr.employee_id) AS user_id,
            u.full_name AS employee_name, d.name AS department
     FROM leave_requests lr
     LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
     ${SQL_LEAVE_ASSIGNMENT_DEPT_JOIN}
     WHERE ${scopeSql}
     ORDER BY department, employee_name, user_id`,
      params,
    );
    return result.rows;
  }
  return { HR_REVIEW_SCOPE_SQL, finalReviewScope, listLeaveReviewFilterOptions };
};
