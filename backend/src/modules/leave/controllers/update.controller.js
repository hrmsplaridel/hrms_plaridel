'use strict';
module.exports = function createLeaveControllers({
  assertAnnualQuotaLeaveLimit,
  assertLeaveEmploymentEligibility,
  assertLeaveServiceEligibility,
  assertLeaveSubmissionReviewer,
  broadcastLeaveUpdated,
  computeEmployeeLeaveWorkingDays,
  computeNumberOfDaysSync,
  employeeLeaveDetailsFromPayload,
  ensureLeaveTypeIdByName,
  getDepartmentReviewSnapshot,
  getLeaveTypeDefinition,
  getUserSexForLeaveValidation,
  hasOverlappingLeaveRequest,
  insertLeaveRequestHistory,
  invalidProvidedDate,
  leaveNotifications,
  leaveTypeRowToApi,
  loadEmployeeOfficialSnapshot,
  lockEmployeeLeaveFiling,
  mapLeaveRowToApi,
  mustBlockMissingAttachment,
  normalizeEmployeeDetailSchema,
  normalizeEmployeeOfficialSnapshot,
  notifySafe,
  pool,
  readAdoptionParentRole,
  readLeaveEventDates,
  readMaternityDeliveryType,
  replaceRequestReviewerSnapshot,
  reservePendingLeaveBalance,
  serializeEmployeeDetailSchema,
  toIsoDateStr,
  validateEmployeeLeaveRequestWithRule,
  validateEmployeeUpdateTransition,
  workflowEngine,
}) {
  return {
    updateLeave: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      const { id } = req.params;
      try {
        const existing = await pool.query(
          `SELECT id, status, employee_official_snapshot, leave_type_id, workflow_snapshot
       FROM leave_requests
       WHERE id = $1 AND (user_id = $2 OR employee_id = $2)
         AND discarded_at IS NULL`,
          [id, userId],
        );
        if (existing.rows.length === 0)
          return res.status(404).json({ error: 'Leave request not found' });
        const status = existing.rows[0].status;

        const {
          leave_type,
          start_date,
          end_date,
          reason,
          details,
          status: desiredStatus,
          ...rest
        } = req.body || {};
        let nextStatus;
        let historyAction;
        try {
          ({ nextStatus, historyAction } = validateEmployeeUpdateTransition({
            currentStatus: status,
            desiredStatus,
          }));
        } catch (err) {
          return res.status(err.statusCode || 400).json({ error: err.message });
        }
        const startStr = toIsoDateStr(start_date);
        const endStr = toIsoDateStr(end_date);
        if (invalidProvidedDate(start_date, startStr)) {
          return res.status(400).json({ error: 'start_date must be a valid date' });
        }
        if (invalidProvidedDate(end_date, endStr)) {
          return res.status(400).json({ error: 'end_date must be a valid date' });
        }
        if (startStr && endStr && endStr < startStr) {
          return res.status(400).json({ error: 'end_date cannot be earlier than start_date' });
        }
        const days = computeNumberOfDaysSync(startStr, endStr);
        let effectiveDays = days;
        let refreshReviewSnapshot = false;
        let reviewSnapshot = null;
        let preparedWorkflow = null;

        const client = await pool.connect();
        try {
          await client.query('BEGIN');
          await lockEmployeeLeaveFiling(client, userId);
          // Serialize edits/submissions of this request before any write or reservation.
          const lockedRequest = await client.query(
            `SELECT id, status, employee_official_snapshot, leave_type_id, workflow_snapshot
         FROM leave_requests
         WHERE id = $1 AND (user_id = $2 OR employee_id = $2)
           AND discarded_at IS NULL
         FOR UPDATE`,
            [id, userId],
          );
          if (!lockedRequest.rows.length) {
            await client.query('ROLLBACK');
            return res.status(404).json({ error: 'Leave request not found' });
          }
          if (lockedRequest.rows[0].status !== status) {
            await client.query('ROLLBACK');
            return res.status(409).json({
              error: 'This leave request has changed. Refresh before saving or submitting again.',
            });
          }
          // Use the row read under lock for both the transition and filing snapshot.
          existing.rows[0] = lockedRequest.rows[0];
          ({ nextStatus, historyAction } = validateEmployeeUpdateTransition({
            currentStatus: lockedRequest.rows[0].status,
            desiredStatus,
          }));
          const savingDraft = nextStatus === 'draft';
          const submitting = [
            'pending',
            'pending_department_head',
            'pending_hr',
            'pending_mayor',
          ].includes(nextStatus);
          if (submitting && (!leave_type || !startStr || !endStr)) {
            await client.query('ROLLBACK');
            return res.status(400).json({
              error: 'Leave type, start date, and end date are required before submission.',
            });
          }
          const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
          // FIX #1: isNotEmpty is Dart/Swift, not JS. Use .length > 0 instead.
          if (leave_type != null && String(leave_type).trim().length > 0 && !leaveTypeId) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: 'Invalid leave type' });
          }
          const storedTypeRule =
            !leave_type && lockedRequest.rows[0].leave_type_id
              ? await client.query('SELECT * FROM leave_types WHERE id = $1::uuid', [
                  lockedRequest.rows[0].leave_type_id,
                ])
              : null;
          const leaveRule = leave_type
            ? await getLeaveTypeDefinition(client, leave_type)
            : storedTypeRule?.rows[0]
              ? leaveTypeRowToApi(storedTypeRule.rows[0])
              : null;
          await assertLeaveEmploymentEligibility(client, leaveRule, userId);
          if (!savingDraft)
            await assertLeaveServiceEligibility(client, leaveRule, userId, startStr);
          if (leaveRule && lockedRequest.rows[0].leave_type_id === leaveTypeId)
            leaveRule.approval_workflow_snapshot = lockedRequest.rows[0].workflow_snapshot;
          if (submitting) {
            reviewSnapshot = await getDepartmentReviewSnapshot(client, userId);
            preparedWorkflow = await workflowEngine.prepareWorkflow(
              client,
              'leave',
              leaveRule,
              userId,
              reviewSnapshot,
            );
            await assertLeaveSubmissionReviewer(client, userId, 'leave', leaveRule, reviewSnapshot);
          }
          const customFieldSchema = normalizeEmployeeDetailSchema(
            leaveRule?.employee_detail_schema,
          );
          const payloadDetails = employeeLeaveDetailsFromPayload({
            details,
            rest,
            customFieldSchema,
            requireCustomFields: !savingDraft,
          });
          const officialSnapshot = await loadEmployeeOfficialSnapshot(client, userId);
          const existingOfficialSnapshot = normalizeEmployeeOfficialSnapshot(
            existing.rows[0].employee_official_snapshot,
          );
          if (existingOfficialSnapshot.date_filed) {
            officialSnapshot.date_filed = existingOfficialSnapshot.date_filed;
          }
          const otherPurpose = (
            payloadDetails.other_purpose ||
            payloadDetails.otherPurpose ||
            ''
          ).toString();
          const maternityDeliveryType = readMaternityDeliveryType(payloadDetails);
          const adoptionParentRole = readAdoptionParentRole(payloadDetails);
          const eventDates = readLeaveEventDates(payloadDetails);
          if (startStr && endStr) {
            const workingDayResult = await computeEmployeeLeaveWorkingDays(
              client,
              userId,
              startStr,
              endStr,
            );
            effectiveDays = workingDayResult.days ?? days;

            // Validate the server-computed, holiday-aware working day count.
            if (!savingDraft && (effectiveDays == null || effectiveDays <= 0)) {
              await client.query('ROLLBACK');
              return res
                .status(400)
                .json({ error: 'Number of working days must be greater than 0.' });
            }
          }

          if (leave_type) {
            const userSex = await getUserSexForLeaveValidation(client, userId);
            const validation = validateEmployeeLeaveRequestWithRule({
              rule: leaveRule,
              leaveType: leave_type,
              otherPurpose: otherPurpose || null,
              startDateStr: savingDraft ? null : startStr,
              endDateStr: savingDraft ? null : endStr,
              numberOfDays: savingDraft ? null : effectiveDays,
              hasAttachment: false,
              userSex,
              maternityDeliveryType,
              adoptionParentRole,
              eventDates,
              details: payloadDetails,
              enforceEventDateRules: submitting,
            });
            if (!validation.valid) {
              await client.query('ROLLBACK');
              return res.status(400).json({ error: validation.error });
            }

            // FIX #6 (backend): When transitioning to a pending status via PUT, check attachment.
            if (submitting) {
              const existingRow = await client.query(
                'SELECT attachment_path FROM leave_requests WHERE id = $1',
                [id],
              );
              const hasAttachment = !!existingRow.rows[0]?.attachment_path;
              if (mustBlockMissingAttachment(leaveRule, leave_type, effectiveDays, hasAttachment)) {
                await client.query('ROLLBACK');
                return res.status(400).json({
                  error: `${leave_type} requires a supporting document before submission. Please upload one first.`,
                });
              }

              // Two-stage workflow: resolve actual target status.
              if (!preparedWorkflow && leaveRule?.approval_route === 'mayor') {
                const emp = (
                  await client.query('SELECT employment_type FROM users WHERE id=$1', [userId])
                ).rows[0]?.employment_type;
                if (
                  require('../../../services/leaveRouting').chooseLeaveRoute(leaveRule, emp) ===
                    'mayor' &&
                  !reviewSnapshot?.departmentHeadUserId
                ) {
                  const error = new Error(
                    'Configure a different department reviewer before submitting a Mayor-routed leave request.',
                  );
                  error.statusCode = 409;
                  throw error;
                }
              }
              refreshReviewSnapshot = true;
              nextStatus = preparedWorkflow
                ? workflowEngine.workflowStatus(preparedWorkflow)
                : reviewSnapshot?.departmentHeadUserId
                  ? 'pending_department_head'
                  : 'pending_hr';
              await workflowEngine.initialWorkflow(client, 'leave', id, preparedWorkflow);
            }
          }
          // Prevent overlapping ranges when dates are being set/changed.
          if (!savingDraft && startStr && endStr) {
            const hasOverlap = await hasOverlappingLeaveRequest(
              client,
              userId,
              startStr,
              endStr,
              id,
            );
            if (hasOverlap) {
              await client.query('ROLLBACK');
              return res.status(400).json({ error: 'Overlapping leave request exists' });
            }
          }

          if (
            (nextStatus === 'pending' ||
              nextStatus === 'pending_department_head' ||
              nextStatus === 'pending_hr' ||
              nextStatus === 'pending_mayor') &&
            leave_type &&
            startStr &&
            endStr
          ) {
            await assertAnnualQuotaLeaveLimit(client, {
              userId,
              leaveTypeName: String(leave_type),
              startStr,
              endStr,
              excludeId: id,
            });
          }

          const q = await client.query(
            `UPDATE leave_requests
         SET leave_type_id = COALESCE($1::uuid, leave_type_id),
             start_date = CASE WHEN $15::boolean THEN $2::date ELSE COALESCE($2::date, start_date) END,
             end_date = CASE WHEN $15::boolean THEN $3::date ELSE COALESCE($3::date, end_date) END,
             total_days = CASE WHEN $15::boolean THEN $4::numeric ELSE COALESCE($4::numeric, total_days) END,
             number_of_days = CASE WHEN $15::boolean THEN $4::numeric ELSE COALESCE($4::numeric, number_of_days) END,
             reason = $5::text,
              details = COALESCE($6::jsonb, details),
              status = $9::text,
              review_department_id = CASE
                WHEN $10::boolean THEN $11::uuid
                ELSE review_department_id
              END,
              assigned_department_head_id = CASE
                WHEN $10::boolean THEN $12::uuid
                ELSE assigned_department_head_id
              END,
              employee_official_snapshot = $13::jsonb,
              employee_detail_schema_snapshot = $14::jsonb,
              updated_at = now()
         WHERE id = $7 AND (user_id = $8 OR employee_id = $8)
         RETURNING *`,
            [
              leaveTypeId,
              startStr,
              endStr,
              effectiveDays,
              reason || null,
              payloadDetails,
              id,
              userId,
              nextStatus,
              refreshReviewSnapshot,
              reviewSnapshot?.departmentId || null,
              preparedWorkflow && !preparedWorkflow.steps.includes('department')
                ? null
                : reviewSnapshot?.departmentHeadUserId || null,
              officialSnapshot,
              serializeEmployeeDetailSchema(customFieldSchema),
              savingDraft,
            ],
          );
          const row = q.rows[0];
          if (refreshReviewSnapshot) {
            await replaceRequestReviewerSnapshot(client, {
              requestType: 'leave',
              requestId: row.id,
              departmentId: reviewSnapshot?.departmentId || null,
              reviewers:
                preparedWorkflow && !preparedWorkflow.steps.includes('department')
                  ? []
                  : reviewSnapshot?.reviewers || [],
            });
          }
          await insertLeaveRequestHistory(client, {
            leaveRequestId: row.id,
            action: historyAction,
            fromStatus: status,
            toStatus: nextStatus,
            actedBy: userId,
            remarks: reason || null,
            metadataJson: {
              revision: row.signature_revision,
              leave_type: leave_type || null,
              start_date: startStr,
              end_date: endStr,
              number_of_days: effectiveDays,
              review_department_id: refreshReviewSnapshot
                ? reviewSnapshot?.departmentId || null
                : row.review_department_id || null,
              department_head: refreshReviewSnapshot
                ? reviewSnapshot?.departmentHeadUserId || null
                : row.assigned_department_head_id || null,
            },
          });
          // FIX #5b: Update pending_days when status transitions to a pending status via PUT.
          const leaveTypeName = leave_type ? String(leave_type) : null;
          const isPendingTarget =
            nextStatus === 'pending' ||
            nextStatus === 'pending_department_head' ||
            nextStatus === 'pending_hr' ||
            nextStatus === 'pending_mayor';
          const wasPending =
            status === 'pending' ||
            status === 'pending_department_head' ||
            status === 'pending_hr' ||
            status === 'pending_mayor';
          if (leaveTypeName && effectiveDays != null && effectiveDays > 0) {
            if (isPendingTarget && !wasPending) {
              // Moving INTO a pending status: increment pending_days.
              const putAction =
                historyAction === 'resubmitted' ? 'leave_resubmitted' : 'leave_submitted';
              const reservation = await reservePendingLeaveBalance(client, {
                userId,
                leaveTypeName,
                days: effectiveDays,
                leaveRequestId: row.id,
                actorUserId: userId,
                actorKind: 'user',
                action: putAction,
                metadataJson: { number_of_days: effectiveDays, history_action: historyAction },
              });
              row.reserved_credit_days = reservation?.reservedDays ?? null;
            }
          }
          if (submitting) {
            await require('../../../services/docutrackerLeaveSignatureService').confirmSubmittedApplicantSignature(
              client,
              req.user,
              row.id,
              req.body?.applicant_signature_asset_id,
            );
          }
          await client.query('COMMIT');
          if (
            (historyAction === 'submitted' || historyAction === 'resubmitted') &&
            ['pending', 'pending_department_head', 'pending_hr', 'pending_mayor'].includes(
              row.status,
            )
          ) {
            const namePut = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
            const putEmpName = namePut.rows[0]?.full_name || 'Employee';
            notifySafe(() =>
              leaveNotifications.notifyAfterSubmit(pool, {
                leaveRequestId: row.id,
                status: row.status,
                employeeUserId: userId,
                employeeName: putEmpName,
                leaveTypeName: leaveTypeName,
                startDateStr: startStr,
                endDateStr: endStr,
                departmentHeadUserId:
                  row.status === 'pending_department_head'
                    ? row.assigned_department_head_id || null
                    : null,
                departmentReviewerUserIds:
                  row.status === 'pending_department_head'
                    ? reviewSnapshot?.reviewerUserIds || []
                    : [],
              }),
            );
          }
          const mapped = mapLeaveRowToApi({ ...row, leave_type_name: leaveTypeName });
          broadcastLeaveUpdated(historyAction || 'updated', mapped);
          res.json(mapped);
        } catch (e) {
          await client.query('ROLLBACK');
          throw e;
        } finally {
          client.release();
        }
      } catch (err) {
        console.error('[leave PUT /:id]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to update leave request' });
      }
    },
  };
};
