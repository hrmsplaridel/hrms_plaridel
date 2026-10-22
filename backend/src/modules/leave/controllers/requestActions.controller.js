'use strict';
module.exports = function createLeaveControllers({
  broadcastLeaveUpdated,
  insertLeaveRequestHistory,
  leaveNotifications,
  mapLeaveRowToApi,
  notifySafe,
  pool,
  releasePendingLeaveBalance,
  reservedCreditDaysFromRequest,
  validateEmployeeCancelTransition,
}) {
  return {
    discardDraft: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT id, status, discarded_at
         FROM leave_requests
        WHERE id = $1::uuid AND (user_id = $2::uuid OR employee_id = $2::uuid)
        FOR UPDATE`,
          [req.params.id, userId],
        );
        if (!current.rows.length || current.rows[0].discarded_at) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Draft not found' });
        }
        if (current.rows[0].status !== 'draft') {
          await client.query('ROLLBACK');
          return res.status(409).json({ error: 'Only unsubmitted drafts can be discarded' });
        }
        await client.query(
          'UPDATE leave_requests SET discarded_at = now(), updated_at = now() WHERE id = $1::uuid',
          [req.params.id],
        );
        await insertLeaveRequestHistory(client, {
          leaveRequestId: req.params.id,
          action: 'discarded_draft',
          fromStatus: 'draft',
          toStatus: 'draft',
          actedBy: userId,
          remarks: null,
          metadataJson: null,
        });
        await client.query('COMMIT');
        broadcastLeaveUpdated('discarded_draft', { id: req.params.id, user_id: userId });
        return res.json({ discarded: true });
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        if (err.code === '22P02') return res.status(400).json({ error: 'Invalid draft ID' });
        console.error('[leave PATCH /:id/discard]', err);
        return res.status(500).json({ error: 'Failed to discard draft' });
      } finally {
        client.release();
      }
    },

    cancelLeave: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const reason = (req.body?.reason || '').toString().trim() || null;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        const q = await client.query(
          `SELECT id, status, reserved_credit_days
       FROM leave_requests
       WHERE id = $1 AND (user_id = $2 OR employee_id = $2)
         AND discarded_at IS NULL`,
          [id, userId],
        );
        if (q.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Leave request not found' });
        }
        const status = q.rows[0].status;

        const { nextStatus, historyAction } = validateEmployeeCancelTransition({
          currentStatus: status,
        });

        const cancelledReq = await client.query(
          `UPDATE leave_requests
       SET status = 'cancelled',
           reserved_credit_days = 0,
           details = COALESCE(details, '{}'::jsonb) || jsonb_build_object('cancel_reason', $3::text),
           updated_at = now()
       WHERE id = $1 AND (user_id = $2 OR employee_id = $2)
       RETURNING COALESCE(number_of_days, total_days) AS days, user_id, employee_id, leave_type_id`,
          [id, userId, reason],
        );

        await insertLeaveRequestHistory(client, {
          leaveRequestId: id,
          action: historyAction,
          fromStatus: status,
          toStatus: nextStatus,
          actedBy: userId,
          remarks: reason || null,
          metadataJson: null,
        });

        // FIX #5c: Decrement pending_days on cancel (only if it was in a pending status — not draft).
        if (
          status === 'pending' ||
          status === 'pending_department_head' ||
          status === 'pending_hr' ||
          status === 'pending_mayor'
        ) {
          const cancelRow = cancelledReq.rows[0];
          const cancelDays = reservedCreditDaysFromRequest(q.rows[0]);
          const cancelUserId = cancelRow?.user_id || cancelRow?.employee_id;
          if (cancelDays && cancelDays > 0 && cancelUserId) {
            const ltRow = await client.query('SELECT name FROM leave_types WHERE id = $1', [
              cancelRow.leave_type_id,
            ]);
            const ltName = ltRow.rows[0]?.name || null;
            if (ltName) {
              await releasePendingLeaveBalance(client, {
                userId: cancelUserId,
                leaveTypeName: ltName,
                days: cancelDays,
                leaveRequestId: id,
                actorUserId: userId,
                actorKind: 'user',
                action: 'leave_cancelled',
                remarks: reason || null,
                metadataJson: { cancel_days: cancelDays },
              });
            }
          }
        }

        const out = await client.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
          [id],
        );

        await client.query('COMMIT');
        const mappedCancel = mapLeaveRowToApi(out.rows[0]);
        if (
          status === 'pending' ||
          status === 'pending_department_head' ||
          status === 'pending_hr' ||
          status === 'pending_mayor'
        ) {
          notifySafe(() =>
            leaveNotifications.notifyStakeholdersLeaveCancelled(pool, {
              leaveRequestId: id,
              employeeUserId: userId,
              employeeName: mappedCancel.employee_name,
              previousStatus: status,
              leaveTypeName: mappedCancel.leave_type_name || mappedCancel.leave_type,
              startDateStr: mappedCancel.start_date,
              endDateStr: mappedCancel.end_date,
              cancelReason: reason,
              departmentHeadUserId:
                status === 'pending_department_head'
                  ? mappedCancel.assigned_department_head_id || null
                  : null,
            }),
          );
        }
        broadcastLeaveUpdated('cancelled', mappedCancel, { previousStatus: status });
        res.json(mappedCancel);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[leave PATCH /:id/cancel]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to cancel leave request' });
      } finally {
        client.release();
      }
    },
  };
};
