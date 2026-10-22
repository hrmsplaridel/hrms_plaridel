'use strict';
module.exports = function createLocatorControllers({
  assertFinalLeaveReviewer,
  broadcastLocatorUpdated,
  evaluateLocatorReturnWindow,
  fetchLocatorSlipDetails,
  findLocatorRequestConflicts,
  locatorConflictPayload,
  locatorNotifications,
  locatorReviewAttachmentError,
  mapLocatorRow,
  normalizeLocatorRejectionReason,
  notifySafe,
  persistLocatorSignature,
  pool,
  recordLocatorWorkflowEvent,
  workflowEngine,
}) {
  return {
    returnForCorrection: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks = (req.body?.reviewer_remarks || req.body?.reason || req.body?.hr_remarks || '')
        .toString()
        .trim();
      if (!remarks) {
        return res.status(400).json({ error: 'Correction remarks are required.' });
      }

      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT id, status, employee_id, slip_date::text AS slip_date_text
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
        if (!['pending_hr', 'pending', 'pending_mayor'].includes(row.status)) {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error: `Cannot return locator slip with status '${row.status}'`,
          });
        }
        await assertFinalLeaveReviewer(client, row.employee_id, reviewerId, 'locator', id);
        const returnWindow = evaluateLocatorReturnWindow({
          slipDate: row.slip_date_text,
        });
        if (!returnWindow.ok) {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error: returnWindow.error,
            code: returnWindow.code,
          });
        }

        const workflowAction = await workflowEngine.workflowDecision(
          client,
          'locator',
          id,
          reviewerId,
          'return',
          req.sharedWorkflowExpected
        );
        await workflowEngine.saveWorkflow(client, 'locator', id, workflowAction?.snapshot);
        await client.query(
          `UPDATE locator_slips
       SET status = 'returned_for_correction',
           hr_reviewer_id = $2::uuid,
           hr_reviewed_at = now(),
           hr_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
          [id, reviewerId, remarks]
        );
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: id,
          action: req.user.role === 'mayor' ? 'mayor_returned' : 'hr_returned',
          fromStatus: row.status,
          toStatus: 'returned_for_correction',
          actorId: reviewerId,
          actorRole: req.user?.role || 'hr',
          remarks,
        });
        await client.query('COMMIT');

        notifySafe(() =>
          locatorNotifications.notifyEmployee(pool, {
            employeeUserId: row.employee_id,
            slipId: id,
            type: 'locator_returned_hr',
            title: 'Locator request returned for correction',
            body: `HR returned this locator request. ${remarks}`,
            metadata: { reviewer_remarks: remarks, returned_by: 'hr' },
          })
        );
        const mapped = await fetchLocatorSlipDetails(pool, id);
        broadcastLocatorUpdated('hr_returned', mapped || row);
        res.json(mapped);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[locator PATCH /:id/return-for-correction]', err);
        if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to return locator slip for correction' });
      } finally {
        client.release();
      }
    },

    approveFinal: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks =
        (req.body?.reviewer_remarks || req.body?.hr_remarks || '').toString().trim() || null;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT ls.id,
              ls.status,
              ls.employee_id,
              ls.slip_date::text AS slip_date,
              ls.am_in,
              ls.am_out,
              ls.pm_in,
              ls.pm_out,
              ls.attachment_path,
              ls.request_type_requires_attachment_snapshot,
              lrt.requires_attachment AS request_type_requires_attachment
       FROM locator_slips ls
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid
       FOR UPDATE OF ls`,
          [id]
        );
        if (current.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Locator slip not found' });
        }
        if (!['pending_hr', 'pending', 'pending_mayor'].includes(current.rows[0].status)) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: `Cannot approve locator slip with status '${current.rows[0].status}'`,
          });
        }
        await assertFinalLeaveReviewer(
          client,
          current.rows[0].employee_id,
          reviewerId,
          'locator',
          id
        );
        const attachmentError = locatorReviewAttachmentError(current.rows[0]);
        if (attachmentError) {
          await client.query('ROLLBACK');
          return res.status(409).json({ error: attachmentError });
        }
        const conflictCheck = await findLocatorRequestConflicts(client, {
          employeeId: current.rows[0].employee_id,
          slipDate: current.rows[0].slip_date,
          slots: current.rows[0],
          excludeSlipId: id,
          phase: 'approval',
        });
        if (!conflictCheck.ok) {
          await client.query('ROLLBACK');
          return res.status(409).json(locatorConflictPayload(conflictCheck));
        }
        const workflowDecision = await workflowEngine.workflowDecision(
          client,
          'locator',
          id,
          reviewerId,
          'approve',
          req.sharedWorkflowExpected
        );
        await persistLocatorSignature(client, req.user, id, 'hr_approver', req.body?.signature);
        await workflowEngine.saveWorkflow(client, 'locator', id, workflowDecision?.snapshot);
        await client.query(
          `UPDATE locator_slips
       SET status = $4,
           hr_reviewer_id = $2::uuid,
           hr_reviewed_at = now(),
           hr_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
          [id, reviewerId, remarks, workflowDecision?.status || 'approved']
        );
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: id,
          action: req.user.role === 'mayor' ? 'mayor_approved' : 'hr_approved',
          fromStatus: current.rows[0].status,
          toStatus: workflowDecision?.status || 'approved',
          actorId: reviewerId,
          actorRole: req.user?.role || 'hr',
          remarks,
        });
        await client.query('COMMIT');

        if (workflowDecision && workflowDecision.status !== 'approved')
          notifySafe(() =>
            locatorNotifications.notifyAfterSubmit(pool, {
              slipId: id,
              status: workflowDecision.status,
              employeeUserId: current.rows[0].employee_id,
              slipDate: current.rows[0].slip_date,
            })
          );
        notifySafe(() =>
          locatorNotifications.notifyEmployee(pool, {
            employeeUserId: current.rows[0].employee_id,
            slipId: id,
            type:
              workflowDecision && workflowDecision.status !== 'approved'
                ? 'locator_workflow_step_approved'
                : 'locator_approved_hr',
            title:
              workflowDecision && workflowDecision.status !== 'approved'
                ? 'Locator request forwarded for approval'
                : 'Locator request approved',
            body:
              workflowDecision && workflowDecision.status !== 'approved'
                ? `Your request passed review and is awaiting ${workflowEngine.stepLabel(workflowDecision.snapshot.steps[workflowDecision.snapshot.current_step])}.`
                : remarks
                  ? `Your locator request was approved. ${remarks}`
                  : req.user.role === 'mayor'
                    ? 'Your locator request was approved by the Mayor.'
                    : 'Your locator request was approved by HR.',
            metadata: { reviewer_remarks: remarks },
          })
        );

        const out = await pool.query(
          `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
          [id]
        );
        const mapped = mapLocatorRow(out.rows[0]);
        broadcastLocatorUpdated('approved', mapped);
        res.json(mapped);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[locator PATCH /:id/approve]', err);
        if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to approve locator slip' });
      } finally {
        client.release();
      }
    },

    rejectFinal: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const reasonValidation = normalizeLocatorRejectionReason(
        req.body?.reviewer_remarks || req.body?.reason || req.body?.hr_remarks
      );
      if (!reasonValidation.valid) {
        return res.status(400).json({ error: reasonValidation.error });
      }
      const remarks = reasonValidation.value;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
       FOR UPDATE`,
          [id]
        );
        if (current.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Locator slip not found' });
        }
        if (!['pending_hr', 'pending', 'pending_mayor'].includes(current.rows[0].status)) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: `Cannot reject locator slip with status '${current.rows[0].status}'`,
          });
        }
        await assertFinalLeaveReviewer(
          client,
          current.rows[0].employee_id,
          reviewerId,
          'locator',
          id
        );
        const workflowAction = await workflowEngine.workflowDecision(
          client,
          'locator',
          id,
          reviewerId,
          'reject',
          req.sharedWorkflowExpected
        );
        await workflowEngine.saveWorkflow(client, 'locator', id, workflowAction?.snapshot);
        await client.query(
          `UPDATE locator_slips
       SET status = 'rejected_by_hr',
           hr_reviewer_id = $2::uuid,
           hr_reviewed_at = now(),
           hr_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
          [id, reviewerId, remarks]
        );
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: id,
          action: req.user.role === 'mayor' ? 'mayor_rejected' : 'hr_rejected',
          fromStatus: current.rows[0].status,
          toStatus: 'rejected_by_hr',
          actorId: reviewerId,
          actorRole: req.user?.role || 'hr',
          remarks,
        });
        await client.query('COMMIT');

        notifySafe(() =>
          locatorNotifications.notifyEmployee(pool, {
            employeeUserId: current.rows[0].employee_id,
            slipId: id,
            type: 'locator_rejected_hr',
            title: 'Locator request not approved',
            body: `${req.user.role === 'mayor' ? 'The Mayor' : 'HR'} did not approve this locator request.${remarks ? ` ${remarks}` : ''}`,
            metadata: { reviewer_remarks: remarks },
          })
        );

        const out = await pool.query(
          `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
          [id]
        );
        const mapped = mapLocatorRow(out.rows[0]);
        broadcastLocatorUpdated('rejected', mapped);
        res.json(mapped);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[locator PATCH /:id/reject]', err);
        if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to reject locator slip' });
      } finally {
        client.release();
      }
    },
  };
};
