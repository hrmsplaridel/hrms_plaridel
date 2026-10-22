'use strict';
module.exports = function createLocatorControllers({
  assertDepartmentApprovalFinalReviewer,
  broadcastLocatorUpdated,
  evaluateLocatorReturnWindow,
  fetchLocatorSlipDetails,
  findLocatorRequestConflicts,
  isDepartmentHead,
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
    approveDepartment: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks = (req.body?.reviewer_remarks || '').toString().trim() || null;

      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const deptInfo = await isDepartmentHead(client, reviewerId);
        const current = await client.query(
          `SELECT ls.id,
              ls.status,
              ls.employee_id,
              ls.slip_date::text AS slip_date,
              ls.request_type,
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
         AND (
           ls.assigned_department_head_id = $2::uuid
           OR EXISTS (
             SELECT 1 FROM locator_slip_department_reviewers lsr
             WHERE lsr.locator_slip_id = ls.id
               AND lsr.reviewer_id = $2::uuid
           )
           OR (
             ls.assigned_department_head_id IS NULL
             AND ls.department_id = $3::uuid
           )
         )
       FOR UPDATE OF ls`,
          [id, reviewerId, deptInfo.departmentId]
        );
        if (current.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Locator slip not found or not assigned to you' });
        }
        if (current.rows[0].status !== 'pending_department_head') {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: `Cannot approve locator slip with status '${current.rows[0].status}'`,
          });
        }
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
          checkLeave: false,
          checkAttendance: false,
        });
        if (!conflictCheck.ok) {
          await client.query('ROLLBACK');
          return res.status(409).json(locatorConflictPayload(conflictCheck));
        }
        const routeRow = (
          await client.query('SELECT final_review_route FROM locator_slips WHERE id=$1::uuid', [id])
        ).rows[0];
        const workflowDecision = await workflowEngine.workflowDecision(
          client,
          'locator',
          id,
          reviewerId,
          'approve',
          req.sharedWorkflowExpected
        );
        const manualMayor = workflowDecision
          ? workflowDecision.status === 'approved'
          : routeRow?.final_review_route === 'mayor';
        if (!workflowDecision && !manualMayor) {
          await assertDepartmentApprovalFinalReviewer(
            client,
            current.rows[0].employee_id,
            reviewerId,
            'locator',
            id
          );
        }
        await persistLocatorSignature(client, req.user, id, 'department_head', req.body?.signature);
        const departmentNextStatus =
          workflowDecision?.status || (manualMayor ? 'approved' : 'pending_hr');
        await client.query(
          `UPDATE locator_slips
       SET status = $4::text,
           dept_head_reviewer_id = $2::uuid,
           dept_head_reviewed_at = now(),
           dept_head_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
          [id, reviewerId, remarks, departmentNextStatus]
        );
        await workflowEngine.saveWorkflow(client, 'locator', id, workflowDecision?.snapshot);
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: id,
          action: 'department_head_approved',
          fromStatus: 'pending_department_head',
          toStatus: departmentNextStatus,
          actorId: reviewerId,
          actorRole: 'department_head',
          remarks,
        });
        await client.query('COMMIT');

        if (manualMayor) {
          const mapped = await fetchLocatorSlipDetails(pool, id);
          notifySafe(() =>
            locatorNotifications.notifyEmployee(pool, {
              slipId: id,
              employeeUserId: current.rows[0].employee_id,
              type: 'locator_approved_department_head',
              title:
                !workflowDecision || workflowDecision.snapshot.manual_signing_required
                  ? 'Locator approved for manual Mayor signing'
                  : 'Locator request approved',
              body:
                !workflowDecision || workflowDecision.snapshot.manual_signing_required
                  ? 'Your department approved the locator. Obtain the Mayor signature on the printed form.'
                  : 'Your department reviewer approved the locator.',
            })
          );
          broadcastLocatorUpdated('department_head_approved', mapped);
          return res.json(mapped);
        }
        notifySafe(() =>
          locatorNotifications.notifyDepartmentHeadApprovedForEmployee(pool, {
            slipId: id,
            employeeUserId: current.rows[0].employee_id,
            slipDate: current.rows[0].slip_date,
            requestType: current.rows[0].request_type,
            metadata: { reviewer_remarks: remarks },
          })
        );
        const mapped = await fetchLocatorSlipDetails(pool, id);
        notifySafe(() =>
          locatorNotifications.notifyDepartmentHeadApprovedForHr(pool, {
            employeeUserId: mapped.employee_id,
            slipId: id,
            employeeName: mapped.employee_name,
            slipDate: mapped.slip_date,
            requestType: mapped.request_type,
          })
        );
        broadcastLocatorUpdated('department_head_approved', mapped);
        res.json(mapped);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[locator PATCH /:id/department-head-approve]', err);
        if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to approve locator slip (department head)' });
      } finally {
        client.release();
      }
    },

    rejectDepartment: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const reasonValidation = normalizeLocatorRejectionReason(
        req.body?.reviewer_remarks || req.body?.reason
      );
      if (!reasonValidation.valid) {
        return res.status(400).json({ error: reasonValidation.error });
      }
      const remarks = reasonValidation.value;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const deptInfo = await isDepartmentHead(client, reviewerId);
        const current = await client.query(
          `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
         AND (
           assigned_department_head_id = $2::uuid
           OR EXISTS (
             SELECT 1 FROM locator_slip_department_reviewers lsr
             WHERE lsr.locator_slip_id = locator_slips.id
               AND lsr.reviewer_id = $2::uuid
           )
           OR (
             assigned_department_head_id IS NULL
             AND department_id = $3::uuid
           )
         )
       FOR UPDATE`,
          [id, reviewerId, deptInfo.departmentId]
        );
        if (current.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Locator slip not found or not assigned to you' });
        }
        if (current.rows[0].status !== 'pending_department_head') {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: `Cannot reject locator slip with status '${current.rows[0].status}'`,
          });
        }
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
       SET status = 'rejected_by_department_head',
           dept_head_reviewer_id = $2::uuid,
           dept_head_reviewed_at = now(),
           dept_head_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
          [id, reviewerId, remarks]
        );
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: id,
          action: 'department_head_rejected',
          fromStatus: 'pending_department_head',
          toStatus: 'rejected_by_department_head',
          actorId: reviewerId,
          actorRole: 'department_head',
          remarks,
        });
        await client.query('COMMIT');
        notifySafe(() =>
          locatorNotifications.notifyEmployee(pool, {
            employeeUserId: current.rows[0].employee_id,
            slipId: id,
            type: 'locator_rejected_department_head',
            title: 'Locator request not approved by department head',
            body: remarks
              ? `Your locator request was not approved. ${remarks}`
              : 'Your locator request was not approved by your department head.',
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
        broadcastLocatorUpdated('department_head_rejected', mapped);
        res.json(mapped);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[locator PATCH /:id/department-head-reject]', err);
        res.status(500).json({ error: 'Failed to reject locator slip (department head)' });
      } finally {
        client.release();
      }
    },

    returnDepartment: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const remarks = (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim();
      if (!remarks) {
        return res.status(400).json({ error: 'Correction remarks are required.' });
      }

      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const deptInfo = await isDepartmentHead(client, reviewerId);
        const current = await client.query(
          `SELECT id, status, employee_id, slip_date::text AS slip_date_text
       FROM locator_slips
       WHERE id = $1::uuid
         AND (
           assigned_department_head_id = $2::uuid
           OR EXISTS (
             SELECT 1 FROM locator_slip_department_reviewers lsr
             WHERE lsr.locator_slip_id = locator_slips.id
               AND lsr.reviewer_id = $2::uuid
           )
           OR (
             assigned_department_head_id IS NULL
             AND department_id = $3::uuid
           )
         )
       FOR UPDATE`,
          [id, reviewerId, deptInfo.departmentId]
        );
        const row = current.rows[0];
        if (!row) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Locator slip not found or not assigned to you' });
        }
        if (row.status !== 'pending_department_head') {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error: `Cannot return locator slip with status '${row.status}'`,
          });
        }
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
           dept_head_reviewer_id = $2::uuid,
           dept_head_reviewed_at = now(),
           dept_head_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
          [id, reviewerId, remarks]
        );
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: id,
          action: 'department_head_returned',
          fromStatus: 'pending_department_head',
          toStatus: 'returned_for_correction',
          actorId: reviewerId,
          actorRole: 'department_head',
          remarks,
        });
        await client.query('COMMIT');

        notifySafe(() =>
          locatorNotifications.notifyEmployee(pool, {
            employeeUserId: row.employee_id,
            slipId: id,
            type: 'locator_returned_department_head',
            title: 'Locator request returned for correction',
            body: `Your department head returned this locator request. ${remarks}`,
            metadata: { reviewer_remarks: remarks, returned_by: 'department_head' },
          })
        );
        const mapped = await fetchLocatorSlipDetails(pool, id);
        broadcastLocatorUpdated('department_head_returned', mapped || row);
        res.json(mapped);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[locator PATCH /:id/department-head-return]', err);
        res.status(500).json({ error: 'Failed to return locator slip for correction' });
      } finally {
        client.release();
      }
    },
  };
};
