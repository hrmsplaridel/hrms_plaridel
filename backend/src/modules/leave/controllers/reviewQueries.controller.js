'use strict';
module.exports = function createLeaveControllers({
  SQL_LEAVE_ASSIGNMENT_DEPT_JOIN,
  finalQueueVisibilitySql,
  finalReviewScope,
  isDepartmentHead,
  listLeaveReviewFilterOptions,
  mapLeaveRowToApi,
  pool,
  todayInHrmsTimezone,
}) {
  return {
    getReviewFilters: async (req, res) => {
      try {
        const items = await listLeaveReviewFilterOptions(
          pool,
          `${finalReviewScope(req, '$1::uuid')} AND ${finalQueueVisibilitySql('leave', 'lr', '$1::uuid')} AND COALESCE(lr.user_id, lr.employee_id) <> $1::uuid`,
          [req.user?.id],
        );
        res.json(items);
      } catch (err) {
        console.error('[leave GET /filter-options]', err);
        res.status(500).json({ error: 'Failed to fetch leave review filters' });
      }
    },

    listFinalReviewRequests: async (req, res) => {
      try {
        const paginated = req.query?.paginated === 'true';
        const status = (req.query?.status || '').toString().trim() || null;
        const leaveType = (req.query?.leave_type || '').toString().trim() || null;
        const userId = (req.query?.user_id || '').toString().trim() || null;
        const department = (req.query?.department || '').toString().trim() || null;
        const limitRaw = req.query?.limit ? Number(req.query.limit) : null;
        const safeLimit =
          Number.isInteger(limitRaw) && limitRaw > 0
            ? Math.min(limitRaw, 500)
            : paginated
              ? 50
              : null;
        const offsetRaw = req.query?.offset == null ? 0 : Number(req.query.offset);
        if (paginated && (!Number.isInteger(offsetRaw) || offsetRaw < 0)) {
          return res.status(400).json({ error: 'offset must be a non-negative integer' });
        }
        const offset = paginated ? offsetRaw : 0;

        // FIX #12 (Phase 4 preview wired here): Date range filters.
        const startDateFrom = (req.query?.start_date_from || '').toString().trim() || null;
        const startDateTo = (req.query?.start_date_to || '').toString().trim() || null;
        const createdFrom = (req.query?.created_from || '').toString().trim() || null;
        const createdTo = (req.query?.created_to || '').toString().trim() || null;

        const fromWhere = `FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
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
           AND h.action IN (
             'department_head_approved',
             'department_head_rejected',
             'department_head_returned'
           )
         ORDER BY h.acted_at DESC
         LIMIT 1
       ) dhh ON true
       WHERE ($1::text IS NULL OR lr.status = $1)
         AND ($2::text IS NULL OR lt.name = $2)
         AND ($3::uuid IS NULL OR lr.user_id = $3 OR lr.employee_id = $3)
         AND ($4::date IS NULL OR lr.start_date >= $4)
         AND ($5::date IS NULL OR lr.start_date <= $5)
         AND ($6::timestamptz IS NULL OR lr.created_at >= $6)
         AND ($7::date IS NULL OR lr.created_at < ($7::date + interval '1 day'))
         AND ($8::text IS NULL OR d.name = $8)
         AND ${finalReviewScope(req, '$9::uuid')}
         AND ${finalQueueVisibilitySql('leave', 'lr', '$9::uuid')}
         AND COALESCE(lr.user_id, lr.employee_id) <> $9::uuid`;
        const params = [
          status,
          leaveType,
          userId,
          startDateFrom,
          startDateTo,
          createdFrom,
          createdTo,
          department,
          req.user?.id,
        ];
        const rows = await pool.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name,
              d.name AS assignment_department_name,
              rv.full_name AS reviewer_name,
              rv.role AS reviewer_role,
              dhh.department_head_action,
              dhh.department_head_reviewer_id,
              dhh.department_head_reviewer_name,
              dhh.department_head_reviewed_at,
              dhh.department_head_remarks
       ${fromWhere}
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC, lr.id DESC
       ${safeLimit ? `LIMIT ${safeLimit}` : ''}
       ${paginated ? `OFFSET ${offset}` : ''}`,
          params,
        );
        const items = rows.rows.map(mapLeaveRowToApi);
        if (!paginated) return res.json(items);
        const count = await pool.query(`SELECT COUNT(*)::int AS total ${fromWhere}`, params);
        const total = count.rows[0]?.total || 0;
        res.json({
          items,
          total,
          limit: safeLimit,
          offset,
          has_more: offset + items.length < total,
        });
      } catch (err) {
        console.error('[leave GET /]', err);
        res.status(500).json({ error: 'Failed to fetch leave requests' });
      }
    },

    listPendingRequests: async (req, res) => {
      try {
        const rows = await pool.query(
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
           AND h.action IN (
             'department_head_approved',
             'department_head_rejected',
             'department_head_returned'
           )
         ORDER BY h.acted_at DESC
         LIMIT 1
       ) dhh ON true
       WHERE ${finalReviewScope(req, '$1::uuid')} AND lr.status IN ('pending', 'pending_hr', 'pending_mayor')
         AND ${finalQueueVisibilitySql('leave', 'lr', '$1::uuid')}
         AND COALESCE(lr.user_id, lr.employee_id) <> $1::uuid
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC
       LIMIT 200`,
          [req.user?.id],
        );
        res.json(rows.rows.map(mapLeaveRowToApi));
      } catch (err) {
        console.error('[leave GET /pending]', err);
        res.status(500).json({ error: 'Failed to fetch pending leave requests' });
      }
    },

    getDepartmentReviewerAccess: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const client = await pool.connect();
      try {
        const result = await isDepartmentHead(client, userId);
        const assigned = await client.query(
          `SELECT lr.review_department_id AS department_id,
              d.name AS department_name
       FROM leave_requests lr
       LEFT JOIN departments d ON d.id = lr.review_department_id
       WHERE lr.status = 'pending_department_head'
         AND (
           lr.assigned_department_head_id = $1::uuid
           OR EXISTS (
             SELECT 1 FROM leave_request_department_reviewers lrr
             WHERE lrr.leave_request_id = lr.id AND lrr.reviewer_id = $1::uuid
           )
         )
       ORDER BY lr.updated_at DESC
       LIMIT 1`,
          [userId],
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
          [userId, todayInHrmsTimezone()],
        );
        const assignedDepartment = assigned.rows[0] || activeBackup.rows[0] || null;

        const hasHistoryResult = await client.query(
          `SELECT EXISTS (
         SELECT 1 FROM leave_request_history h
         WHERE h.acted_by = $1::uuid
           AND h.action IN ('department_head_approved', 'department_head_rejected', 'department_head_returned')
       )`,
          [userId],
        );

        const canReviewPending = result.isDeptHead || Boolean(assignedDepartment);
        res.json({
          isDeptHead: canReviewPending,
          canReviewPending,
          canViewReviewHistory: hasHistoryResult.rows[0].exists,
          departmentId: result.departmentId || assignedDepartment?.department_id || null,
          departmentName: result.departmentName || assignedDepartment?.department_name || null,
          hasHistory: hasHistoryResult.rows[0].exists,
        });
      } catch (err) {
        console.error('[leave GET /department-head/check]', err);
        res.status(500).json({ error: 'Failed to check department head status' });
      } finally {
        client.release();
      }
    },

    getDepartmentReviewFilters: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      try {
        const items = await listLeaveReviewFilterOptions(
          pool,
          `((lr.status = 'pending_department_head' AND (
         lr.assigned_department_head_id = $1::uuid OR EXISTS (
           SELECT 1 FROM leave_request_department_reviewers lrr
           WHERE lrr.leave_request_id = lr.id AND lrr.reviewer_id = $1::uuid
         )
       )) OR EXISTS (
         SELECT 1 FROM leave_request_history h
         WHERE h.leave_request_id = lr.id AND h.acted_by = $1::uuid
           AND h.action IN ('department_head_approved', 'department_head_rejected', 'department_head_returned')
       )) AND COALESCE(lr.user_id, lr.employee_id) <> $1::uuid`,
          [userId],
        );
        res.json(items);
      } catch (err) {
        console.error('[leave GET /department-head/filter-options]', err);
        res.status(500).json({ error: 'Failed to fetch department-head leave filters' });
      }
    },

    listDepartmentRequests: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const client = await pool.connect();
      try {
        const paginated = req.query?.paginated === 'true';
        const status = (req.query?.status || '').toString().trim() || null;
        const leaveType = (req.query?.leave_type || '').toString().trim() || null;
        const employeeUserId = (req.query?.user_id || '').toString().trim() || null;
        const department = (req.query?.department || '').toString().trim() || null;
        const startDateFrom = (req.query?.start_date_from || '').toString().trim() || null;
        const startDateTo = (req.query?.start_date_to || '').toString().trim() || null;
        const createdFrom = (req.query?.created_from || '').toString().trim() || null;
        const createdTo = (req.query?.created_to || '').toString().trim() || null;
        const limitRaw = req.query?.limit ? Number(req.query.limit) : 200;
        const limit = Number.isInteger(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 500) : 200;
        const offsetRaw = req.query?.offset == null ? 0 : Number(req.query.offset);
        if (paginated && (!Number.isInteger(offsetRaw) || offsetRaw < 0)) {
          return res.status(400).json({ error: 'offset must be a non-negative integer' });
        }
        const offset = paginated ? offsetRaw : 0;

        const fromWhere = `FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
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
            AND h.acted_by = $1::uuid
           AND h.action IN (
             'department_head_approved',
             'department_head_rejected',
             'department_head_returned'
           )
         ORDER BY h.acted_at DESC
         LIMIT 1
       ) dhh ON true
        WHERE (
            (
              lr.status = 'pending_department_head'
              AND (
                lr.assigned_department_head_id = $1::uuid
                OR EXISTS (
                  SELECT 1
                  FROM leave_request_department_reviewers lrr
                  WHERE lrr.leave_request_id = lr.id
                    AND lrr.reviewer_id = $1::uuid
                )
              )
            )
            OR dhh.department_head_reviewer_id IS NOT NULL
          )
          AND COALESCE(lr.user_id, lr.employee_id) <> $1::uuid
          AND ($2::text IS NULL OR lr.status = $2)
          AND ($3::text IS NULL OR lt.name = $3)
          AND ($4::uuid IS NULL OR lr.user_id = $4 OR lr.employee_id = $4)
          AND ($5::date IS NULL OR lr.start_date >= $5)
          AND ($6::date IS NULL OR lr.start_date <= $6)
          AND ($7::timestamptz IS NULL OR lr.created_at >= $7)
          AND ($8::date IS NULL OR lr.created_at < ($8::date + interval '1 day'))
          AND ($9::text IS NULL OR d.name = $9)`;
        const params = [
          userId,
          status,
          leaveType,
          employeeUserId,
          startDateFrom,
          startDateTo,
          createdFrom,
          createdTo,
          department,
        ];
        const rows = await client.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name,
              d.name AS assignment_department_name,
              rv.full_name AS reviewer_name,
              rv.role AS reviewer_role,
              dhh.department_head_action,
              dhh.department_head_reviewer_id,
              dhh.department_head_reviewer_name,
              dhh.department_head_reviewed_at,
              dhh.department_head_remarks
       ${fromWhere}
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC, lr.id DESC
       LIMIT ${limit}
       ${paginated ? `OFFSET ${offset}` : ''}`,
          params,
        );
        const items = rows.rows.map(mapLeaveRowToApi);
        if (!paginated) return res.json(items);
        const count = await client.query(`SELECT COUNT(*)::int AS total ${fromWhere}`, params);
        const total = count.rows[0]?.total || 0;
        res.json({ items, total, limit, offset, has_more: offset + items.length < total });
      } catch (err) {
        console.error('[leave GET /department-head]', err);
        res.status(500).json({ error: 'Failed to fetch department head leave requests' });
      } finally {
        client.release();
      }
    },
  };
};
