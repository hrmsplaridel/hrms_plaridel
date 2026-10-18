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
  leaveNotifications,
  loadEmployeeOfficialSnapshot,
  lockEmployeeLeaveFiling,
  mapLeaveRowToApi,
  mustBlockMissingAttachment,
  normalizeEmployeeDetailSchema,
  notifySafe,
  pool,
  readAdoptionParentRole,
  readLeaveEventDates,
  readMaternityDeliveryType,
  replaceRequestReviewerSnapshot,
  requiredLeaveDateRangeError,
  reservePendingLeaveBalance,
  serializeEmployeeDetailSchema,
  toIsoDateStr,
  validateEmployeeLeaveRequestWithRule,
  workflowEngine,
}) {
  return {
    submitLeave: async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      try {
        const { leave_type, start_date, end_date, reason, details, ...rest } = req.body || {};

        const dateError = requiredLeaveDateRangeError(start_date, end_date);
        if (dateError) return res.status(400).json({ error: dateError });
        const startStr = toIsoDateStr(start_date);
        const endStr = toIsoDateStr(end_date);
        const days = computeNumberOfDaysSync(startStr, endStr); // holiday-aware recomputed inside tx

        const client = await pool.connect();
        try {
          await client.query('BEGIN');
          await lockEmployeeLeaveFiling(client, userId);
          const workingDayResult = await computeEmployeeLeaveWorkingDays(
            client,
            userId,
            startStr,
            endStr,
          );
          const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
          if (!leaveTypeId) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: 'Invalid leave type' });
          }
          const leaveRule = await getLeaveTypeDefinition(client, leave_type);
          await assertLeaveEmploymentEligibility(client, leaveRule, userId);
          await assertLeaveServiceEligibility(client, leaveRule, userId, startStr);
          const reviewSnapshot = await getDepartmentReviewSnapshot(client, userId);
          const preparedWorkflow = await workflowEngine.prepareWorkflow(
            client,
            'leave',
            leaveRule,
            userId,
            reviewSnapshot,
          );
          await assertLeaveSubmissionReviewer(client, userId, 'leave', leaveRule, reviewSnapshot);
          const customFieldSchema = normalizeEmployeeDetailSchema(
            leaveRule?.employee_detail_schema,
          );
          const payloadDetails = employeeLeaveDetailsFromPayload({
            details,
            rest,
            customFieldSchema,
          });
          const officialSnapshot = await loadEmployeeOfficialSnapshot(client, userId);
          const otherPurpose = (
            payloadDetails.other_purpose ||
            payloadDetails.otherPurpose ||
            ''
          ).toString();
          const maternityDeliveryType = readMaternityDeliveryType(payloadDetails);
          const adoptionParentRole = readAdoptionParentRole(payloadDetails);
          const eventDates = readLeaveEventDates(payloadDetails);

          // Validate the server-computed, holiday-aware working day count.
          const effectiveDaysSubmit = workingDayResult.days ?? days;
          if (effectiveDaysSubmit == null || effectiveDaysSubmit <= 0) {
            await client.query('ROLLBACK');
            return res
              .status(400)
              .json({ error: 'Number of working days must be greater than 0.' });
          }

          const userSex = await getUserSexForLeaveValidation(client, userId);
          const validation = validateEmployeeLeaveRequestWithRule({
            rule: leaveRule,
            leaveType: leave_type,
            otherPurpose: otherPurpose || null,
            startDateStr: startStr,
            endDateStr: endStr,
            numberOfDays: effectiveDaysSubmit,
            hasAttachment: false,
            userSex,
            maternityDeliveryType,
            adoptionParentRole,
            eventDates,
            details: payloadDetails,
            enforceEventDateRules: true,
          });
          if (!validation.valid) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: validation.error });
          }

          // FIX #6 (backend): POST /submit creates a new record — no attachment yet.
          // Block when a required attachment is missing (incl. sick leave ≥5 working days → medical certificate).
          if (mustBlockMissingAttachment(leaveRule, leave_type, effectiveDaysSubmit, false)) {
            await client.query('ROLLBACK');
            return res.status(400).json({
              error: `${leave_type} requires a supporting document. Please save a draft, upload the document, then submit.`,
            });
          }

          const hasOverlap = await hasOverlappingLeaveRequest(
            client,
            userId,
            startStr,
            endStr,
            null,
          );
          if (hasOverlap) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: 'Overlapping leave request exists' });
          }

          await assertAnnualQuotaLeaveLimit(client, {
            userId,
            leaveTypeName: String(leave_type),
            startStr,
            endStr,
          });

          const q = await client.query(
            `INSERT INTO leave_requests (
            employee_id,
            user_id,
            leave_type_id,
            start_date,
            end_date,
            total_days,
            number_of_days,
            reason,
            details,
            employee_official_snapshot,
            employee_detail_schema_snapshot,
            status,
            created_at,
            updated_at
          )
          VALUES (
            $1::uuid, $1::uuid, $2::uuid, $3::date, $4::date,
            $5::numeric, $5::numeric, $6::text, $7::jsonb, $8::jsonb, $9::jsonb,
            'draft', now(), now()
          )
          RETURNING *`,
            [
              userId,
              leaveTypeId,
              startStr,
              endStr,
              effectiveDaysSubmit,
              reason || null,
              payloadDetails,
              officialSnapshot,
              serializeEmployeeDetailSchema(customFieldSchema),
            ],
          );

          const row = q.rows[0];

          // Two-stage workflow: determine initial submitted status.
          if (!leaveRule?.approval_workflow_id && leaveRule?.approval_route === 'mayor') {
            const type = (
              await client.query('SELECT employment_type FROM users WHERE id=$1', [userId])
            ).rows[0]?.employment_type;
            const { chooseLeaveRoute } = require('../../../services/leaveRouting');
            if (
              chooseLeaveRoute(leaveRule, type) === 'mayor' &&
              !reviewSnapshot?.departmentHeadUserId
            ) {
              const error = new Error(
                'Configure a different department reviewer before submitting a Mayor-routed leave request.',
              );
              error.statusCode = 409;
              throw error;
            }
          }
          const submitStatus = preparedWorkflow
            ? workflowEngine.workflowStatus(preparedWorkflow)
            : reviewSnapshot?.departmentHeadUserId
              ? 'pending_department_head'
              : 'pending_hr';
          await workflowEngine.initialWorkflow(client, 'leave', row.id, preparedWorkflow);

          await client.query(
            `UPDATE leave_requests
         SET status = $1,
             review_department_id = $2::uuid,
             assigned_department_head_id = $3::uuid,
             updated_at = now()
         WHERE id = $4`,
            [
              submitStatus,
              reviewSnapshot?.departmentId || null,
              preparedWorkflow && !preparedWorkflow.steps.includes('department')
                ? null
                : reviewSnapshot?.departmentHeadUserId || null,
              row.id,
            ],
          );
          row.status = submitStatus;
          if (preparedWorkflow) {
            row.workflow_snapshot = preparedWorkflow;
            row.final_review_route = workflowEngine.workflowRoute(preparedWorkflow);
          }
          row.review_department_id = reviewSnapshot?.departmentId || null;
          row.assigned_department_head_id = reviewSnapshot?.departmentHeadUserId || null;
          await replaceRequestReviewerSnapshot(client, {
            requestType: 'leave',
            requestId: row.id,
            departmentId: reviewSnapshot?.departmentId || null,
            reviewers:
              preparedWorkflow && !preparedWorkflow.steps.includes('department')
                ? []
                : reviewSnapshot?.reviewers || [],
          });

          await insertLeaveRequestHistory(client, {
            leaveRequestId: row.id,
            action: 'submitted',
            fromStatus: null,
            toStatus: submitStatus,
            actedBy: userId,
            remarks: reason || null,
            metadataJson: {
              leave_type: leave_type || null,
              start_date: startStr,
              end_date: endStr,
              number_of_days: effectiveDaysSubmit,
              review_department_id: reviewSnapshot?.departmentId || null,
              department_head: reviewSnapshot?.departmentHeadUserId || null,
            },
          });
          // FIX #5a: Increment pending_days on direct submit (no existing draft ID).
          const pendingDeltaSubmit = effectiveDaysSubmit;
          if (pendingDeltaSubmit != null && pendingDeltaSubmit > 0) {
            const leaveTypeName = leave_type ? String(leave_type) : null;
            if (leaveTypeName) {
              const reservation = await reservePendingLeaveBalance(client, {
                userId,
                leaveTypeName,
                days: pendingDeltaSubmit,
                leaveRequestId: row.id,
                actorUserId: userId,
                actorKind: 'user',
                action: 'leave_submitted',
                metadataJson: { number_of_days: pendingDeltaSubmit },
              });
              row.reserved_credit_days = reservation?.reservedDays ?? null;
            }
          }
          const typeName = leave_type ? String(leave_type) : null;
          await require('../../../services/docutrackerLeaveSignatureService').confirmSubmittedApplicantSignature(
            client,
            req.user,
            row.id,
            req.body?.applicant_signature_asset_id,
          );
          await client.query('COMMIT');
          const nameRow = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
          const submitEmpName = nameRow.rows[0]?.full_name || 'Employee';
          notifySafe(() =>
            leaveNotifications.notifyAfterSubmit(pool, {
              leaveRequestId: row.id,
              status: row.status,
              employeeUserId: userId,
              employeeName: submitEmpName,
              leaveTypeName: typeName,
              startDateStr: startStr,
              endDateStr: endStr,
              departmentHeadUserId: reviewSnapshot?.departmentHeadUserId ?? null,
              departmentReviewerUserIds: reviewSnapshot?.reviewerUserIds || [],
            }),
          );
          const mapped = mapLeaveRowToApi({ ...row, leave_type_name: typeName });
          broadcastLeaveUpdated('submitted', mapped);
          res.status(201).json(mapped);
        } catch (e) {
          await client.query('ROLLBACK');
          throw e;
        } finally {
          client.release();
        }
      } catch (err) {
        console.error('[leave POST /submit]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to submit leave request' });
      }
    },
  };
};
