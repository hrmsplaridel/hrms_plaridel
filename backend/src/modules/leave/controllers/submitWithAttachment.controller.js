'use strict';
module.exports = function createLeaveControllers({
  assertAnnualQuotaLeaveLimit,
  assertLeaveEmploymentEligibility,
  assertLeaveServiceEligibility,
  assertLeaveSubmissionReviewer,
  broadcastLeaveUpdated,
  broadcastDtrLeaveRefresh,
  prepareStaffLeave,
  completeStaffLeave,
  cleanupStoredLeaveAttachment,
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
  parseJsonBodyField,
  pool,
  readAdoptionParentRole,
  readLeaveEventDates,
  readMaternityDeliveryType,
  replaceRequestReviewerSnapshot,
  requiredLeaveDateRangeError,
  reservePendingLeaveBalance,
  serializeEmployeeDetailSchema,
  storedLeaveAttachmentFromMemoryFile,
  toIsoDateStr,
  validateEmployeeLeaveRequestWithRule,
  workflowEngine,
}) {
  return {
    submitWithAttachment: async (req, res, staffEmployeeId) => {
      const staffFiling = typeof staffEmployeeId === 'string';
      const userId = staffFiling ? staffEmployeeId : req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      if (!req.file) {
        return res
          .status(400)
          .json({ error: 'No file uploaded. Allowed: PDF, JPG, JPEG, PNG (max 10MB).' });
      }

      let storedAttachmentRelPath = null;
      try {
        const body = { ...(req.body || {}) };
        body.details = parseJsonBodyField(body.details);
        const { leave_type, start_date, end_date, reason, details, ...rest } = body;

        const dateError = requiredLeaveDateRangeError(start_date, end_date);
        if (dateError) return res.status(400).json({ error: dateError });
        const startStr = toIsoDateStr(start_date);
        const endStr = toIsoDateStr(end_date);
        const days = computeNumberOfDaysSync(startStr, endStr);

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

          let leaveRule = await getLeaveTypeDefinition(client, leave_type);
          const staffPlan = staffFiling ? await prepareStaffLeave(client, {
            actor:req.user, employeeId:userId, rule:leaveRule, start:startStr, end:endStr,
            paperApproval:req.body?.paper_approval,hasAttachment:Boolean(req.file?.buffer?.length),
          }) : null;
          if (staffPlan) leaveRule = staffPlan.rule;
          await assertLeaveEmploymentEligibility(client, leaveRule, userId);
          await assertLeaveServiceEligibility(client, leaveRule, userId, startStr);
          const reviewSnapshot = staffFiling ? {} : await getDepartmentReviewSnapshot(client, userId);
          const preparedWorkflow = staffFiling ? null : await workflowEngine.prepareWorkflow(
            client, 'leave', leaveRule, userId, reviewSnapshot,
          );
          if (!staffFiling) await assertLeaveSubmissionReviewer(client,userId,'leave',leaveRule,reviewSnapshot);
          const customFieldSchema = normalizeEmployeeDetailSchema(
            leaveRule?.employee_detail_schema,
          );
          const payloadDetails = employeeLeaveDetailsFromPayload({
            details,
            rest,
            customFieldSchema,
          });
          const officialSnapshot = await loadEmployeeOfficialSnapshot(client,userId,staffPlan?.paperRecord.original_filing_date);
          if (staffPlan) officialSnapshot.date_filed = staffPlan.paperRecord.original_filing_date;
          const otherPurpose = (
            payloadDetails.other_purpose ||
            payloadDetails.otherPurpose ||
            ''
          ).toString();
          const maternityDeliveryType = readMaternityDeliveryType(payloadDetails);
          const adoptionParentRole = readAdoptionParentRole(payloadDetails);
          const eventDates = readLeaveEventDates(payloadDetails);

          const effectiveDaysSubmit = workingDayResult.days ?? days;
          if (effectiveDaysSubmit == null || effectiveDaysSubmit <= 0) {
            await client.query('ROLLBACK');
            return res
              .status(400)
              .json({ error: 'Number of working days must be greater than 0.' });
          }

          const userSex = await getUserSexForLeaveValidation(client, userId);
          const validation = validateEmployeeLeaveRequestWithRule({
            rule: staffFiling ? {...leaveRule,employee_can_file:true,admin_only:false} : leaveRule,
            leaveType: leave_type,
            otherPurpose: otherPurpose || null,
            startDateStr: startStr,
            endDateStr: endStr,
            numberOfDays: effectiveDaysSubmit,
            hasAttachment: true,
            userSex,
            maternityDeliveryType,
            adoptionParentRole,
            eventDates,
            details: payloadDetails,
            enforceEventDateRules: true,
            filingDateStr:staffPlan?.paperRecord.original_filing_date,
          });
          if (!validation.valid) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: validation.error });
          }

          if (mustBlockMissingAttachment(leaveRule, leave_type, effectiveDaysSubmit, true)) {
            await client.query('ROLLBACK');
            const label = leaveRule?.display_name || leave_type || 'This leave type';
            return res.status(400).json({
              error: `${label} requires a supporting document before submission.`,
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

          const storedAttachment = storedLeaveAttachmentFromMemoryFile(req.file);
          if (!storedAttachment) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: 'Could not read uploaded attachment.' });
          }
          storedAttachmentRelPath = storedAttachment.relPath;

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
            attachment_name,
            attachment_path,
            attachment_mime_type,
            attachment_uploaded_at,
            status,
            created_at,
            updated_at
          )
          VALUES (
            $1::uuid, $1::uuid, $2::uuid, $3::date, $4::date,
            $5::numeric, $5::numeric, $6::text, $7::jsonb, $8::jsonb, $9::jsonb,
            $10::text, $11::text, $12::text, now(),
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
              storedAttachment.originalName,
              storedAttachment.relPath,
              storedAttachment.mimeType,
            ],
          );

          let row = q.rows[0];
          if (!staffFiling && !leaveRule?.approval_workflow_id && leaveRule?.approval_route === 'mayor') {
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
          const submitStatus = staffFiling ? 'pending_hr' : preparedWorkflow
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

          if (!staffFiling) await insertLeaveRequestHistory(client, {
            leaveRequestId: row.id,
            action: 'submitted',
            fromStatus: null,
            toStatus: submitStatus,
            actedBy: staffFiling ? req.user.id : userId,
            remarks: reason || null,
            metadataJson: {
              leave_type: leave_type || null,
              start_date: startStr,
              end_date: endStr,
              number_of_days: effectiveDaysSubmit,
              attachment_name: storedAttachment.originalName,
              review_department_id: reviewSnapshot?.departmentId || null,
              department_head: reviewSnapshot?.departmentHeadUserId || null,
            },
          });

          if (effectiveDaysSubmit != null && effectiveDaysSubmit > 0) {
            const leaveTypeName = leave_type ? String(leave_type) : null;
            if (leaveTypeName) {
              const reservation = await reservePendingLeaveBalance(client, {
                userId,
                leaveTypeName,
                days: effectiveDaysSubmit,
                leaveRequestId: row.id,
                actorUserId: staffFiling ? req.user.id : userId,
                actorKind: 'user',
                action: staffFiling ? 'paper_leave_recording' : 'leave_submitted',
                metadataJson: {
                  number_of_days: effectiveDaysSubmit,
                  attachment_name: storedAttachment.originalName,
                },
              });
              row.reserved_credit_days = reservation?.reservedDays ?? null;
            }
          }

          const typeName = leave_type ? String(leave_type) : null;
          if (!staffFiling) await require('../../../services/docutrackerLeaveSignatureService').confirmSubmittedApplicantSignature(
            client,
            req.user,
            row.id,
            req.body?.applicant_signature_asset_id,
          );
          if (staffPlan) row = await completeStaffLeave(client, {
            actor:req.user,row,leaveTypeName:typeName,paperRecord:staffPlan.paperRecord,
            approvedDaysWithPay:req.body?.approved_days_with_pay,approvedDaysWithoutPay:req.body?.approved_days_without_pay,
            remarks:req.body?.reviewer_remarks,
          });
          await client.query('COMMIT');
          storedAttachmentRelPath = null;

          const nameRow = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
          const submitEmpName = nameRow.rows[0]?.full_name || 'Employee';
          if (staffPlan) {
            notifySafe(() => leaveNotifications.notifyEmployee(pool, {employeeUserId:userId,
              leaveRequestId:row.id,type:'leave_approved',title:'Approved paper leave recorded',
              body:'Your approved paper leave was recorded by HR.',metadata:{filed_by:req.user.id}}));
            broadcastDtrLeaveRefresh('leave_approved_applied_to_dtr', {userId,leaveRequestId:row.id,dateFrom:startStr,dateTo:endStr});
          } else notifySafe(() =>
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
          broadcastLeaveUpdated(staffPlan ? 'paper_recorded' : 'submitted', mapped);
          res.status(201).json(mapped);
        } catch (e) {
          try {
            await client.query('ROLLBACK');
          } catch (_) {}
          cleanupStoredLeaveAttachment(storedAttachmentRelPath);
          storedAttachmentRelPath = null;
          throw e;
        } finally {
          client.release();
        }
      } catch (err) {
        cleanupStoredLeaveAttachment(storedAttachmentRelPath);
        console.error('[leave POST /submit-with-attachment]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to submit leave request with attachment' });
      }
    },
  };
};
