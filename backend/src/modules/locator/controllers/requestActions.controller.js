'use strict';
module.exports = function createLocatorControllers({
  assertLeaveSubmissionReviewer,
  broadcastLocatorUpdated,
  captureLocatorTypeSnapshot,
  evaluateEmployeeLocatorDateWindow,
  evaluateLocatorEmployeeCorrectionWindow,
  fetchLocatorSlipDetails,
  findLocatorRequestConflicts,
  getDepartmentReviewSnapshotForDate,
  getLocatorTypeByCode,
  locatorAttachmentFileExists,
  locatorConflictPayload,
  locatorCorrectionChanges,
  locatorDetailValues,
  locatorNotifications,
  mapLocatorRow,
  normalizeLocatorCorrection,
  normalizeLocatorFieldSchema,
  notifySafe,
  parseLocatorDateOnly,
  persistLocatorSignature,
  pool,
  recordLocatorWorkflowEvent,
  resolveLocatorRouting,
  snapshotLocatorReviewers,
  validateLocatorAttachmentForReview,
  validateLocatorRequiredFields,
  validateLocatorWorkingDayForEmployee,
  workflowEngine,
}) {
  return {
    cancelRequest: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT id, status
       FROM locator_slips
       WHERE id = $1::uuid AND employee_id = $2::uuid
       FOR UPDATE`,
          [id, userId]
        );
        if (current.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Locator slip not found' });
        }
        const status = current.rows[0].status;
        if (
          ![
            'pending',
            'pending_department_head',
            'pending_hr',
            'pending_mayor',
            'returned_for_correction',
          ].includes(status)
        ) {
          await client.query('ROLLBACK');
          return res
            .status(400)
            .json({ error: `Cannot cancel locator slip with status '${status}'` });
        }
        await client.query(
          `UPDATE locator_slips
       SET status = 'cancelled', updated_at = now()
       WHERE id = $1::uuid`,
          [id]
        );
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: id,
          action: 'cancelled',
          fromStatus: status,
          toStatus: 'cancelled',
          actorId: userId,
          actorRole: 'employee',
        });
        await client.query('COMMIT');
        const out = await pool.query(
          `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              corrector.full_name AS retroactive_corrector_name,
              revoker.full_name AS revoked_by_name,
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
       LEFT JOIN users corrector ON corrector.id = ls.retroactive_corrected_by
       LEFT JOIN users revoker ON revoker.id = ls.revoked_by
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
          [id]
        );
        const mapped = mapLocatorRow(out.rows[0]);
        broadcastLocatorUpdated('cancelled', mapped, { previousStatus: status });
        res.json(mapped);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[locator PATCH /:id/cancel]', err);
        res.status(500).json({ error: 'Failed to cancel locator slip' });
      } finally {
        client.release();
      }
    },

    resubmitRequest: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              lrt.requires_attachment AS request_type_requires_attachment
       FROM locator_slips ls
       JOIN users u ON u.id = ls.employee_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid
         AND ls.employee_id = $2::uuid
       FOR UPDATE OF ls`,
          [id, userId]
        );
        const row = current.rows[0];
        if (!row) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Locator slip not found' });
        }
        if (row.status !== 'returned_for_correction') {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error: `Cannot resubmit locator slip with status '${row.status}'`,
          });
        }
        const correctionWindow = evaluateLocatorEmployeeCorrectionWindow({
          slipDate: row.slip_date_text,
        });
        if (!correctionWindow.ok) {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error: correctionWindow.error,
            code: correctionWindow.code,
          });
        }

        const correction = normalizeLocatorCorrection(row, req.body || {});
        const fieldValidation = validateLocatorRequiredFields({
          slipDate: correction.slipDate,
          requestType: correction.requestType,
          office: correction.office,
          reason: correction.reason,
          slots: correction,
        });
        if (!fieldValidation.valid) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: fieldValidation.error });
        }
        const locatorType = await getLocatorTypeByCode(client, correction.requestType, {
          activeOnly: true,
        });
        if (!locatorType) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: 'Invalid request_type' });
        }
        const attachmentError = validateLocatorAttachmentForReview({
          locatorType,
          attachmentPath: row.attachment_path,
          attachmentFileExists: locatorAttachmentFileExists(row.attachment_path),
        });
        if (attachmentError) {
          await client.query('ROLLBACK');
          return res.status(409).json({ error: attachmentError });
        }
        const resubmitWindow = evaluateEmployeeLocatorDateWindow({
          slipDate: correction.slipDate,
        });
        if (!resubmitWindow.ok) {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error: resubmitWindow.error,
            code: resubmitWindow.code,
          });
        }
        const workingDayCheck = await validateLocatorWorkingDayForEmployee(
          client,
          userId,
          parseLocatorDateOnly(correction.slipDate),
          correction
        );
        if (!workingDayCheck.ok) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: workingDayCheck.error });
        }
        const conflictCheck = await findLocatorRequestConflicts(client, {
          employeeId: userId,
          slipDate: correction.slipDate,
          slots: correction,
          excludeSlipId: id,
          phase: 'submission',
        });
        if (!conflictCheck.ok) {
          await client.query('ROLLBACK');
          return res.status(409).json(locatorConflictPayload(conflictCheck));
        }

        const reviewSnapshot = await getDepartmentReviewSnapshotForDate(
          client,
          userId,
          correction.slipDate
        );
        if (row.request_type === correction.requestType)
          locatorType.approval_workflow_snapshot = row.workflow_snapshot;
        const routing = await resolveLocatorRouting(
          client,
          userId,
          locatorType,
          reviewSnapshot?.departmentHeadUserId,
          reviewSnapshot
        );
        if (!routing.workflow && routing.route === 'hr')
          await assertLeaveSubmissionReviewer(client, userId, 'locator', null, reviewSnapshot);
        const departmentHeadUserId = (
          routing.workflow
            ? !routing.workflow.steps.includes('department')
            : routing.route === 'mayor_direct'
        )
          ? null
          : reviewSnapshot?.departmentHeadUserId || null;
        const submitStatus = routing.status;
        const typeSnapshot = captureLocatorTypeSnapshot(locatorType);
        const changes = locatorCorrectionChanges(row, correction);

        const detailSchema = normalizeLocatorFieldSchema(locatorType.employee_detail_schema);
        const detailValues = locatorDetailValues(
          req.body.additional_details ?? row.additional_details,
          detailSchema
        );

        await client.query(
          `UPDATE locator_slips
       SET slip_date = $2::date,
           request_type = $3::text,
           office = $4::text,
           reason = $5::text,
           am_in = $6::boolean,
           am_out = $7::boolean,
           pm_in = $8::boolean,
           pm_out = $9::boolean,
           request_type_label_snapshot = $10::text,
           request_type_short_label_snapshot = $11::text,
           request_type_location_label_snapshot = $12::text,
           request_type_location_hint_snapshot = $13::text,
           request_type_dtr_slot_label_snapshot = $14::text,
           request_type_dtr_print_label_snapshot = $15::text,
           request_type_requires_attachment_snapshot = $16::boolean,
           request_type_coverage_mode_snapshot = $17::text,
           request_type_snapshot_at = now(),
           status = $18::text,
           department_id = $19::uuid,
           assigned_department_head_id = $20::uuid,
           final_review_route = $21::text,
           final_reviewer_user_id = $22::uuid,
           employee_detail_schema_snapshot = $23::jsonb,
           additional_details = $24::jsonb,
           dept_head_reviewer_id = NULL,
           dept_head_reviewed_at = NULL,
           dept_head_remarks = NULL,
           hr_reviewer_id = NULL,
           hr_reviewed_at = NULL,
           hr_remarks = NULL,
           updated_at = now()
       WHERE id = $1::uuid`,
          [
            id,
            correction.slipDate,
            correction.requestType,
            correction.office,
            correction.reason,
            correction.amIn,
            correction.amOut,
            correction.pmIn,
            correction.pmOut,
            typeSnapshot.label,
            typeSnapshot.shortLabel,
            typeSnapshot.locationLabel,
            typeSnapshot.locationHint,
            typeSnapshot.dtrSlotLabel,
            typeSnapshot.dtrPrintLabel,
            typeSnapshot.requiresAttachment,
            typeSnapshot.coverageMode,
            submitStatus,
            reviewSnapshot?.departmentId || null,
            departmentHeadUserId,
            routing.route,
            routing.mayorId,
            JSON.stringify(detailSchema),
            JSON.stringify(detailValues),
          ]
        );
        await workflowEngine.initialWorkflow(client, 'locator', id, routing.workflow);
        await snapshotLocatorReviewers(client, {
          requestType: 'locator',
          requestId: id,
          departmentId: reviewSnapshot?.departmentId || null,
          reviewers: routing.workflow
            ? routing.workflow.steps.includes('department')
              ? reviewSnapshot?.reviewers || []
              : []
            : routing.route === 'mayor_direct'
              ? []
              : reviewSnapshot?.reviewers || [],
        });
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: id,
          action: 'resubmitted',
          fromStatus: 'returned_for_correction',
          toStatus: submitStatus,
          actorId: userId,
          actorRole: 'employee',
          metadata: { changes },
        });
        await persistLocatorSignature(client, req.user, id, 'applicant', req.body?.signature, {
          requireInput: true,
        });
        await client.query('COMMIT');

        notifySafe(() =>
          locatorNotifications.notifyAfterSubmit(pool, {
            slipId: id,
            status: submitStatus,
            employeeUserId: userId,
            employeeName: row.employee_name,
            slipDate: correction.slipDate,
            amIn: correction.amIn,
            amOut: correction.amOut,
            pmIn: correction.pmIn,
            pmOut: correction.pmOut,
            requestType: correction.requestType,
            departmentHeadUserId,
            departmentReviewerUserIds: reviewSnapshot?.reviewerUserIds || [],
          })
        );

        const mapped = await fetchLocatorSlipDetails(pool, id);
        broadcastLocatorUpdated('resubmitted', mapped || row, { status: submitStatus });
        res.json(mapped);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[locator PATCH /:id/resubmit]', err);
        if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to resubmit locator slip' });
      } finally {
        client.release();
      }
    },
  };
};
