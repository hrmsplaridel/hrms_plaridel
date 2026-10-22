'use strict';
module.exports = function createLeaveControllers({
  assertAnnualQuotaLeaveLimit,
  assertDepartmentApprovalFinalReviewer,
  broadcastDtrLeaveRefresh,
  broadcastLeaveUpdated,
  finalizeLeaveApproval,
  insertLeaveRequestHistory,
  leaveNotifications,
  mapLeaveRowToApi,
  notifySafe,
  pool,
  releasePendingLeaveBalance,
  requireDepartmentHeadApprovalSignature,
  reservedCreditDaysFromRequest,
  toIsoDateStr,
  validateDepartmentHeadTransition,
  workflowEngine,
}) {
  return {
    approveDepartment: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks = (req.body?.reviewer_remarks || '').toString().trim() || null;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const existing = await client.query(
          `SELECT lr.id, lr.status, lr.user_id, lr.employee_id,
              lr.start_date, lr.end_date, lr.review_department_id,
              lr.final_review_route, lr.attachment_path, lr.reserved_credit_days, lr.signature_revision,
              COALESCE(lr.number_of_days, lr.total_days) AS days,
              lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       WHERE lr.id = $1
         AND (
           lr.assigned_department_head_id = $2::uuid
           OR EXISTS (
             SELECT 1 FROM leave_request_department_reviewers lrr
             WHERE lrr.leave_request_id = lr.id
               AND lrr.reviewer_id = $2::uuid
           )
         )
       FOR UPDATE OF lr`,
          [id, reviewerId],
        );
        if (existing.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Leave request not found or not assigned to you' });
        }
        const r = existing.rows[0];
        const workflowDecision = await workflowEngine.workflowDecision(
          client,
          'leave',
          id,
          reviewerId,
          'approve',
          req.sharedWorkflowExpected,
        );
        const legacyTransition = validateDepartmentHeadTransition({
          currentStatus: r.status,
          desiredStatus: 'pending_hr',
          finalReviewRoute: r.final_review_route,
        });
        const nextStatus = workflowDecision?.status || legacyTransition.nextStatus;
        const historyAction = legacyTransition.historyAction;
        if (!workflowDecision && nextStatus === 'pending_hr') {
          await assertDepartmentApprovalFinalReviewer(
            client,
            r.user_id || r.employee_id,
            reviewerId,
            'leave',
            id,
          );
        }
        await assertAnnualQuotaLeaveLimit(client, {
          userId: r.user_id || r.employee_id,
          leaveTypeName: r.leave_type_name || null,
          startStr: toIsoDateStr(r.start_date),
          endStr: toIsoDateStr(r.end_date),
          excludeId: id,
        });
        await requireDepartmentHeadApprovalSignature(client, id, reviewerId);
        if (nextStatus === 'approved') {
          await finalizeLeaveApproval(client, r, {
            id,
            reviewerId,
            remarks,
            departmentFinal: true,
          });
        } else {
          await client.query(
            `UPDATE leave_requests
         SET status = $2, reviewer_id = $3, reviewer_remarks = $4, reviewed_at = now(), updated_at = now()
         WHERE id = $1`,
            [id, nextStatus, reviewerId, remarks],
          );
          await insertLeaveRequestHistory(client, {
            leaveRequestId: id,
            action: historyAction,
            fromStatus: r.status,
            toStatus: nextStatus,
            actedBy: reviewerId,
            remarks,
            metadataJson: {
              department_id: r.review_department_id || null,
              revision: r.signature_revision,
            },
          });
        }
        await workflowEngine.saveWorkflow(client, 'leave', id, workflowDecision?.snapshot);
        await client.query('COMMIT');
        const out = await pool.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
          [id],
        );
        const mappedDhApprove = mapLeaveRowToApi(out.rows[0]);
        if (nextStatus !== 'approved')
          notifySafe(() =>
            leaveNotifications.notifyDepartmentHeadApprovedForHr(pool, {
              employeeUserId: r.user_id || r.employee_id,
              leaveRequestId: id,
              employeeName: mappedDhApprove.employee_name,
              leaveTypeName: mappedDhApprove.leave_type_name || mappedDhApprove.leave_type,
              startDateStr: mappedDhApprove.start_date,
              endDateStr: mappedDhApprove.end_date,
            }),
          );
        notifySafe(() =>
          leaveNotifications.notifyEmployee(pool, {
            employeeUserId: r.user_id || r.employee_id,
            leaveRequestId: id,
            type: nextStatus === 'approved' ? 'leave_approved' : 'leave_endorsed_department_head',
            title:
              nextStatus === 'approved'
                ? 'Leave request approved'
                : 'Leave request endorsed by department head',
            body:
              nextStatus === 'approved'
                ? `Your leave request was approved by the department reviewer.${!workflowDecision || workflowDecision.snapshot.manual_signing_required ? ' The Mayor signs the printed form manually.' : ''}${remarks ? ` ${remarks}` : ''}`
                : remarks
                  ? `Your leave request has been endorsed by your department head and forwarded to HR for final approval. ${remarks}`
                  : nextStatus === 'pending_mayor'
                    ? 'Your request passed department review and is awaiting Mayor approval.'
                    : 'Your leave request has been endorsed by your department head and forwarded to HR for final approval.',
            metadata: { reviewer_remarks: remarks },
          }),
        );
        if (nextStatus === 'approved')
          broadcastDtrLeaveRefresh('leave_approved_applied_to_dtr', {
            userId: r.user_id || r.employee_id,
            leaveRequestId: id,
            dateFrom: toIsoDateStr(r.start_date),
            dateTo: toIsoDateStr(r.end_date),
          });
        broadcastLeaveUpdated('department_head_approved', mappedDhApprove);
        res.json(mappedDhApprove);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[leave PATCH /:id/department-head-approve]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to approve (department head)' });
      } finally {
        client.release();
      }
    },

    rejectDepartment: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks =
        (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim() || null;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const existing = await client.query(
          `SELECT lr.id, lr.status, lr.user_id, lr.employee_id,
              lr.review_department_id,
              COALESCE(lr.number_of_days, lr.total_days) AS days,
              lr.reserved_credit_days, lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       WHERE lr.id = $1
         AND (
           lr.assigned_department_head_id = $2::uuid
           OR EXISTS (
             SELECT 1 FROM leave_request_department_reviewers lrr
             WHERE lrr.leave_request_id = lr.id
               AND lrr.reviewer_id = $2::uuid
           )
         )
       FOR UPDATE OF lr`,
          [id, reviewerId],
        );
        if (existing.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Leave request not found or not assigned to you' });
        }
        const r = existing.rows[0];
        const { nextStatus, historyAction } = validateDepartmentHeadTransition({
          currentStatus: r.status,
          desiredStatus: 'rejected_by_department_head',
        });
        const workflowAction = await workflowEngine.workflowDecision(
          client,
          'leave',
          id,
          reviewerId,
          'reject',
          req.sharedWorkflowExpected,
        );
        await workflowEngine.saveWorkflow(client, 'leave', id, workflowAction?.snapshot);
        await client.query(
          `UPDATE leave_requests
       SET status = $2, reviewer_id = $3, reviewer_remarks = $4,
           reserved_credit_days = 0, reviewed_at = now(), updated_at = now()
       WHERE id = $1`,
          [id, nextStatus, reviewerId, remarks],
        );
        await insertLeaveRequestHistory(client, {
          leaveRequestId: id,
          action: historyAction,
          fromStatus: r.status,
          toStatus: nextStatus,
          actedBy: reviewerId,
          remarks,
          metadataJson: { department_id: r.review_department_id || null },
        });
        // Decrement pending_days on dept head reject
        const rejectDays = reservedCreditDaysFromRequest(r);
        const rejectUserId = r.user_id || r.employee_id;
        const rejectLtName = r.leave_type_name || null;
        if (rejectDays && rejectDays > 0 && rejectUserId && rejectLtName) {
          await releasePendingLeaveBalance(client, {
            userId: rejectUserId,
            leaveTypeName: rejectLtName,
            days: rejectDays,
            leaveRequestId: id,
            actorUserId: reviewerId,
            actorKind: 'user',
            action: 'leave_rejected',
            remarks,
            metadataJson: { stage: 'department_head' },
          });
        }
        await client.query('COMMIT');
        const out = await pool.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
          [id],
        );
        const mappedDhReject = mapLeaveRowToApi(out.rows[0]);
        notifySafe(() =>
          leaveNotifications.notifyEmployee(pool, {
            employeeUserId: r.user_id || r.employee_id,
            leaveRequestId: id,
            type: 'leave_rejected_department_head',
            title: 'Leave request not approved by department head',
            body: remarks
              ? `Your request was not approved. ${remarks}`
              : 'Your leave request was not approved by your department head.',
            metadata: { reviewer_remarks: remarks },
          }),
        );
        broadcastLeaveUpdated('department_head_rejected', mappedDhReject);
        res.json(mappedDhReject);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[leave PATCH /:id/department-head-reject]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to reject (department head)' });
      } finally {
        client.release();
      }
    },

    returnDepartment: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks =
        (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim() || null;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const existing = await client.query(
          `SELECT lr.id, lr.status, lr.user_id, lr.employee_id,
              lr.review_department_id,
              COALESCE(lr.number_of_days, lr.total_days) AS days,
              lr.reserved_credit_days, lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       WHERE lr.id = $1
         AND (
           lr.assigned_department_head_id = $2::uuid
           OR EXISTS (
             SELECT 1 FROM leave_request_department_reviewers lrr
             WHERE lrr.leave_request_id = lr.id
               AND lrr.reviewer_id = $2::uuid
           )
         )
       FOR UPDATE OF lr`,
          [id, reviewerId],
        );
        if (existing.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Leave request not found or not assigned to you' });
        }
        const r = existing.rows[0];
        const { nextStatus, historyAction } = validateDepartmentHeadTransition({
          currentStatus: r.status,
          desiredStatus: 'returned',
        });
        const workflowAction = await workflowEngine.workflowDecision(
          client,
          'leave',
          id,
          reviewerId,
          'return',
          req.sharedWorkflowExpected,
        );
        await workflowEngine.saveWorkflow(client, 'leave', id, workflowAction?.snapshot);
        await client.query(
          `UPDATE leave_requests
       SET status = $2, reviewer_id = $3, reviewer_remarks = $4,
           reserved_credit_days = 0, reviewed_at = now(), updated_at = now()
       WHERE id = $1`,
          [id, nextStatus, reviewerId, remarks],
        );
        await insertLeaveRequestHistory(client, {
          leaveRequestId: id,
          action: historyAction,
          fromStatus: r.status,
          toStatus: nextStatus,
          actedBy: reviewerId,
          remarks,
          metadataJson: { department_id: r.review_department_id || null },
        });
        // Decrement pending_days on dept head return
        const returnDays = reservedCreditDaysFromRequest(r);
        const returnUserId = r.user_id || r.employee_id;
        const returnLtName = r.leave_type_name || null;
        if (returnDays && returnDays > 0 && returnUserId && returnLtName) {
          await releasePendingLeaveBalance(client, {
            userId: returnUserId,
            leaveTypeName: returnLtName,
            days: returnDays,
            leaveRequestId: id,
            actorUserId: reviewerId,
            actorKind: 'user',
            action: 'leave_returned',
            remarks,
            metadataJson: { stage: 'department_head' },
          });
        }
        await client.query('COMMIT');
        const out = await pool.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
          [id],
        );
        const mappedDhReturn = mapLeaveRowToApi(out.rows[0]);
        notifySafe(() =>
          leaveNotifications.notifyEmployee(pool, {
            employeeUserId: r.user_id || r.employee_id,
            leaveRequestId: id,
            type: 'leave_returned_department_head',
            title: 'Leave request returned for correction',
            body: remarks
              ? `Your department head returned this request for correction. ${remarks}`
              : 'Your department head returned this leave request for correction.',
            metadata: { reviewer_remarks: remarks },
          }),
        );
        broadcastLeaveUpdated('department_head_returned', mappedDhReturn);
        res.json(mappedDhReturn);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[leave PATCH /:id/department-head-return]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to return (department head)' });
      } finally {
        client.release();
      }
    },
  };
};
