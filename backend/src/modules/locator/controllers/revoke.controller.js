'use strict';
module.exports = function createLocatorControllers({
  broadcastLocatorUpdated,
  evaluateLocatorRevocation,
  fetchLocatorSlipDetails,
  locatorNotifications,
  notifySafe,
  pool,
  recordLocatorWorkflowEvent,
}) {
  return {
    revokeRequest: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const reason = (
        req.body?.revocation_reason ||
        req.body?.reviewer_remarks ||
        req.body?.reason ||
        ''
      )
        .toString()
        .trim();
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT id, status, employee_id, slip_date::text AS slip_date,
              hr_reviewed_at
       FROM locator_slips
       WHERE id = $1::uuid
       FOR UPDATE`,
          [id]
        );
        const row = current.rows[0];
        if (!row) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Locator slip not found' });
        }

        const policy = evaluateLocatorRevocation({
          status: row.status,
          final_review_route: row.final_review_route || 'hr',
          approvedAt: row.hr_reviewed_at,
          reason,
        });
        if (!policy.ok) {
          await client.query('ROLLBACK');
          return res.status(policy.statusCode).json({
            error: policy.error,
            code: policy.code,
            ...(policy.deadline ? { revoke_deadline: policy.deadline.toISOString() } : {}),
          });
        }

        const postingTable = await client.query(
          `SELECT to_regclass('public.leave_attendance_deductions') AS table_name`
        );
        let reconciliationRequired = false;
        if (postingTable.rows[0]?.table_name) {
          const posting = await client.query(
            `SELECT 1
         FROM leave_attendance_deductions
         WHERE user_id = $1::uuid
           AND service_month = date_trunc('month', $2::date)::date
         LIMIT 1`,
            [row.employee_id, row.slip_date]
          );
          reconciliationRequired = posting.rowCount > 0;
        }

        await client.query(
          `UPDATE locator_slips
       SET status = 'revoked',
           revoked_by = $2::uuid,
           revoked_at = now(),
           revocation_reason = $3::text,
           month_end_reconciliation_required = $4::boolean,
           month_end_reconciled_at = NULL,
           updated_at = now()
       WHERE id = $1::uuid`,
          [id, reviewerId, policy.revocationReason, reconciliationRequired]
        );
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: id,
          action: 'approval_revoked',
          fromStatus: 'approved',
          toStatus: 'revoked',
          actorId: reviewerId,
          actorRole: req.user?.role || 'hr',
          remarks: policy.revocationReason,
          metadata: { reconciliation_required: reconciliationRequired },
        });
        await client.query('COMMIT');

        const mapped = await fetchLocatorSlipDetails(pool, id);
        notifySafe(() =>
          locatorNotifications.notifyEmployee(pool, {
            employeeUserId: row.employee_id,
            slipId: id,
            type: 'locator_approval_revoked',
            title: 'Locator approval revoked',
            body: `HR revoked this locator approval. ${policy.revocationReason}`,
            metadata: {
              revocation_reason: policy.revocationReason,
              reconciliation_required: reconciliationRequired,
            },
          })
        );
        broadcastLocatorUpdated('revoked', mapped || row, {
          previousStatus: 'approved',
          dateFrom: row.slip_date,
          dateTo: row.slip_date,
          reconciliationRequired,
        });
        return res.json(mapped);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[locator PATCH /:id/revoke]', err);
        return res.status(500).json({ error: 'Failed to revoke locator approval' });
      } finally {
        client.release();
      }
    },
  };
};
