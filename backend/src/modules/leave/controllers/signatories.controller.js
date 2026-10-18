'use strict';
module.exports = function createLeaveControllers({
  findAssignmentProfileByUserIdAtDate,
  getDepartmentHeadForEmployee,
  getEmployeeDepartment,
  isDepartmentHead,
  mapOfficialSignatoryProfile,
  mapSignatoryProfile,
  pool,
  resolveActiveMayor,
  resolveDepartmentReviewers,
  resolveFinalLeaveReviewerConfiguration,
  todayInHrmsTimezone,
  workflowEngine,
}) {
  return {
    getSignatories: async (req, res) => {
      const requesterId = req.user?.id;
      const role = req.user?.role;
      if (!requesterId) return res.status(401).json({ error: 'Not authenticated' });
      const employeeId = (req.query?.employee_id || '').toString().trim();
      const leaveRequestId = (req.query?.leave_request_id || '').toString().trim() || null;
      if (!employeeId) return res.status(400).json({ error: 'employee_id is required' });

      try {
        const privileged = role === 'admin' || role === 'hr';
        let requestContext = null;
        if (leaveRequestId) {
          const requestResult = await pool.query(
            `SELECT lr.id,
                COALESCE(lr.user_id, lr.employee_id) AS employee_id,
                lr.status,
                COALESCE(
                  (
                    SELECT h.acted_at
                    FROM leave_request_history h
                    WHERE h.leave_request_id = lr.id
                      AND h.action IN ('submitted', 'resubmitted')
                    ORDER BY h.acted_at DESC
                    LIMIT 1
                  ),
                  lr.created_at
                )::date::text AS submitted_on,
                lr.review_department_id,
                lr.approved_at::date::text AS approved_on,
                lr.approving_authority_snapshot,lr.final_review_route,lr.final_reviewer_user_id,lr.workflow_snapshot,
                lr.assigned_department_head_id,
                d.name AS review_department_name,
                EXISTS (
                  SELECT 1
                  FROM leave_request_history h
                  WHERE h.leave_request_id = lr.id
                    AND h.acted_by = $2::uuid
                    AND h.action IN (
                      'department_head_approved',
                      'department_head_rejected',
                      'department_head_returned'
                    )
                ) AS requester_reviewed
                , EXISTS (
                  SELECT 1
                  FROM leave_request_department_reviewers lrr
                  WHERE lrr.leave_request_id = lr.id
                    AND lrr.reviewer_id = $2::uuid
                ) AS requester_snapshotted_reviewer
         FROM leave_requests lr
         LEFT JOIN departments d ON d.id = lr.review_department_id
         WHERE lr.id = $1::uuid
         LIMIT 1`,
            [leaveRequestId, requesterId],
          );
          requestContext = requestResult.rows[0] || null;
          if (!requestContext) {
            return res.status(404).json({ error: 'Leave request not found' });
          }
          if (String(requestContext.employee_id) !== employeeId) {
            return res.status(400).json({ error: 'employee_id does not match the leave request' });
          }
          if (
            (await require('../../../services/sharedWorkflowInbox').pendingReadAccess(
              pool,
              'leave',
              requestContext,
              req.user,
            )) === false
          ) {
            return res.status(403).json({ error: 'Not authorized to view leave form signatories' });
          }
          const canReviewRequest =
            (workflowEngine.isShared(requestContext.workflow_snapshot) &&
              (await require('../../../services/sharedWorkflowInbox').canRead(
                pool,
                'leave',
                requestContext,
                req.user,
              ))) ||
            (['mayor', 'mayor_direct'].includes(requestContext.final_review_route) &&
              (await workflowEngine.isCurrentMayor(pool, req.user))) ||
            requestContext.assigned_department_head_id === requesterId ||
            requestContext.requester_reviewed === true ||
            requestContext.requester_snapshotted_reviewer === true;
          if (!privileged && requesterId !== employeeId && !canReviewRequest) {
            return res.status(403).json({ error: 'Not authorized to view leave form signatories' });
          }
        } else if (!privileged && requesterId !== employeeId) {
          const requesterDept = await isDepartmentHead(pool, requesterId);
          const employeeDept = await getEmployeeDepartment(pool, employeeId);
          if (
            !requesterDept.isDeptHead ||
            !requesterDept.departmentId ||
            !employeeDept?.departmentId ||
            requesterDept.departmentId !== employeeDept.departmentId
          ) {
            return res.status(403).json({ error: 'Not authorized to view leave form signatories' });
          }
        }

        const signatoryDate =
          requestContext?.approved_on || requestContext?.submitted_on || todayInHrmsTimezone();
        const { primary: hrCertifier } = await resolveFinalLeaveReviewerConfiguration(
          pool,
          signatoryDate,
        );
        const approvingAuthority =
          requestContext?.status === 'approved' &&
          requestContext?.approving_authority_snapshot?.name
            ? requestContext.approving_authority_snapshot
            : await resolveActiveMayor(pool, requestContext?.approved_on || todayInHrmsTimezone());
        const departmentHeadInfo = requestContext
          ? requestContext.assigned_department_head_id
            ? {
                departmentHeadUserId: requestContext.assigned_department_head_id,
                departmentId: requestContext.review_department_id || null,
                departmentName: requestContext.review_department_name || null,
              }
            : null
          : await getDepartmentHeadForEmployee(pool, employeeId);
        const departmentHeadProfile = departmentHeadInfo?.departmentHeadUserId
          ? await findAssignmentProfileByUserIdAtDate(
              pool,
              departmentHeadInfo.departmentHeadUserId,
              requestContext?.submitted_on || null,
            )
          : null;

        const departmentId =
          requestContext?.review_department_id || departmentHeadInfo?.departmentId;
        const primaryDepartment = departmentId
          ? (
              await resolveDepartmentReviewers(pool, {
                departmentId,
                effectiveDate: requestContext?.submitted_on || signatoryDate,
              })
            ).primary
          : null;
        const applicantIsHead =
          String(
            primaryDepartment?.reviewerId || departmentHeadInfo?.departmentHeadUserId || '',
          ) === employeeId;
        const applicantIsHr = String(hrCertifier?.id || '') === employeeId;
        const replacement =
          applicantIsHead || applicantIsHr
            ? mapOfficialSignatoryProfile(await resolveActiveMayor(pool, todayInHrmsTimezone()))
            : null;
        if (workflowEngine.isShared(requestContext?.workflow_snapshot)) {
          const officials = await workflowEngine.printOfficials(pool, 'leave', {
            ...requestContext,
            employee_id: employeeId,
          });
          return res.json({
            hr_certification_officer: hrCertifier
              ? mapOfficialSignatoryProfile({ ...hrCertifier, employee_id: hrCertifier.id })
              : null,
            recommendation_officer: mapOfficialSignatoryProfile(officials.department_head),
            approving_authority: mapOfficialSignatoryProfile(officials.hr_approver),
          });
        }
        res.json({
          hr_certification_officer: applicantIsHr
            ? replacement
            : hrCertifier
              ? mapOfficialSignatoryProfile({ ...hrCertifier, employee_id: hrCertifier.id })
              : null,
          recommendation_officer: applicantIsHead
            ? replacement
            : departmentHeadProfile
              ? mapSignatoryProfile({
                  ...departmentHeadProfile,
                  department_id:
                    departmentHeadInfo.departmentId || departmentHeadProfile.department_id,
                  department_name:
                    departmentHeadInfo.departmentName || departmentHeadProfile.department_name,
                })
              : null,
          approving_authority: mapOfficialSignatoryProfile(approvingAuthority),
        });
      } catch (err) {
        console.error('[leave GET /signatories]', err);
        res.status(500).json({ error: 'Failed to fetch leave form signatories' });
      }
    },
  };
};
