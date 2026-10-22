'use strict';
module.exports = function createLeaveControllers({
  SQL_LEAVE_ASSIGNMENT_DEPT_JOIN,
  mapLeaveRowToApi,
  pool,
  todayInHrmsTimezone,
}) {
  return {
    getEmployeeContext: (_req, res) => {
      res.json({ official_date: todayInHrmsTimezone() });
    },

    listMyRequests: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      try {
        const status = (req.query?.status || '').toString().trim() || null;
        const paginated = String(req.query?.paginated || '').toLowerCase() === 'true';
        const limitRaw = req.query?.limit ? parseInt(req.query.limit, 10) : 100;
        const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 500) : 100;
        const offsetRaw = req.query?.offset ? parseInt(req.query.offset, 10) : 0;
        const offset = Number.isFinite(offsetRaw) && offsetRaw >= 0 ? offsetRaw : 0;
        const rows = await pool.query(
          `SELECT lr.*, COUNT(*) OVER()::int AS total_count,
              lt.name AS leave_type_name, u.full_name AS employee_full_name,
              rv.full_name AS reviewer_name,
              rv.role AS reviewer_role,
              dhh.department_head_action,
              dhh.department_head_reviewer_id,
              dhh.department_head_reviewer_name,
              dhh.department_head_reviewed_at,
              dhh.department_head_remarks
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
       LEFT JOIN users rv ON rv.id = COALESCE(lr.reviewer_id, lr.approved_by)
       LEFT JOIN LATERAL (
         SELECT h.action AS department_head_action,
                h.acted_by AS department_head_reviewer_id,
                actor.full_name AS department_head_reviewer_name,
                h.acted_at AS department_head_reviewed_at,
                h.remarks AS department_head_remarks
         FROM leave_request_history h
         LEFT JOIN users actor ON actor.id = h.acted_by
         WHERE h.leave_request_id = lr.id
           AND h.action IN (
             'department_head_approved',
             'department_head_rejected',
             'department_head_returned'
           )
         ORDER BY h.acted_at DESC
         LIMIT 1
       ) dhh ON true
       WHERE (lr.user_id = $1 OR lr.employee_id = $1)
         AND lr.discarded_at IS NULL
         AND ($2::text IS NULL OR lr.status = $2)
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC, lr.id DESC
       LIMIT $3 OFFSET $4`,
          [userId, status, limit, offset],
        );
        const items = rows.rows.map(mapLeaveRowToApi);
        if (!paginated) return res.json(items);
        let total = rows.rows.length > 0 ? Number(rows.rows[0].total_count) : 0;
        if (rows.rows.length === 0 && offset > 0) {
          const countRows = await pool.query(
            `SELECT COUNT(*)::int AS total
         FROM leave_requests lr
         WHERE (lr.user_id = $1 OR lr.employee_id = $1)
           AND lr.discarded_at IS NULL
           AND ($2::text IS NULL OR lr.status = $2)`,
            [userId, status],
          );
          total = Number(countRows.rows[0]?.total || 0);
        }
        res.json({ items, total, limit, offset, has_more: offset + items.length < total });
      } catch (err) {
        console.error('[leave GET /my]', err);
        res.status(500).json({ error: 'Failed to fetch my leave requests' });
      }
    },

    getMyHistory: async (req, res) => {
      const userId = req.user?.id;
      const requestId = (req.params?.id || '').toString().trim();
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      if (!requestId) return res.status(400).json({ error: 'Leave request id is required' });

      try {
        const ownedRequest = await pool.query(
          `SELECT 1
       FROM leave_requests lr
       WHERE lr.id = $1::uuid
         AND (lr.user_id = $2::uuid OR lr.employee_id = $2::uuid)
       LIMIT 1`,
          [requestId, userId],
        );
        if (ownedRequest.rowCount === 0) {
          return res.status(404).json({ error: 'Leave request not found' });
        }

        const history = await pool.query(
          `SELECT h.id,
              h.leave_request_id,
              h.action,
              h.from_status,
              h.to_status,
              h.acted_by,
              h.acted_at,
              h.remarks,
              h.metadata_json,
              actor.full_name AS actor_name,
              actor.role AS actor_role
       FROM leave_request_history h
       LEFT JOIN users actor ON actor.id = h.acted_by
       WHERE h.leave_request_id = $1::uuid
       ORDER BY h.acted_at ASC, h.id ASC`,
          [requestId],
        );
        res.json(history.rows);
      } catch (err) {
        if (err?.code === '22P02') {
          return res.status(404).json({ error: 'Leave request not found' });
        }
        console.error('[leave GET /my/:id/history]', err);
        res.status(500).json({ error: 'Failed to fetch leave request history' });
      }
    },

    getRequest: async (req, res) => {
      const userId = req.user?.id;
      const role = req.user?.role;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      try {
        const isAdmin = role === 'admin' || role === 'hr';
        const loadRequest = (sharedRead = false) =>
          pool.query(
            `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name,
              d.name AS assignment_department_name,
              rv.full_name AS reviewer_name,
              rv.role AS reviewer_role,
              dhh.department_head_action,
              dhh.department_head_reviewer_id,
              dhh.department_head_reviewer_name,
              dhh.department_head_reviewed_at,
              dhh.department_head_remarks
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       ${SQL_LEAVE_ASSIGNMENT_DEPT_JOIN}
       LEFT JOIN users rv ON rv.id = COALESCE(lr.reviewer_id, lr.approved_by)
       LEFT JOIN LATERAL (
         SELECT h.action AS department_head_action,
                h.acted_by AS department_head_reviewer_id,
                actor.full_name AS department_head_reviewer_name,
                h.acted_at AS department_head_reviewed_at,
                h.remarks AS department_head_remarks
         FROM leave_request_history h
         LEFT JOIN users actor ON actor.id = h.acted_by
         WHERE h.leave_request_id = lr.id
           AND ($2::boolean = true OR h.acted_by = $3::uuid)
           AND h.action IN (
             'department_head_approved',
             'department_head_rejected',
             'department_head_returned'
           )
         ORDER BY h.acted_at DESC
         LIMIT 1
       ) dhh ON true
       WHERE lr.id = $1
         AND lr.discarded_at IS NULL
         AND (
           $2::boolean = true
           OR (lr.user_id = $3 OR lr.employee_id = $3)
           OR ($4::boolean AND lr.final_review_route IN ('mayor','mayor_direct'))
            OR (
              lr.status = 'pending_department_head'
              AND lr.assigned_department_head_id = $3::uuid
            )
            OR dhh.department_head_reviewer_id IS NOT NULL
          )
        LIMIT 1`,
            [id, isAdmin || sharedRead, userId, role === 'mayor'],
          );
        let rows = await loadRequest();
        if (
          !rows.rows.length &&
          (await require('../../../services/leaveWorkflowReadAccess').canReadSharedLeaveRequest(
            pool,
            id,
            req.user,
          ))
        ) {
          rows = await loadRequest(true);
        }
        if (rows.rows.length === 0)
          return res.status(404).json({ error: 'Leave request not found' });
        if (
          (await require('../../../services/sharedWorkflowInbox').pendingReadAccess(
            pool,
            'leave',
            rows.rows[0],
            req.user,
          )) === false
        ) {
          return res.status(404).json({ error: 'Leave request not found' });
        }
        const row = rows.rows[0];
        res.json({
          ...mapLeaveRowToApi(row),
          ...(require('../../../services/approvalWorkflows').isShared(row.workflow_snapshot)
            ? { can_revoke_approval: await require('../../../services/leaveRevocationAccess').canRevokeSharedLeave(pool, row, req.user) }
            : {}),
        });
      } catch (err) {
        console.error('[leave GET /:id]', err);
        res.status(500).json({ error: 'Failed to fetch leave request' });
      }
    },
  };
};
