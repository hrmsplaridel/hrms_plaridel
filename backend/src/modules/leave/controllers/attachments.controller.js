'use strict';
module.exports = function createLeaveControllers({
  DEPARTMENT_HEAD_HISTORY_ACTIONS,
  LEAVE_ATTACHMENT_SUBDIR,
  UPLOAD_DIR,
  attachmentReplacementCleanupPath,
  broadcastLeaveUpdated,
  canModifyLeaveAttachment,
  cleanupStoredLeaveAttachment,
  fs,
  mapLeaveRowToApi,
  path,
  pool,
  recordLeaveAttachmentAccess,
  resolveLeaveAttachmentAccess,
  workflowEngine,
}) {
  return {
    uploadAttachment: async (req, res) => {
      const userId = req.user?.id;
      const role = req.user?.role;
      const newRelPath = req.file?.filename
        ? `${LEAVE_ATTACHMENT_SUBDIR}/${req.file.filename}`
        : null;
      if (!userId) {
        cleanupStoredLeaveAttachment(newRelPath);
        return res.status(401).json({ error: 'Not authenticated' });
      }
      const { id } = req.params;
      if (!req.file) {
        return res
          .status(400)
          .json({ error: 'No file uploaded. Allowed: PDF, JPG, JPEG, PNG (max 10MB).' });
      }
      let client = null;
      let committed = false;
      let oldAttachmentPath = null;
      try {
        client = await pool.connect();
        await client.query('BEGIN');
        const isAdmin = role === 'admin' || role === 'hr';
        const existing = await client.query(
          `SELECT id, status, attachment_path
       FROM leave_requests
       WHERE id = $1 AND ($2 = true OR user_id = $3 OR employee_id = $3)
       FOR UPDATE`,
          [id, isAdmin, userId, await workflowEngine.isCurrentMayor(pool, req.user)],
        );
        if (existing.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Leave request not found' });
        }
        const row = existing.rows[0];
        if (!canModifyLeaveAttachment(row.status)) {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error:
              'Attachment is locked after submission. It can only be changed while the request is a draft or has been returned.',
          });
        }
        oldAttachmentPath = row.attachment_path || null;
        const mimeType = req.file.mimetype || null;
        await client.query(
          `UPDATE leave_requests
       SET attachment_name = $1, attachment_path = $2, attachment_mime_type = $3, attachment_uploaded_at = now(), updated_at = now()
       WHERE id = $4`,
          [req.file.originalname || req.file.filename, newRelPath, mimeType, id],
        );
        const out = await client.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
          [id],
        );
        await client.query('COMMIT');
        committed = true;
        const mapped = mapLeaveRowToApi(out.rows[0]);
        broadcastLeaveUpdated('attachment_uploaded', mapped);
        res.json(mapped);
      } catch (err) {
        if (client) {
          try {
            await client.query('ROLLBACK');
          } catch (_) {}
        }
        console.error('[leave POST /:id/attachment]', err);
        res.status(500).json({ error: 'Failed to upload attachment' });
      } finally {
        cleanupStoredLeaveAttachment(
          attachmentReplacementCleanupPath({
            committed,
            oldAttachmentPath,
            newAttachmentPath: newRelPath,
          }),
        );
        if (client) client.release();
      }
    },

    deleteAttachment: async (req, res) => {
      const userId = req.user?.id;
      const role = req.user?.role;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      let client = null;
      let oldAttachmentPath = null;
      try {
        client = await pool.connect();
        await client.query('BEGIN');
        const isAdmin = role === 'admin' || role === 'hr';
        const existing = await client.query(
          `SELECT id, status, attachment_path
       FROM leave_requests
       WHERE id = $1 AND ($2 = true OR user_id = $3 OR employee_id = $3)
       FOR UPDATE`,
          [id, isAdmin, userId],
        );
        if (existing.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Leave request not found' });
        }
        const row = existing.rows[0];
        if (!canModifyLeaveAttachment(row.status)) {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error:
              'Attachment is locked after submission. It can only be changed while the request is a draft or has been returned.',
          });
        }
        oldAttachmentPath = row.attachment_path || null;
        await client.query(
          `UPDATE leave_requests
       SET attachment_name = NULL, attachment_path = NULL, attachment_mime_type = NULL, attachment_uploaded_at = NULL, updated_at = now()
       WHERE id = $1`,
          [id],
        );
        const out = await client.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
          [id],
        );
        await client.query('COMMIT');
        if (oldAttachmentPath) cleanupStoredLeaveAttachment(oldAttachmentPath);
        const mapped = mapLeaveRowToApi(out.rows[0]);
        broadcastLeaveUpdated('attachment_removed', mapped);
        res.json(mapped);
      } catch (err) {
        if (client) {
          try {
            await client.query('ROLLBACK');
          } catch (_) {}
        }
        console.error('[leave DELETE /:id/attachment]', err);
        res.status(500).json({ error: 'Failed to remove attachment' });
      } finally {
        if (client) client.release();
      }
    },

    downloadAttachment: async (req, res) => {
      const userId = req.user?.id;
      const role = req.user?.role;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      try {
        const rows = await pool.query(
          `SELECT lr.user_id, lr.employee_id, lr.status, lr.workflow_snapshot,
              lr.assigned_department_head_id,lr.final_reviewer_user_id,lr.final_review_route,
              lr.attachment_path, lr.attachment_name, lr.attachment_mime_type,
              EXISTS (
                SELECT 1 FROM leave_request_department_reviewers lrr
                WHERE lrr.leave_request_id = lr.id
                  AND lrr.reviewer_id = $2::uuid
              ) AS is_snapshotted_reviewer
       FROM leave_requests lr
       WHERE lr.id = $1`,
          [id, userId],
        );
        if (rows.rows.length === 0)
          return res.status(404).json({ error: 'Leave request not found' });
        const row = rows.rows[0];
        const targetUserId = row.user_id || row.employee_id;
        const assignedDepartmentHeadId =
          row.status === 'pending_department_head'
            ? (row.is_snapshotted_reviewer ? userId : row.assigned_department_head_id) || null
            : null;
        let historicalDepartmentHeadAction = null;
        const isOwner = targetUserId === userId;
        const isHrOrAdmin = role === 'admin' || role === 'hr';
        if (!isOwner && !isHrOrAdmin) {
          const history = await pool.query(
            `SELECT action
         FROM leave_request_history
         WHERE leave_request_id = $1
           AND acted_by = $2
           AND action = ANY($3::text[])
         ORDER BY acted_at DESC
         LIMIT 1`,
            [id, userId, Array.from(DEPARTMENT_HEAD_HISTORY_ACTIONS)],
          );
          historicalDepartmentHeadAction = history.rows[0]?.action || null;
        }
        const workflowRead =
          await require('../../../services/sharedWorkflowInbox').pendingReadAccess(
            pool,
            'leave',
            row,
            req.user,
          );
        const access =
          workflowRead === false
            ? { allowed: false, reason: 'not_authorized' }
            : workflowRead === true || req.sharedWorkflowRead
              ? { allowed: true, reason: 'assigned_workflow_reviewer' }
              : resolveLeaveAttachmentAccess({
                  role:
                    ['mayor', 'mayor_direct'].includes(row.final_review_route) &&
                    (await workflowEngine.isCurrentMayor(pool, req.user))
                      ? 'hr'
                      : role,
                  userId,
                  ownerUserId: targetUserId,
                  requestStatus: row.status,
                  assignedDepartmentHeadId,
                  historicalDepartmentHeadAction,
                });
        const auditBase = {
          leaveRequestId: id,
          attachmentName: row.attachment_name || null,
          accessedBy: userId,
          actorRole: role || null,
          accessReason: access.reason,
          ipAddress: req.ip || req.socket?.remoteAddress || null,
          userAgent: req.get('user-agent') || null,
        };
        if (!access.allowed) {
          await recordLeaveAttachmentAccess(pool, {
            ...auditBase,
            accessOutcome: 'denied',
          });
          return res.status(404).json({ error: 'Leave request not found' });
        }
        if (!row.attachment_path) {
          await recordLeaveAttachmentAccess(pool, {
            ...auditBase,
            accessOutcome: 'missing_attachment',
          });
          return res.status(404).json({ error: 'No attachment for this request' });
        }
        const uploadRoot = path.resolve(UPLOAD_DIR);
        const filePath = path.resolve(uploadRoot, String(row.attachment_path));
        const isStoredFile =
          filePath !== uploadRoot &&
          filePath.startsWith(`${uploadRoot}${path.sep}`) &&
          fs.existsSync(filePath) &&
          fs.statSync(filePath).isFile();
        if (!isStoredFile) {
          await recordLeaveAttachmentAccess(pool, {
            ...auditBase,
            accessOutcome: 'missing_file',
          });
          return res.status(404).json({ error: 'Attachment file not found' });
        }
        await recordLeaveAttachmentAccess(pool, {
          ...auditBase,
          accessOutcome: 'allowed',
        });
        const filename = row.attachment_name || 'attachment';
        res.setHeader('Content-Disposition', `inline; filename="${filename}"`);
        if (row.attachment_mime_type) res.setHeader('Content-Type', row.attachment_mime_type);
        res.sendFile(filePath);
      } catch (err) {
        console.error('[leave GET /:id/attachment]', err);
        res.status(500).json({ error: 'Failed to fetch attachment' });
      }
    },
  };
};
