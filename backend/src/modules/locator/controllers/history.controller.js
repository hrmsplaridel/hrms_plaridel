'use strict';
module.exports = function createLocatorControllers({
  canReadLocatorAsMayor,
  isDepartmentHead,
  listLocatorWorkflowEvents,
  pool,
}) {
  return {
    getRequestHistory: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });

      const client = await pool.connect();
      try {
        const current = await client.query(
          `SELECT ls.id, ls.employee_id, ls.department_id,
              ls.assigned_department_head_id, ls.dept_head_reviewer_id, ls.status, ls.final_review_route, ls.workflow_snapshot,
              EXISTS (
                SELECT 1 FROM locator_slip_department_reviewers lsr
                WHERE lsr.locator_slip_id = ls.id
                  AND lsr.reviewer_id = $2::uuid
              ) AS is_snapshotted_reviewer
       FROM locator_slips ls
       WHERE ls.id = $1::uuid`,
          [req.params.id, userId]
        );
        const row = current.rows[0];
        if (!row) return res.status(404).json({ error: 'Locator slip not found' });

        const workflowRead =
          await require('../../../services/sharedWorkflowInbox').pendingReadAccess(
            client,
            'locator',
            row,
            req.user
          );
        if (workflowRead === false)
          return res.status(404).json({ error: 'Locator slip not found' });
        const normalizedRole = String(req.user?.role || '')
          .trim()
          .toLowerCase();
        const isOwner = String(row.employee_id) === String(userId);
        const isHrOrAdmin =
          normalizedRole === 'hr' ||
          normalizedRole === 'admin' ||
          (await canReadLocatorAsMayor(client, req.user, row.final_review_route));
        let canReadAsDepartmentHead =
          String(row.assigned_department_head_id || '') === String(userId) ||
          String(row.dept_head_reviewer_id || '') === String(userId) ||
          row.is_snapshotted_reviewer === true;

        if (
          !isOwner &&
          !isHrOrAdmin &&
          !canReadAsDepartmentHead &&
          !row.assigned_department_head_id &&
          row.status === 'pending_department_head'
        ) {
          const departmentHead = await isDepartmentHead(client, userId);
          canReadAsDepartmentHead =
            departmentHead.isDeptHead === true &&
            String(departmentHead.departmentId || '') === String(row.department_id || '');
        }

        if (!isOwner && !isHrOrAdmin && !canReadAsDepartmentHead && workflowRead !== true) {
          return res.status(404).json({ error: 'Locator slip not found' });
        }

        const events = await listLocatorWorkflowEvents(client, row.id);
        return res.json(events);
      } catch (err) {
        console.error('[locator GET /:id/history]', err);
        return res.status(500).json({ error: 'Failed to fetch locator history' });
      } finally {
        client.release();
      }
    },
  };
};
