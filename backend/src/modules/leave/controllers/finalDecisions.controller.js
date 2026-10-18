'use strict';
module.exports = function createLeaveControllers({
  assertFinalLeaveReviewer,
  broadcastDtrLeaveRefresh,
  broadcastLeaveUpdated,
  finalizeLeaveApproval,
  insertLeaveRequestHistory,
  leaveNotifications,
  mapLeaveRowToApi,
  notifySafe,
  pool,
  releasePendingLeaveBalance,
  requireHrApprovalSignature,
  reservedCreditDaysFromRequest,
  resolveApprovalAllocation,
  validateAdminTransition,
  workflowEngine,
}) {
  return {
    approveFinal: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks =
        (req.body?.reviewer_remarks || req.body?.hr_remarks || '').toString().trim() || null;
      const recommendationRemarks =
        (req.body?.recommendation_remarks || req.body?.recommendationRemarks || '')
          .toString()
          .trim() || null;
      const approvedOtherDetails =
        (req.body?.approved_other_details || req.body?.approvedOtherDetails || '')
          .toString()
          .trim() || null;
      const approvedDaysWithPayRaw =
        req.body?.approved_days_with_pay ?? req.body?.approvedDaysWithPay;
      const approvedDaysWithoutPayRaw =
        req.body?.approved_days_without_pay ?? req.body?.approvedDaysWithoutPay;
      try {
        const client = await pool.connect();
        try {
          await client.query('BEGIN');
          const existing = await client.query(
            `SELECT lr.id, lr.status, lr.user_id, lr.employee_id, lr.start_date, lr.end_date,
               lr.attachment_path, lr.signature_revision,
               COALESCE(lr.number_of_days, lr.total_days) AS days,
                lr.reserved_credit_days,
                lt.name AS leave_type_name
         FROM leave_requests lr
         LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
         WHERE lr.id = $1
         FOR UPDATE OF lr`,
            [id],
          );
          if (existing.rows.length === 0) {
            await client.query('ROLLBACK');
            return res.status(404).json({ error: 'Leave request not found' });
          }
          const r = existing.rows[0];
          const targetUserId = r.user_id || r.employee_id;
          await assertFinalLeaveReviewer(client, targetUserId, reviewerId, 'leave', id);
          // Prevent double deduction: if already approved, return current record and skip updates.
          if (r.status === 'approved') {
            await client.query('COMMIT');
            const out = await pool.query(
              `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
           FROM leave_requests lr
           LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
           LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
           WHERE lr.id = $1`,
              [id],
            );
            return res.json(mapLeaveRowToApi(out.rows[0]));
          }

          const workflowDecision = await workflowEngine.workflowDecision(
            client,
            'leave',
            id,
            reviewerId,
            'approve',
            req.sharedWorkflowExpected,
          );
          if (workflowDecision && workflowDecision.status !== 'approved') {
            const allocation = resolveApprovalAllocation({
              requestedDays: r.days,
              approvedDaysWithPay: approvedDaysWithPayRaw,
              approvedDaysWithoutPay: approvedDaysWithoutPayRaw,
            });
            await requireHrApprovalSignature(client, id, reviewerId);
            await workflowEngine.saveWorkflow(client, 'leave', id, workflowDecision.snapshot);
            await client.query(
              'UPDATE leave_requests SET status=$2,approved_days_with_pay=$3,approved_days_without_pay=$4,updated_at=now() WHERE id=$1::uuid',
              [
                id,
                workflowDecision.status,
                allocation.approvedDaysWithPay,
                allocation.approvedDaysWithoutPay,
              ],
            );
            await insertLeaveRequestHistory(client, {
              leaveRequestId: id,
              action: 'workflow_step_approved',
              fromStatus: r.status,
              toStatus: workflowDecision.status,
              actedBy: reviewerId,
              remarks,
              metadataJson: { workflow_step: workflowDecision.step },
            });
            await client.query('COMMIT');
            const out = await pool.query(
              `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
           FROM leave_requests lr
           LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
           LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
           WHERE lr.id = $1`,
              [id],
            );
            const mapped = mapLeaveRowToApi(out.rows[0]);
            notifySafe(() =>
              leaveNotifications.notifyAfterSubmit(pool, {
                leaveRequestId: id,
                status: workflowDecision.status,
                employeeUserId: targetUserId,
                employeeName: mapped.employee_name,
                leaveTypeName: mapped.leave_type_name || mapped.leave_type,
                startDateStr: mapped.start_date,
                endDateStr: mapped.end_date,
              }),
            );
            broadcastLeaveUpdated('workflow_step_approved', mapped);
            return res.json(mapped);
          }
          const { row, leaveTypeName, startStr, endStr } = await finalizeLeaveApproval(client, r, {
            id,
            reviewerId,
            remarks,
            recommendationRemarks,
            approvedOtherDetails,
            approvedDaysWithPayRaw,
            approvedDaysWithoutPayRaw,
          });

          await workflowEngine.saveWorkflow(client, 'leave', id, workflowDecision?.snapshot);
          await client.query('COMMIT');
          notifySafe(() =>
            leaveNotifications.notifyEmployee(pool, {
              employeeUserId: targetUserId,
              leaveRequestId: id,
              type: 'leave_approved',
              title: 'Leave request approved',
              body: remarks
                ? `Your leave request was approved. ${remarks}`
                : 'Your leave request was approved.',
              metadata: {
                reviewer_remarks: remarks,
                leave_type: leaveTypeName,
                start_date: startStr,
                end_date: endStr,
              },
            }),
          );
          const mapped = mapLeaveRowToApi({ ...row, leave_type_name: leaveTypeName });
          broadcastDtrLeaveRefresh('leave_approved_applied_to_dtr', {
            userId: targetUserId,
            leaveRequestId: id,
            dateFrom: startStr,
            dateTo: endStr,
          });
          broadcastLeaveUpdated('approved', mapped);
          res.json(mapped);
        } catch (e) {
          await client.query('ROLLBACK');
          throw e;
        } finally {
          client.release();
        }
      } catch (err) {
        if (err && err.statusCode) {
          return res.status(err.statusCode).json({
            error: err.message,
            ...(err.details && typeof err.details === 'object' ? err.details : {}),
          });
        }
        console.error('[leave PATCH /:id/approve]', err);
        const msg = err && err.message ? err.message : 'Failed to approve leave request';
        res.status(500).json({ error: msg });
      }
    },

    rejectFinal: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks =
        (req.body?.reviewer_remarks || req.body?.reason || req.body?.hr_remarks || '')
          .toString()
          .trim() || null;
      const disapprovalReason =
        (
          req.body?.disapproval_reason ||
          req.body?.disapprovalReason ||
          req.body?.reason ||
          req.body?.reviewer_remarks ||
          ''
        )
          .toString()
          .trim() || null;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT lr.status, COALESCE(lr.number_of_days, lr.total_days) AS days,
              lr.reserved_credit_days,
              lr.user_id, lr.employee_id, lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       WHERE lr.id = $1
       FOR UPDATE OF lr`,
          [id],
        );
        if (current.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Leave request not found' });
        }
        const currentRow = current.rows[0];

        await assertFinalLeaveReviewer(
          client,
          currentRow.user_id || currentRow.employee_id,
          reviewerId,
          'leave',
          id,
        );

        const { nextStatus: rejectNextStatus, historyAction } = validateAdminTransition({
          currentStatus: currentRow.status,
          desiredStatus: 'rejected',
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
       SET status = $4::text,
           reviewer_id = $2::uuid,
           reviewer_remarks = $3::text,
           disapproval_reason = $5::text,
           reserved_credit_days = 0,
           reviewed_at = now(),
           updated_at = now()
       WHERE id = $1`,
          [id, reviewerId, remarks, rejectNextStatus, disapprovalReason],
        );

        await insertLeaveRequestHistory(client, {
          leaveRequestId: id,
          action: historyAction,
          fromStatus: currentRow.status,
          toStatus: rejectNextStatus,
          actedBy: reviewerId,
          remarks: remarks || null,
          metadataJson: workflowEngine.isShared(workflowAction?.snapshot)
            ? { workflow_step: workflowAction.step }
            : null,
        });

        // FIX #5d: Decrement pending_days on reject.
        const rejectDays = reservedCreditDaysFromRequest(currentRow);
        const rejectUserId = currentRow.user_id || currentRow.employee_id;
        const rejectLtName = currentRow.leave_type_name || null;
        if (rejectDays && rejectDays > 0 && rejectUserId && rejectLtName) {
          await releasePendingLeaveBalance(client, {
            userId: rejectUserId,
            leaveTypeName: rejectLtName,
            days: rejectDays,
            leaveRequestId: id,
            actorUserId: reviewerId,
            actorKind: 'admin',
            action: 'leave_rejected',
            remarks,
            metadataJson: { stage: 'hr' },
          });
        }

        await client.query('COMMIT');
        // FIX #3: Re-fetch with full join so leave_type_name is in the response.
        const out = await pool.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
          [id],
        );
        const mappedReject = mapLeaveRowToApi(out.rows[0]);
        const empRejectId = currentRow.user_id || currentRow.employee_id;
        const disapproval = disapprovalReason || remarks || mappedReject.disapproval_reason || null;
        notifySafe(() =>
          leaveNotifications.notifyEmployee(pool, {
            employeeUserId: empRejectId,
            leaveRequestId: id,
            type: 'leave_rejected_hr',
            title: 'Leave request not approved',
            body: disapproval
              ? `HR did not approve this leave request. ${disapproval}`
              : 'HR did not approve this leave request.',
            metadata: { reviewer_remarks: remarks, disapproval_reason: disapprovalReason },
          }),
        );
        broadcastLeaveUpdated('rejected', mappedReject);
        res.json(mappedReject);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[leave PATCH /:id/reject]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to reject leave request' });
      } finally {
        client.release();
      }
    },

    returnFinal: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks =
        (req.body?.reviewer_remarks || req.body?.reason || req.body?.hr_remarks || '')
          .toString()
          .trim() || null;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT lr.status, COALESCE(lr.number_of_days, lr.total_days) AS days,
              lr.reserved_credit_days,
              lr.user_id, lr.employee_id, lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       WHERE lr.id = $1
       FOR UPDATE OF lr`,
          [id],
        );
        if (current.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Leave request not found' });
        }
        const currentRow = current.rows[0];

        // Admin can return from pending_hr or legacy pending
        if (
          currentRow.status !== 'pending_hr' &&
          currentRow.status !== 'pending_mayor' &&
          currentRow.status !== 'pending'
        ) {
          await client.query('ROLLBACK');
          return res
            .status(400)
            .json({ error: `Cannot return request with status '${currentRow.status}'` });
        }
        await assertFinalLeaveReviewer(
          client,
          currentRow.user_id || currentRow.employee_id,
          reviewerId,
          'leave',
          id,
        );
        const historyAction = 'returned';

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
       SET status = 'returned',
           reviewer_id = $2::uuid,
           reviewer_remarks = $3::text,
           reserved_credit_days = 0,
           reviewed_at = now(),
           updated_at = now()
       WHERE id = $1`,
          [id, reviewerId, remarks],
        );

        await insertLeaveRequestHistory(client, {
          leaveRequestId: id,
          action: historyAction,
          fromStatus: currentRow.status,
          toStatus: 'returned',
          actedBy: reviewerId,
          remarks: remarks || null,
          metadataJson: workflowEngine.isShared(workflowAction?.snapshot)
            ? { workflow_step: workflowAction.step }
            : null,
        });

        // FIX #5e: Decrement pending_days when a request is returned to employee.
        const returnDays = reservedCreditDaysFromRequest(currentRow);
        const returnUserId = currentRow.user_id || currentRow.employee_id;
        const returnLtName = currentRow.leave_type_name || null;
        if (returnDays && returnDays > 0 && returnUserId && returnLtName) {
          await releasePendingLeaveBalance(client, {
            userId: returnUserId,
            leaveTypeName: returnLtName,
            days: returnDays,
            leaveRequestId: id,
            actorUserId: reviewerId,
            actorKind: 'admin',
            action: 'leave_returned',
            remarks,
            metadataJson: { stage: 'hr' },
          });
        }

        await client.query('COMMIT');
        // FIX #3: Re-fetch with full join so leave_type_name is in the response.
        const out = await pool.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
          [id],
        );
        const mappedHrReturn = mapLeaveRowToApi(out.rows[0]);
        const empReturnId = currentRow.user_id || currentRow.employee_id;
        notifySafe(() =>
          leaveNotifications.notifyEmployee(pool, {
            employeeUserId: empReturnId,
            leaveRequestId: id,
            type: 'leave_returned_hr',
            title: 'Leave request returned for correction',
            body: remarks
              ? `HR returned this request for correction. ${remarks}`
              : 'HR returned this leave request for correction.',
            metadata: { reviewer_remarks: remarks },
          }),
        );
        broadcastLeaveUpdated('returned', mappedHrReturn);
        res.json(mappedHrReturn);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[leave PATCH /:id/return]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to return leave request' });
      } finally {
        client.release();
      }
    },
  };
};
