'use strict';
// Load per router instance so tests and callers can supply current dependencies.
function loadLeaveDependencies() {
  const workflowEngine = require('../../services/approvalWorkflows');
  const { requireLeaveFinalRole } = require('../../services/leaveRouting');
  const {
    normalizeEligibleEmploymentTypes,
    assertLeaveEmploymentEligibility,
  } = require('../../services/leaveEmploymentEligibility');
  const {
    serviceEligibility,
    assertLeaveServiceEligibility,
  } = require('../../services/leaveServiceEligibility');
  const { finalQueueVisibilitySql } = require('../../services/approvalStageSeparation');
  const express = require('express');
  const multer = require('multer');
  const path = require('path');
  const fs = require('fs');
  const { v4: uuidv4 } = require('uuid');
  const { pool } = require('../../config/db');
  const { canAdjustLeaveCredits } = require('../../services/leaveCreditAdjustmentEligibility');
  const { lockEmployeeLeaveFiling } = require('../../services/leaveFilingLock');
  const { authMiddleware } = require('../../middleware/auth');
  const { requireDtrFeatureIfAdmin } = require('../../middleware/dtrAccess');
  const { requireAdmin, requireAdminOrHr } = require('../../middleware/rbac');
  const {
    LEAVE_TYPE_RULES,
    mustBlockMissingAttachment,
    validateEmployeeLeaveRequestWithRule,
  } = require('../../routes/leaveTypeRules');
  const {
    validateEmployeeUpdateTransition,
    validateEmployeeCancelTransition,
    validateDepartmentHeadTransition,
    validateAdminTransition,
  } = require('../../services/leaveWorkflowRules');
  const {
    getEmployeeDepartment,
    getDepartmentHeadForEmployee,
    getDepartmentReviewSnapshot,
    isDepartmentHead,
  } = require('../../services/departmentHeadService');
  const {
    resolveDepartmentReviewers,
    replaceRequestReviewerSnapshot,
  } = require('../../services/departmentReviewerService');
  const {
    initLeaveRequestHistory,
    insertLeaveRequestHistory,
  } = require('../../services/leaveRequestHistory');
  const {
    applyAdminLeaveBalanceAdjustment,
    buildLeaveBalanceHistoryFilters,
    initLeaveBalanceLedger,
    insertLeaveBalanceLedger,
    fetchBalanceSnapshot,
  } = require('../../services/leaveBalanceLedger');
  const {
    expandNonRecurringToWindow,
    expandRecurringToWindow,
  } = require('../../services/holidayRangeUtils');
  const leaveNotifications = require('../../services/leaveNotifications');
  const { runLeaveMonthlyAccrual } = require('../../services/leaveMonthlyAccrual');
  const {
    notifyLeaveMonthEnd,
    notifyLeaveMonthEndFailure,
    notificationMonthForTarget,
  } = require('../../services/leaveMonthEndNotifications');
  const { runMonthlyAttendanceDeductions } = require('../../services/leaveAttendanceDeduction');
  const {
    approvedPaidDaysForRevoke,
    resolveApprovalAllocation,
  } = require('../../services/leaveApprovalAllocation');
  const {
    calculateApprovalCreditHeadroom,
    calculateCreditReservation,
  } = require('../../services/leaveCreditReservation');
  const {
    attachmentReplacementCleanupPath,
    assertRequiredLeaveAttachment,
    canModifyLeaveAttachment,
  } = require('../../services/leaveAttachmentPolicy');
  const {
    DEPARTMENT_HEAD_HISTORY_ACTIONS,
    initLeaveAttachmentAccessLog,
    recordLeaveAttachmentAccess,
    resolveLeaveAttachmentAccess,
  } = require('../../services/leaveAttachmentAccess');
  const {
    assertCoverageMatchesRequestedDays,
    removeApprovedLeaveCoverage,
    replaceApprovedLeaveCoverage,
  } = require('../../services/leaveDtrCoverage');
  const {
    customLeaveDetailValues,
    employeeLeaveDetailsFromPayload,
    loadEmployeeOfficialSnapshot,
    normalizeEmployeeDetailSchema,
    normalizeEmployeeOfficialSnapshot,
    sanitizeEmployeeLeaveDetails,
    serializeEmployeeDetailSchema,
  } = require('../../services/leaveRequestDetailsPolicy');
  const {
    getYearEndForcedLeaveCompliance,
    applyYearEndForcedLeaveDeductions,
    manilaYearNow: yearEndManilaYearNow,
  } = require('../../services/leaveYearEndForcedLeave');
  const {
    ENTITLEMENT_BASES,
    buildAnnualEntitlementYearSummary,
    annualAllowance,
    countedDatesForCalendarYear,
    defaultEntitlementBasisForLeaveType,
    normalizeEntitlementBasis,
  } = require('../../services/leaveEntitlementPolicy');
  const { broadcastAppEvent } = require('../../websockets/appEvents');
  const { broadcastBiometricUpdate } = require('../../websockets/biometricStream');
  const {
    requireDepartmentHeadApprovalSignature,
    requireHrApprovalSignature,
  } = require('../../services/docutrackerLeaveSignatureService');
  const { resolveActiveMayor } = require('../../services/officialSignatoryService');
  const { todayInHrmsTimezone } = require('../../utils/dateRangeParser');
  const {
    assertFinalLeaveReviewer,
    assertLeaveSubmissionReviewer,
    assertDepartmentApprovalFinalReviewer,
    resolveFinalLeaveReviewers,
    resolveFinalLeaveReviewerConfiguration,
  } = require('../../services/leaveFinalReviewerService');
  const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../../uploads');
  const LEAVE_ATTACHMENT_SUBDIR = 'leave-attachments';
  const SYSTEM_LEAVE_TYPE_NAMES = Object.freeze(Object.keys(LEAVE_TYPE_RULES));
  const NO_CREDIT_LEDGER_TYPE = 'none';
  const OWN_BALANCE_LEDGER_TYPE = 'ownBalance';
  const BALANCE_LEDGER_CONFIG_TYPES = new Set([
    NO_CREDIT_LEDGER_TYPE,
    OWN_BALANCE_LEDGER_TYPE,
    'vacationLeave',
    'sickLeave',
  ]);
  const SEX_ELIGIBILITY_TYPES = new Set(['any', 'female', 'male']);
  const CREDIT_BALANCE_BUCKET_TYPES = new Set(['vacationLeave', 'sickLeave']);
  const SYSTEM_NO_CREDIT_LEAVE_TYPES = new Set([
    'maternityLeave',
    'paternityLeave',
    'specialPrivilegeLeave',
    'soloParentLeave',
    'studyLeave',
    'tenDayVawcLeave',
    'rehabilitationPrivilege',
    'specialLeaveBenefitsForWomen',
    'specialEmergencyCalamityLeave',
    'adoptionLeave',
    'others',
  ]);
  const LEGACY_NO_CREDIT_LEDGER_TYPES = new Set([...SYSTEM_NO_CREDIT_LEAVE_TYPES, 'others']);
  const LEAVE_REVOKE_WINDOW_DAYS = 3;
  const LEAVE_REVOKE_WINDOW_MS = LEAVE_REVOKE_WINDOW_DAYS * 24 * 60 * 60 * 1000;
  const ANNUAL_QUOTA_LEAVE_USAGE_STATUSES = [
    'pending',
    'pending_department_head',
    'pending_hr',
    'pending_mayor',
    'approved',
  ];
  const protect = [authMiddleware];
  return {
    workflowEngine,
    requireLeaveFinalRole,
    normalizeEligibleEmploymentTypes,
    assertLeaveEmploymentEligibility,
    serviceEligibility,
    assertLeaveServiceEligibility,
    finalQueueVisibilitySql,
    express,
    multer,
    path,
    fs,
    uuidv4,
    pool,
    canAdjustLeaveCredits,
    lockEmployeeLeaveFiling,
    authMiddleware,
    requireDtrFeatureIfAdmin,
    requireAdmin,
    requireAdminOrHr,
    LEAVE_TYPE_RULES,
    mustBlockMissingAttachment,
    validateEmployeeLeaveRequestWithRule,
    validateEmployeeUpdateTransition,
    validateEmployeeCancelTransition,
    validateDepartmentHeadTransition,
    validateAdminTransition,
    getEmployeeDepartment,
    getDepartmentHeadForEmployee,
    getDepartmentReviewSnapshot,
    isDepartmentHead,
    resolveDepartmentReviewers,
    replaceRequestReviewerSnapshot,
    initLeaveRequestHistory,
    insertLeaveRequestHistory,
    applyAdminLeaveBalanceAdjustment,
    buildLeaveBalanceHistoryFilters,
    initLeaveBalanceLedger,
    insertLeaveBalanceLedger,
    fetchBalanceSnapshot,
    expandNonRecurringToWindow,
    expandRecurringToWindow,
    leaveNotifications,
    runLeaveMonthlyAccrual,
    notifyLeaveMonthEnd,
    notifyLeaveMonthEndFailure,
    notificationMonthForTarget,
    runMonthlyAttendanceDeductions,
    approvedPaidDaysForRevoke,
    resolveApprovalAllocation,
    calculateApprovalCreditHeadroom,
    calculateCreditReservation,
    attachmentReplacementCleanupPath,
    assertRequiredLeaveAttachment,
    canModifyLeaveAttachment,
    DEPARTMENT_HEAD_HISTORY_ACTIONS,
    initLeaveAttachmentAccessLog,
    recordLeaveAttachmentAccess,
    resolveLeaveAttachmentAccess,
    assertCoverageMatchesRequestedDays,
    removeApprovedLeaveCoverage,
    replaceApprovedLeaveCoverage,
    customLeaveDetailValues,
    employeeLeaveDetailsFromPayload,
    loadEmployeeOfficialSnapshot,
    normalizeEmployeeDetailSchema,
    normalizeEmployeeOfficialSnapshot,
    sanitizeEmployeeLeaveDetails,
    serializeEmployeeDetailSchema,
    getYearEndForcedLeaveCompliance,
    applyYearEndForcedLeaveDeductions,
    yearEndManilaYearNow,
    ENTITLEMENT_BASES,
    buildAnnualEntitlementYearSummary,
    annualAllowance,
    countedDatesForCalendarYear,
    defaultEntitlementBasisForLeaveType,
    normalizeEntitlementBasis,
    broadcastAppEvent,
    broadcastBiometricUpdate,
    requireDepartmentHeadApprovalSignature,
    requireHrApprovalSignature,
    resolveActiveMayor,
    todayInHrmsTimezone,
    assertFinalLeaveReviewer,
    assertLeaveSubmissionReviewer,
    assertDepartmentApprovalFinalReviewer,
    resolveFinalLeaveReviewers,
    resolveFinalLeaveReviewerConfiguration,
    protect,
    UPLOAD_DIR,
    LEAVE_ATTACHMENT_SUBDIR,
    SYSTEM_LEAVE_TYPE_NAMES,
    NO_CREDIT_LEDGER_TYPE,
    OWN_BALANCE_LEDGER_TYPE,
    BALANCE_LEDGER_CONFIG_TYPES,
    SEX_ELIGIBILITY_TYPES,
    CREDIT_BALANCE_BUCKET_TYPES,
    SYSTEM_NO_CREDIT_LEAVE_TYPES,
    LEGACY_NO_CREDIT_LEDGER_TYPES,
    LEAVE_REVOKE_WINDOW_DAYS,
    LEAVE_REVOKE_WINDOW_MS,
    ANNUAL_QUOTA_LEAVE_USAGE_STATUSES,
  };
}
module.exports = { loadLeaveDependencies };
