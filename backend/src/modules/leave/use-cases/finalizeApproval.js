'use strict';
const {publicPaperRecord}=require('../services/paperSignatures');
module.exports = function createLeaveComponent({
  assertAnnualQuotaLeaveLimit,
  assertCoverageMatchesRequestedDays,
  assertLeaveServiceEligibility,
  assertRequiredLeaveAttachment,
  computeEmployeeLeaveWorkingDays,
  getLeaveTypeDefinition,
  hasOverlappingLeaveRequest,
  insertLeaveRequestHistory,
  replaceApprovedLeaveCoverage,
  requireHrApprovalSignature,
  reservedCreditDaysFromRequest,
  resolveActiveMayor,
  resolveApprovalAllocation,
  storedLeaveAttachmentExists,
  toIsoDateStr,
  todayInHrmsTimezone,
  upsertLeaveBalanceDeduction,
  validateAdminTransition,
  validateDepartmentHeadTransition,
  workflowEngine,
}) {
  // Shared finalization keeps department-only approval and HR approval accounting identical.
  async function finalizeLeaveApproval(
    client,
    r,
    {
      id,
      reviewerId,
      remarks,
      departmentFinal = false,
      paperRecord = null,
      recommendationRemarks = null,
      approvedOtherDetails = null,
      approvedDaysWithPayRaw,
      approvedDaysWithoutPayRaw,
    },
  ) {
    const targetUserId = r.user_id || r.employee_id;
    const startStr = toIsoDateStr(r.start_date);
    const endStr = toIsoDateStr(r.end_date);
    const workingDayResult = await computeEmployeeLeaveWorkingDays(
      client,
      targetUserId,
      startStr,
      endStr,
    );
    const storedRequestedDays = r.days != null ? parseFloat(r.days) : null;
    const approvalCoverage = assertCoverageMatchesRequestedDays(
      workingDayResult.countedDates,
      storedRequestedDays,
    );
    const approvalDates = approvalCoverage.dates;
    const approvalDays = approvalCoverage.days;
    const leaveTypeRule = r.leave_type_name
      ? await getLeaveTypeDefinition(client, r.leave_type_name)
      : null;
    await assertLeaveServiceEligibility(client, leaveTypeRule, targetUserId, startStr);
    assertRequiredLeaveAttachment({
      rule: leaveTypeRule,
      leaveType: r.leave_type_name,
      days: approvalDays,
      hasAttachment: storedLeaveAttachmentExists(r.attachment_path),
    });
    const allocation = resolveApprovalAllocation({
      requestedDays: approvalDays,
      approvedDaysWithPay: departmentFinal ? approvalDays : approvedDaysWithPayRaw,
      approvedDaysWithoutPay: departmentFinal ? 0 : approvedDaysWithoutPayRaw,
    });
    const { historyAction } = paperRecord ? {historyAction:'paper_approved_recorded'} : departmentFinal
      ? validateDepartmentHeadTransition({
          currentStatus: r.status,
          desiredStatus: 'pending_hr',
          finalReviewRoute: 'mayor',
        })
      : validateAdminTransition({ currentStatus: r.status, desiredStatus: 'approved' });
    if (!departmentFinal && !paperRecord) await requireHrApprovalSignature(client, id, reviewerId);
    const requestWorkflow = paperRecord ? null : await workflowEngine.loadRequestWorkflow(client, 'leave', id);
    const approvingAuthority = paperRecord ? {...publicPaperRecord(paperRecord).final_approver,source:'approved_paper'} :
      workflowEngine.isShared(requestWorkflow) &&
      workflowEngine.workflowRoute(requestWorkflow) !== 'mayor'
        ? await workflowEngine.reviewerProfile(client, reviewerId)
        : await resolveActiveMayor(client, todayInHrmsTimezone());

    const updated = await client.query(
      `UPDATE leave_requests
     SET status = 'approved',
         reviewer_id = $2::uuid,
         reviewer_remarks = $3::text,
         recommendation_remarks = $4::text,
         approved_days_with_pay = $5::numeric,
         approved_days_without_pay = $6::numeric,
         approved_other_details = $7::text,
         reserved_credit_days = 0,
         reviewed_at = COALESCE($9::timestamptz,now()),
         approved_by = $2::uuid,
         approved_at = COALESCE($9::timestamptz,now()),
         approving_authority_snapshot = $8::jsonb,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
      [
        id,
        paperRecord ? null : reviewerId,
        remarks,
        recommendationRemarks,
        allocation.approvedDaysWithPay,
        allocation.approvedDaysWithoutPay,
        approvedOtherDetails,
        JSON.stringify(approvingAuthority || {}),
        paperRecord ? `${paperRecord.approval_date}T00:00:00+08:00` : null,
      ],
    );
    const row = updated.rows[0];
    const days = allocation.requestedDays;
    const leaveTypeName = r.leave_type_name || null;

    // Prevent approving if another pending/approved leave overlaps this range.
    const hasOverlap = await hasOverlappingLeaveRequest(client, targetUserId, startStr, endStr, id);
    if (hasOverlap) {
      throw Object.assign(new Error('Overlapping leave request exists'), { statusCode: 400 });
    }

    await assertAnnualQuotaLeaveLimit(client, {
      userId: targetUserId,
      leaveTypeName,
      startStr,
      endStr,
      excludeId: id,
    });

    if (leaveTypeRule?.affects_dtr_normally !== false) {
      await replaceApprovedLeaveCoverage(client, {
        employeeId: targetUserId,
        leaveRequestId: id,
        dates: approvalDates,
        actorUserId: reviewerId,
      });
    }

    const reservedCreditDays = reservedCreditDaysFromRequest(r);

    // Final approval releases this request's exact pending reservation but charges only
    // the days HR classified as paid against the configured balance bucket.
    await upsertLeaveBalanceDeduction(
      client,
      targetUserId,
      leaveTypeName,
      allocation.usedDaysToDeduct,
      {
        decrementPendingDays: true,
        pendingDaysToRelease: reservedCreditDays,
        ledgerContext: {
          action: 'leave_approved',
          leaveRequestId: id,
          actorUserId: reviewerId,
          actorKind: departmentFinal
            ? 'department_reviewer'
            : workflowEngine.isShared(requestWorkflow)
              ? 'user'
              : 'admin',
          metadataJson: {
            ...(paperRecord ? {approval_source:'approved_paper',encoded_by:reviewerId,original_approval_date:paperRecord.approval_date} : {}),
            requested_days: allocation.requestedDays,
            approved_days_with_pay: allocation.approvedDaysWithPay,
            approved_days_without_pay: allocation.approvedDaysWithoutPay,
            reserved_credit_days: reservedCreditDays,
          },
        },
      },
    );

    await insertLeaveRequestHistory(client, {
      leaveRequestId: id,
      action: historyAction,
      fromStatus: r.status,
      toStatus: 'approved',
      actedBy: reviewerId,
      remarks: remarks || null,
      metadataJson: {
        ...(paperRecord ? {paper_approval_record:publicPaperRecord(paperRecord)} : {}),
        revision: row.signature_revision,
        leave_type: leaveTypeName,
        start_date: startStr,
        end_date: endStr,
        number_of_days: days,
        covered_work_dates: approvalDates,
        ...(workflowEngine.isShared(requestWorkflow)
          ? { workflow_step: requestWorkflow.steps[requestWorkflow.current_step] }
          : {}),
        approved_days_with_pay: allocation.approvedDaysWithPay,
        approved_days_without_pay: allocation.approvedDaysWithoutPay,
      },
    });

    return { row, leaveTypeName, startStr, endStr };
  }
  return { finalizeLeaveApproval };
};
