'use strict';
module.exports = function createLocatorControllers({
  currentHrmsDate,
  getLocatorSubmissionAvailability,
  isDepartmentHead,
  parseLocatorDateOnly,
  pool,
  resolveActiveMayor,
  resolveFinalLeaveReviewers,
  resolveLocatorShiftCoverage,
  todayInHrmsTimezone,
}) {
  return {
    getFinalReviewerAccess: async (req, res) => {
      try {
        const reviewers =
          req.user.role === 'mayor'
            ? await resolveActiveMayor(pool, todayInHrmsTimezone()).then((m) =>
                m ? [{ id: m.employee_id }] : []
              )
            : await resolveFinalLeaveReviewers(pool);
        res.json({
          can_review: reviewers.some((reviewer) => String(reviewer.id) === String(req.user.id)),
        });
      } catch (err) {
        console.error('[locator GET final-reviewer/me]', err);
        res.status(500).json({ error: 'Failed to check locator final reviewer assignment' });
      }
    },

    getSubmissionAvailability: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const date = req.query?.slip_date ?? currentHrmsDate();
      const dateInfo = typeof date === 'string' ? parseLocatorDateOnly(date) : null;
      if (!dateInfo) return res.status(400).json({ error: 'Invalid slip_date' });
      try {
        res.json(await getLocatorSubmissionAvailability(pool, userId, dateInfo.dateStr));
      } catch (err) {
        console.error('[locator GET submission-availability]', err);
        res.status(500).json({ error: 'Failed to check locator reviewer availability' });
      }
    },

    getContext: (_req, res) => {
      res.json({ official_date: currentHrmsDate() });
    },

    getShiftCoverage: async (req, res) => {
      const date = parseLocatorDateOnly(req.query.slip_date);
      if (!date) return res.status(400).json({ error: 'Invalid slip_date' });
      try {
        res.json(await resolveLocatorShiftCoverage(pool, req.user.id, date));
      } catch (err) {
        console.error('[locator shift coverage]', err);
        res.status(500).json({ error: 'Could not load the shift for the selected date.' });
      }
    },

    getDepartmentReviewerAccess: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const client = await pool.connect();
      try {
        const current = await isDepartmentHead(client, userId);
        const assigned = await client.query(
          `SELECT ls.department_id, d.name AS department_name
       FROM locator_slips ls
       LEFT JOIN departments d ON d.id = ls.department_id
       WHERE (
           ls.assigned_department_head_id = $1::uuid
           OR EXISTS (
             SELECT 1 FROM locator_slip_department_reviewers lsr
             WHERE lsr.locator_slip_id = ls.id
               AND lsr.reviewer_id = $1::uuid
           )
         )
         AND ls.status = 'pending_department_head'
       ORDER BY ls.updated_at DESC
       LIMIT 1`,
          [userId]
        );
        const reviewed = await client.query(
          `SELECT ls.department_id, d.name AS department_name
       FROM locator_slips ls
       LEFT JOIN departments d ON d.id = ls.department_id
       WHERE ls.dept_head_reviewer_id = $1::uuid
       ORDER BY COALESCE(ls.dept_head_reviewed_at, ls.updated_at) DESC
       LIMIT 1`,
          [userId]
        );
        const activeBackup = await client.query(
          `SELECT b.department_id, d.name AS department_name
       FROM department_reviewer_backups b
       JOIN users u ON u.id = b.employee_id
       LEFT JOIN departments d ON d.id = b.department_id
       WHERE b.employee_id = $1::uuid AND b.is_active = true AND u.is_active = true
         AND b.effective_from <= $2::date
         AND (b.effective_to IS NULL OR b.effective_to >= $2::date)
       ORDER BY b.backup_rank, b.id LIMIT 1`,
          [userId, currentHrmsDate()]
        );
        const assignedDepartment = assigned.rows[0] || activeBackup.rows[0];
        const assignedDepartmentId = assignedDepartment?.department_id || null;
        const assignedDepartmentName = assignedDepartment?.department_name || null;
        const reviewedDepartmentId = reviewed.rows[0]?.department_id || null;
        const reviewedDepartmentName = reviewed.rows[0]?.department_name || null;
        const canReviewPending = current.isDeptHead || Boolean(assignedDepartment);
        const hasReviewHistory = reviewed.rows.length > 0;
        res.json({
          // Keep the legacy field while clients migrate to the explicit capabilities.
          isDeptHead: canReviewPending || hasReviewHistory,
          canReviewPending,
          hasReviewHistory,
          departmentId: current.departmentId || assignedDepartmentId || reviewedDepartmentId,
          departmentName:
            current.departmentName || assignedDepartmentName || reviewedDepartmentName,
        });
      } catch (err) {
        console.error('[locator GET /department-head/check]', err);
        res.status(500).json({ error: 'Failed to check department head status' });
      } finally {
        client.release();
      }
    },
  };
};
