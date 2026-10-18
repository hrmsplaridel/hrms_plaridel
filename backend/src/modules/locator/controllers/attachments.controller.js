'use strict';
module.exports = function createLocatorControllers({
  LOCATOR_ATTACHMENT_SUBDIR,
  UPLOAD_DIR,
  broadcastLocatorUpdated,
  canModifyLocatorAttachment,
  canReadLocatorAsMayor,
  deleteLocatorAttachment,
  findDepartmentHeadUserId,
  locatorAttachmentFileExists,
  path,
  pool,
  recordLocatorAttachmentAccess,
  recordLocatorWorkflowEvent,
  removeLocatorAttachmentFile,
  replaceLocatorAttachment,
  resolveLocatorAttachmentAccess,
}) {
  return {
    uploadAttachment: async (req, res) => {
      const userId = req.user?.id;
      const relPath = req.file ? `${LOCATOR_ATTACHMENT_SUBDIR}/${req.file.filename}` : null;
      if (!userId) {
        removeLocatorAttachmentFile(relPath);
        return res.status(401).json({ error: 'Not authenticated' });
      }
      if (!req.file) return res.status(400).json({ error: 'Attachment is required.' });
      try {
        const attachment = await replaceLocatorAttachment({
          dbPool: pool,
          slipId: req.params.id,
          employeeId: userId,
          attachment: {
            name: req.file.originalname || 'attachment',
            path: relPath,
            mimeType: req.file.mimetype || null,
          },
          canModifyStatus: canModifyLocatorAttachment,
          recordHistory: recordLocatorWorkflowEvent,
          removeFile: removeLocatorAttachmentFile,
        });
        broadcastLocatorUpdated('attachment_replaced', {
          id: req.params.id,
          employee_id: userId,
        });
        res.json(attachment);
      } catch (err) {
        if (err?.statusCode) {
          return res.status(err.statusCode).json({ error: err.message });
        }
        console.error('[locator POST /:id/attachment]', err);
        res.status(500).json({ error: 'Failed to upload attachment' });
      }
    },

    deleteAttachment: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      try {
        await deleteLocatorAttachment({
          dbPool: pool,
          slipId: req.params.id,
          employeeId: userId,
          canModifyStatus: canModifyLocatorAttachment,
          recordHistory: recordLocatorWorkflowEvent,
          removeFile: removeLocatorAttachmentFile,
        });
        broadcastLocatorUpdated('attachment_removed', {
          id: req.params.id,
          employee_id: userId,
        });
        res.json({ ok: true });
      } catch (err) {
        if (err?.statusCode) {
          return res.status(err.statusCode).json({ error: err.message });
        }
        console.error('[locator DELETE /:id/attachment]', err);
        res.status(500).json({ error: 'Failed to remove attachment' });
      }
    },

    downloadAttachment: async (req, res) => {
      const userId = req.user?.id;
      const role = req.user?.role;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      try {
        const current = await pool.query(
          `SELECT ls.id,
              ls.employee_id,
              ls.department_id,
              ls.assigned_department_head_id,
              ls.status,
              ls.dept_head_reviewer_id,
              ls.final_review_route,
              ls.workflow_snapshot,
              ls.attachment_name,
              ls.attachment_path,
              ls.attachment_mime_type,
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

        const normalizedRole = String(role || '')
          .trim()
          .toLowerCase();
        const isOwner = String(row.employee_id) === String(userId);
        const isHrOrAdmin = normalizedRole === 'hr' || normalizedRole === 'admin';
        let assignedDepartmentHeadId =
          (row.is_snapshotted_reviewer ? userId : row.assigned_department_head_id) || null;
        if (
          !assignedDepartmentHeadId &&
          !isOwner &&
          !isHrOrAdmin &&
          row.status === 'pending_department_head' &&
          row.department_id
        ) {
          assignedDepartmentHeadId = await findDepartmentHeadUserId(pool, row.department_id);
        }
        const workflowRead =
          await require('../../../services/sharedWorkflowInbox').pendingReadAccess(
            pool,
            'locator',
            row,
            req.user
          );
        const access =
          workflowRead === false
            ? { allowed: false, reason: 'not_authorized' }
            : workflowRead === true || req.sharedWorkflowRead
              ? { allowed: true, reason: 'assigned_workflow_reviewer' }
              : resolveLocatorAttachmentAccess({
                  finalReviewRoute: row.final_review_route,
                  canReadAsMayor: await canReadLocatorAsMayor(
                    pool,
                    req.user,
                    row.final_review_route
                  ),
                  role,
                  userId,
                  ownerUserId: row.employee_id,
                  requestStatus: row.status,
                  assignedDepartmentHeadId,
                  reviewingDepartmentHeadId: row.dept_head_reviewer_id,
                });
        const auditBase = {
          locatorSlipId: row.id,
          attachmentName: row.attachment_name || null,
          accessedBy: userId,
          actorRole: role || null,
          accessReason: access.reason,
          ipAddress: req.ip || req.socket?.remoteAddress || null,
          userAgent: req.get('user-agent') || null,
        };
        if (!access.allowed) {
          await recordLocatorAttachmentAccess(pool, {
            ...auditBase,
            accessOutcome: 'denied',
          });
          return res.status(404).json({ error: 'Locator slip not found' });
        }
        if (!row.attachment_path) {
          await recordLocatorAttachmentAccess(pool, {
            ...auditBase,
            accessOutcome: 'missing_attachment',
          });
          return res.status(404).json({ error: 'No attachment for this request' });
        }
        if (!locatorAttachmentFileExists(row.attachment_path)) {
          await recordLocatorAttachmentAccess(pool, {
            ...auditBase,
            accessOutcome: 'missing_file',
          });
          return res.status(404).json({ error: 'Attachment file not found' });
        }
        await recordLocatorAttachmentAccess(pool, {
          ...auditBase,
          accessOutcome: 'allowed',
        });
        const filePath = path.resolve(UPLOAD_DIR, row.attachment_path);
        const filename = (row.attachment_name || 'attachment')
          .replace(/[^\w.\- ()]/g, '_')
          .slice(0, 180);
        if (row.attachment_mime_type) res.setHeader('Content-Type', row.attachment_mime_type);
        res.setHeader('Content-Disposition', `inline; filename="${filename}"`);
        res.sendFile(filePath);
      } catch (err) {
        console.error('[locator GET /:id/attachment]', err);
        res.status(500).json({ error: 'Failed to fetch attachment' });
      }
    },
  };
};
