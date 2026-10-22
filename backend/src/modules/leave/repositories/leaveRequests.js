'use strict';
module.exports = function createLeaveComponent({ pool }) {
  async function hasOverlappingLeaveRequest(client, userId, startStr, endStr, excludeId = null) {
    if (!userId || !startStr || !endStr) return false;
    // FIX #10: prefer user_id; fallback to employee_id only for legacy records not yet backfilled.
    const q = await client.query(
      `SELECT 1
     FROM leave_requests
     WHERE (user_id = $1 OR employee_id = $1)
       AND status IN ('pending', 'pending_department_head', 'pending_hr', 'pending_mayor', 'approved')
       AND start_date <= $3::date
       AND end_date >= $2::date
       AND ($4::uuid IS NULL OR id <> $4::uuid)
     LIMIT 1`,
      [userId, startStr, endStr, excludeId],
    );
    return q.rows.length > 0;
  }

  /** Snapshotted review department, with an effective-date fallback for legacy rows. */
  const SQL_LEAVE_ASSIGNMENT_DEPT_JOIN = `
LEFT JOIN LATERAL (
  SELECT hist_a.department_id
  FROM assignments hist_a
  WHERE hist_a.employee_id = COALESCE(lr.user_id, lr.employee_id)
    AND hist_a.effective_from <= lr.start_date
    AND (hist_a.effective_to IS NULL OR hist_a.effective_to >= lr.start_date)
  ORDER BY hist_a.effective_from DESC, hist_a.created_at DESC, hist_a.id DESC
  LIMIT 1
) a ON true
LEFT JOIN departments d ON d.id = COALESCE(lr.review_department_id, a.department_id)`;

  /** Check if user can access leave request (owner or admin). */
  async function canAccessLeaveRequest(requestId, userId, isAdmin) {
    // FIX #10: prefer user_id first; employee_id kept as fallback for legacy rows.
    const q = await pool.query(
      'SELECT id FROM leave_requests WHERE id = $1 AND ($2 = true OR user_id = $3 OR employee_id = $3)',
      [requestId, isAdmin, userId],
    );
    return q.rows.length > 0;
  }
  return { hasOverlappingLeaveRequest, canAccessLeaveRequest, SQL_LEAVE_ASSIGNMENT_DEPT_JOIN };
};
