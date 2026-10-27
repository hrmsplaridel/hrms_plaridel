'use strict';
module.exports = function createLeaveControllers({
  LEAVE_REVOKE_WINDOW_DAYS,
  LEAVE_REVOKE_WINDOW_MS,
  approvedPaidDaysForRevoke,
  assertFinalLeaveReviewer,
  broadcastDtrLeaveRefresh,
  broadcastLeaveUpdated,
  fetchBalanceSnapshot,
  insertLeaveBalanceLedger,
  insertLeaveRequestHistory,
  leaveNotifications,
  mapLeaveRowToApi,
  notifySafe,
  pool,
  removeApprovedLeaveCoverage,
  resolveBalanceLedgerLeaveType,
  toIsoDateStr,
}) {
  return {
    revokeLeave: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks =
        (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim() || null;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT lr.id, lr.status,
              COALESCE(lr.number_of_days, lr.total_days) AS days,
              lr.user_id, lr.employee_id,
              lr.start_date, lr.end_date,
              lr.approved_at, lr.reviewed_at, lr.paper_approval_record,
              lr.approved_days_with_pay, lr.approved_days_without_pay,
              lt.name AS leave_type_name
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
        const r = current.rows[0];
        await assertFinalLeaveReviewer(client, r.user_id || r.employee_id, reviewerId, 'leave', id);
        if (r.paper_approval_record) {
          await client.query('ROLLBACK');
          return res.status(409).json({error:'Approved paper records require a documented paper correction or cancellation; digital approval revocation is not available.'});
        }
        if (r.status !== 'approved') {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: `Cannot revoke a leave request with status '${r.status}'. Only approved requests can be revoked.`,
          });
        }

        const approvalTimestamp = r.approved_at || r.reviewed_at;
        if (!approvalTimestamp) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error:
              'Cannot determine the HR approval date for this request. Approval can only be revoked within 3 days.',
          });
        }
        const approvedAt = new Date(approvalTimestamp);
        const revokeDeadline = new Date(approvedAt.getTime() + LEAVE_REVOKE_WINDOW_MS);
        if (Date.now() > revokeDeadline.getTime()) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: `Revoke period expired. Approved leave can only be revoked within ${LEAVE_REVOKE_WINDOW_DAYS} days after HR approval.`,
          });
        }

        const targetUserId = r.user_id || r.employee_id;
        const revokeDays = r.days != null ? parseFloat(r.days) : null;
        const revokePaidDays = approvedPaidDaysForRevoke({
          requestedDays: revokeDays,
          approvedDaysWithPay: r.approved_days_with_pay,
        });
        const revokeWithoutPayDays =
          r.approved_days_without_pay != null
            ? parseFloat(r.approved_days_without_pay)
            : Math.max(0, (revokeDays || 0) - revokePaidDays);
        const ltName = r.leave_type_name || null;
        const startStr = toIsoDateStr(r.start_date);
        const endStr = toIsoDateStr(r.end_date);

        // 1. Set status back to 'returned' (employee must re-file or Admin closes it separately).
        await client.query(
          `UPDATE leave_requests
       SET status = 'returned',
           reviewer_id   = $2::uuid,
           reviewer_remarks = $3::text,
           approved_days_with_pay = NULL,
           approved_days_without_pay = NULL,
           approved_other_details = NULL,
           recommendation_remarks = NULL,
           disapproval_reason = NULL,
           approved_by = NULL,
           approved_at = NULL,
           approving_authority_snapshot = '{}'::jsonb,
           reviewed_at   = now(),
           updated_at    = now()
       WHERE id = $1`,
          [id, reviewerId, remarks || 'Approval revoked by admin.'],
        );

        // 2. Restore used_days balance (reverse final approval). Pending was cleared on approve; do not re-add to pending
        //    — request status is 'returned', not a pending workflow; employee may resubmit (submit adds pending again).
        if (revokePaidDays > 0 && targetUserId && ltName) {
          const ledgerType = await resolveBalanceLedgerLeaveType(client, ltName);
          if (ledgerType) {
            const beforeRev = await fetchBalanceSnapshot(client, targetUserId, ledgerType);
            await client.query(
              `UPDATE leave_balances
           SET used_days = GREATEST(0, COALESCE(used_days, 0) - $3::numeric),
               updated_at = now()
           WHERE user_id = $1::uuid AND leave_type = $2::text`,
              [targetUserId, ledgerType, revokePaidDays],
            );
            const afterRev = await fetchBalanceSnapshot(client, targetUserId, ledgerType);
            await insertLeaveBalanceLedger(client, {
              userId: targetUserId,
              leaveType: ledgerType,
              action: 'leave_revoked',
              affectedBucket: 'used',
              daysChanged: afterRev.used_days - beforeRev.used_days,
              oldValue: beforeRev.used_days,
              newValue: afterRev.used_days,
              relatedLeaveRequestId: id,
              actorUserId: reviewerId,
              actorKind: 'admin',
              remarks: remarks || null,
              metadataJson: {
                requested_days: revokeDays,
                restored_paid_days: revokePaidDays,
                approved_days_without_pay: revokeWithoutPayDays,
              },
            });
          }
        }

        // 3. Remove only the leave overlay. Underlying attendance/holiday rows remain intact.
        // Older approvals predate the coverage table, so clean up their generated DTR rows
        // only when no separate coverage record existed.
        const removedCoverageRows = await removeApprovedLeaveCoverage(client, id);
        if (removedCoverageRows === 0) {
          await client.query(
            `DELETE FROM dtr_daily_summary
         WHERE leave_request_id = $1
           AND status = 'on_leave'`,
            [id],
          );
        }

        // 4. Audit trail.
        await insertLeaveRequestHistory(client, {
          leaveRequestId: id,
          action: 'revoked',
          fromStatus: 'approved',
          toStatus: 'returned',
          actedBy: reviewerId,
          remarks: remarks || 'Approval revoked.',
          metadataJson: {
            leave_type: ltName,
            start_date: startStr,
            end_date: endStr,
            number_of_days: revokeDays,
            restored_paid_days: revokePaidDays,
            approved_days_without_pay: revokeWithoutPayDays,
            revoked_by: reviewerId,
          },
        });

        await client.query('COMMIT');
        const out = await pool.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
       WHERE lr.id = $1`,
          [id],
        );
        const mappedRevoke = mapLeaveRowToApi(out.rows[0]);
        notifySafe(() =>
          leaveNotifications.notifyEmployee(pool, {
            employeeUserId: targetUserId,
            leaveRequestId: id,
            type: 'leave_revoked',
            title: 'Approved leave was revoked',
            body:
              remarks ||
              'HR revoked the approval for this leave request. Please review your record and contact HR if needed.',
            metadata: { reviewer_remarks: remarks },
          }),
        );
        broadcastDtrLeaveRefresh('leave_revoked_removed_from_dtr', {
          userId: targetUserId,
          leaveRequestId: id,
          dateFrom: startStr,
          dateTo: endStr,
        });
        broadcastLeaveUpdated('revoked', mappedRevoke);
        res.json(mappedRevoke);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[leave PATCH /:id/revoke]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to revoke leave approval' });
      } finally {
        client.release();
      }
    },
  };
};
