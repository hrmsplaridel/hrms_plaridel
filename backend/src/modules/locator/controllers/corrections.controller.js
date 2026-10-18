'use strict';
module.exports = function createLocatorControllers({
  LOCATOR_ATTACHMENT_SUBDIR,
  boolField,
  broadcastLocatorUpdated,
  captureLocatorTypeSnapshot,
  evaluateEmployeeLocatorDateWindow,
  fetchLocatorSlipDetails,
  findLocatorRequestConflicts,
  getDepartmentReviewSnapshotForDate,
  getLocatorTypeByCode,
  locatorAttachmentRequiredError,
  locatorConflictPayload,
  locatorDetailValues,
  locatorNotifications,
  mapLocatorRow,
  normalizeCorrectionReason,
  normalizeLocatorFieldSchema,
  normalizeRequestType,
  notifySafe,
  parseLocatorDateOnly,
  pool,
  recordLocatorWorkflowEvent,
  removeLocatorAttachmentFile,
  validateLocatorRequiredFields,
  validateLocatorWorkingDayForEmployee,
}) {
  return {
    recordCorrection: async (req, res) => {
      const reviewerId = req.user?.id;
      const employeeId = String(req.body?.employee_id || '').trim();
      const slipDate = String(req.body?.slip_date || '').trim();
      const office = String(req.body?.office || '').trim();
      const reason = String(req.body?.reason || '').trim();
      const requestType = normalizeRequestType(req.body?.request_type);
      const amIn = boolField(req.body?.am_in);
      const amOut = boolField(req.body?.am_out);
      const pmIn = boolField(req.body?.pm_in);
      const pmOut = boolField(req.body?.pm_out);
      const correctionReason = normalizeCorrectionReason(req.body?.retroactive_correction_reason);
      const relPath = req.file ? `${LOCATOR_ATTACHMENT_SUBDIR}/${req.file.filename}` : null;
      const cleanup = () => {
        if (relPath) removeLocatorAttachmentFile(relPath);
      };

      if (!reviewerId) {
        cleanup();
        return res.status(401).json({ error: 'Not authenticated' });
      }
      const fields = validateLocatorRequiredFields({
        slipDate,
        requestType,
        office,
        reason,
        slots: { amIn, amOut, pmIn, pmOut },
      });
      if (!employeeId || !fields.valid) {
        cleanup();
        return res.status(400).json({
          error: !employeeId ? 'employee_id is required' : fields.error,
        });
      }
      if (!correctionReason) {
        cleanup();
        return res.status(400).json({
          error: 'A correction reason between 10 and 1000 characters is required.',
          code: 'locator_correction_reason_required',
        });
      }
      const employeeDateWindow = evaluateEmployeeLocatorDateWindow({ slipDate });
      if (employeeDateWindow.ok) {
        cleanup();
        return res.status(409).json({
          error:
            'Today and future locator dates must use the normal employee filing and approval workflow.',
          code: 'locator_correction_not_needed',
        });
      }
      if (employeeDateWindow.code !== 'locator_past_date_not_allowed') {
        cleanup();
        return res.status(400).json({
          error: employeeDateWindow.error,
          code: employeeDateWindow.code,
        });
      }

      let client = null;
      let committed = false;
      try {
        client = await pool.connect();
        await client.query('BEGIN');
        const employee = await client.query(
          `SELECT id, full_name FROM users WHERE id = $1::uuid LIMIT 1`,
          [employeeId]
        );
        if (!employee.rows[0]) {
          await client.query('ROLLBACK');
          cleanup();
          return res.status(404).json({ error: 'Employee not found' });
        }
        const workingDay = await validateLocatorWorkingDayForEmployee(
          client,
          employeeId,
          parseLocatorDateOnly(slipDate),
          { amIn, amOut, pmIn, pmOut }
        );
        if (!workingDay.ok) {
          await client.query('ROLLBACK');
          cleanup();
          return res.status(400).json({ error: workingDay.error });
        }
        const locatorType = await getLocatorTypeByCode(client, requestType, {
          activeOnly: true,
        });
        if (!locatorType) {
          await client.query('ROLLBACK');
          cleanup();
          return res.status(400).json({ error: 'Invalid request_type' });
        }
        const typeSnapshot = captureLocatorTypeSnapshot(locatorType);
        const detailSchema = normalizeLocatorFieldSchema(locatorType.employee_detail_schema);
        const detailValues = locatorDetailValues(req.body.additional_details, detailSchema);
        const attachmentError = locatorAttachmentRequiredError(locatorType, Boolean(relPath));
        if (attachmentError) {
          await client.query('ROLLBACK');
          cleanup();
          return res.status(400).json({ error: attachmentError });
        }
        const conflictCheck = await findLocatorRequestConflicts(client, {
          employeeId,
          slipDate,
          slots: { amIn, amOut, pmIn, pmOut },
          phase: 'approval',
        });
        if (!conflictCheck.ok) {
          await client.query('ROLLBACK');
          cleanup();
          return res.status(409).json(locatorConflictPayload(conflictCheck));
        }
        const snapshot = await getDepartmentReviewSnapshotForDate(client, employeeId, slipDate);
        const inserted = await client.query(
          `INSERT INTO locator_slips (
           employee_id, department_id, assigned_department_head_id,
           slip_date, am_in, am_out, pm_in, pm_out, request_type, office, reason,
           request_type_label_snapshot, request_type_short_label_snapshot,
           request_type_location_label_snapshot, request_type_location_hint_snapshot,
           request_type_dtr_slot_label_snapshot, request_type_dtr_print_label_snapshot,
           request_type_requires_attachment_snapshot,
           request_type_coverage_mode_snapshot, request_type_snapshot_at,
           attachment_name, attachment_path, attachment_mime_type,
           attachment_uploaded_at, status, hr_reviewer_id, hr_reviewed_at,
           hr_remarks, is_retroactive_correction,
           retroactive_correction_reason, retroactive_corrected_by,
           retroactive_corrected_at, created_at, updated_at,
           employee_detail_schema_snapshot, additional_details
         ) VALUES (
           $1::uuid, $2::uuid, $3::uuid,
           $4::date, $5::boolean, $6::boolean, $7::boolean, $8::boolean,
           $9::text, $10::text, $11::text,
           $17::text, $18::text, $19::text, $20::text,
           $21::text, $22::text, $23::boolean, $24::text, now(),
           $12::text, $13::text, $14::text,
           CASE WHEN $13::text IS NULL THEN NULL ELSE now() END,
           'approved', $15::uuid, now(), $16::text, true,
           $16::text, $15::uuid, now(), now(), now(), $25::jsonb, $26::jsonb
         ) RETURNING *`,
          [
            employeeId,
            snapshot?.departmentId || null,
            snapshot?.departmentHeadUserId || null,
            slipDate,
            amIn,
            amOut,
            pmIn,
            pmOut,
            requestType,
            office,
            reason,
            relPath ? req.file.originalname || 'attachment' : null,
            relPath,
            relPath ? req.file.mimetype || null : null,
            reviewerId,
            correctionReason,
            typeSnapshot.label,
            typeSnapshot.shortLabel,
            typeSnapshot.locationLabel,
            typeSnapshot.locationHint,
            typeSnapshot.dtrSlotLabel,
            typeSnapshot.dtrPrintLabel,
            typeSnapshot.requiresAttachment,
            typeSnapshot.coverageMode,
            JSON.stringify(detailSchema),
            JSON.stringify(detailValues),
          ]
        );
        await recordLocatorWorkflowEvent(client, {
          locatorSlipId: inserted.rows[0].id,
          action: 'retroactive_correction_recorded',
          fromStatus: null,
          toStatus: 'approved',
          actorId: reviewerId,
          actorRole: req.user?.role || 'hr',
          remarks: correctionReason,
          metadata: { retroactive_correction: true },
        });
        await client.query('COMMIT');
        committed = true;

        const insertedRow = inserted.rows[0];
        let mapped = mapLocatorRow({
          ...insertedRow,
          slip_date_text: slipDate,
          employee_name: employee.rows[0].full_name,
          department_name: snapshot?.departmentName || null,
        });
        try {
          mapped = (await fetchLocatorSlipDetails(pool, insertedRow.id)) || mapped;
        } catch (detailsError) {
          console.error('[locator POST /admin/corrections details]', detailsError);
        }
        notifySafe(() =>
          locatorNotifications.notifyEmployee(pool, {
            employeeUserId: employeeId,
            slipId: insertedRow.id,
            type: 'locator_retroactive_correction_recorded',
            title: 'Locator correction recorded',
            body: `HR recorded a locator correction for ${slipDate}.`,
            metadata: { correction_reason: correctionReason },
          })
        );
        broadcastLocatorUpdated('retroactive_correction_recorded', mapped);
        return res.status(201).json(mapped);
      } catch (err) {
        if (client && !committed) {
          try {
            await client.query('ROLLBACK');
          } catch (_) {}
        }
        if (!committed) cleanup();
        console.error('[locator POST /admin/corrections]', err);
        if (err.statusCode === 400) return res.status(400).json({ error: err.message });
        return res.status(500).json({ error: 'Failed to record locator correction' });
      } finally {
        client?.release();
      }
    },
  };
};
