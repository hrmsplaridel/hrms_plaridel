'use strict';
// Resolve existing shared services for each new router instance.
function loadLocatorDependencies() {
  const workflowEngine = require('../../services/approvalWorkflows');
  const { finalQueueVisibilitySql } = require('../../services/approvalStageSeparation');
  const {
    normalizeLocatorRouting,
    resolveLocatorRouting,
    requireLocatorFinalRole,
  } = require('../../services/locatorRouting');
  const { resolveActiveMayor } = require('../../services/officialSignatoryService');
  const { canReadLocatorAsMayor } = require('../../services/locatorMayorAccess');
  const { todayInHrmsTimezone } = require('../../utils/dateRangeParser');
  const express = require('express');
  const {
    normalizeLocatorFieldSchema,
    locatorDetailValues,
  } = require('../../services/locatorCustomFields');
  const fs = require('fs');
  const path = require('path');
  const multer = require('multer');
  const { pool } = require('../../config/db');
  const { authMiddleware } = require('../../middleware/auth');
  const { requireDtrFeatureIfAdmin } = require('../../middleware/dtrAccess');
  const { requireAdminOrHr } = require('../../middleware/rbac');
  const {
    assertFinalLeaveReviewer,
    assertLeaveSubmissionReviewer,
    assertDepartmentApprovalFinalReviewer,
    resolveFinalLeaveReviewers,
  } = require('../../services/leaveFinalReviewerService');
  const {
    findDepartmentHeadUserId,
    getDepartmentReviewSnapshotForDate,
    isDepartmentHead,
  } = require('../../services/departmentHeadService');
  const {
    snapshotLocatorReviewers,
    persistLocatorSignature,
  } = require('../../services/locatorSignatureService');
  const locatorNotifications = require('../../services/locatorNotifications');
  const {
    recordLocatorAttachmentAccess,
    resolveLocatorAttachmentAccess,
  } = require('../../services/locatorAttachmentAccess');
  const {
    deleteLocatorAttachment,
    replaceLocatorAttachment,
  } = require('../../services/locatorAttachmentLifecycle');
  const { broadcastAppEvent } = require('../../websockets/appEvents');
  const {
    canModifyLocatorAttachment,
    locatorAttachmentRequiredError,
    parseLocatorDateOnly,
    validateLocatorAttachmentForReview,
    validateLocatorRequiredFields,
    validateLocatorWorkingDayForEmployee,
    resolveLocatorShiftCoverage,
  } = require('../../services/locatorFilingRules');
  const { findLocatorRequestConflicts } = require('../../services/locatorConflictPolicy');
  const { createLocatorSubmissionService } = require('../../services/locatorSubmissionService');
  const {
    getLocatorSubmissionAvailability,
  } = require('../../services/locatorSubmissionAvailability');
  const {
    currentHrmsDate,
    evaluateEmployeeLocatorDateWindow,
    evaluateLocatorEmployeeCorrectionWindow,
    evaluateLocatorReturnWindow,
    normalizeCorrectionReason,
  } = require('../../services/locatorDatePolicy');
  const { evaluateLocatorRevocation } = require('../../services/locatorRevocationPolicy');
  const {
    parseLocatorAdminFilters,
    parseLocatorHistoryFilters,
  } = require('../../services/locatorAdminFilters');
  const {
    captureLocatorTypeSnapshot,
    resolveLocatorTypeMetadata,
  } = require('../../services/locatorTypeSnapshot');
  const {
    locatorCorrectionChanges,
    normalizeLocatorCorrection,
  } = require('../../services/locatorCorrection');
  const {
    listLocatorWorkflowEvents,
    normalizeLocatorRejectionReason,
    recordLocatorWorkflowEvent,
  } = require('../../services/locatorWorkflowHistory');
  const { validateStaffBatch, runStaffBatch } = require('../../services/locatorStaffFiling');
  const protect = [authMiddleware];
  const LOCATOR_ATTACHMENT_SUBDIR = 'locator-attachments';
  const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '..', '..', '..', 'uploads');
  return {
    workflowEngine,
    finalQueueVisibilitySql,
    normalizeLocatorRouting,
    resolveLocatorRouting,
    requireLocatorFinalRole,
    resolveActiveMayor,
    canReadLocatorAsMayor,
    todayInHrmsTimezone,
    express,
    normalizeLocatorFieldSchema,
    locatorDetailValues,
    fs,
    path,
    multer,
    pool,
    authMiddleware,
    requireDtrFeatureIfAdmin,
    requireAdminOrHr,
    assertFinalLeaveReviewer,
    assertLeaveSubmissionReviewer,
    assertDepartmentApprovalFinalReviewer,
    resolveFinalLeaveReviewers,
    findDepartmentHeadUserId,
    getDepartmentReviewSnapshotForDate,
    isDepartmentHead,
    snapshotLocatorReviewers,
    persistLocatorSignature,
    locatorNotifications,
    recordLocatorAttachmentAccess,
    resolveLocatorAttachmentAccess,
    deleteLocatorAttachment,
    replaceLocatorAttachment,
    broadcastAppEvent,
    canModifyLocatorAttachment,
    locatorAttachmentRequiredError,
    parseLocatorDateOnly,
    validateLocatorAttachmentForReview,
    validateLocatorRequiredFields,
    validateLocatorWorkingDayForEmployee,
    resolveLocatorShiftCoverage,
    findLocatorRequestConflicts,
    createLocatorSubmissionService,
    getLocatorSubmissionAvailability,
    currentHrmsDate,
    evaluateEmployeeLocatorDateWindow,
    evaluateLocatorEmployeeCorrectionWindow,
    evaluateLocatorReturnWindow,
    normalizeCorrectionReason,
    evaluateLocatorRevocation,
    parseLocatorAdminFilters,
    parseLocatorHistoryFilters,
    captureLocatorTypeSnapshot,
    resolveLocatorTypeMetadata,
    locatorCorrectionChanges,
    normalizeLocatorCorrection,
    listLocatorWorkflowEvents,
    normalizeLocatorRejectionReason,
    recordLocatorWorkflowEvent,
    validateStaffBatch,
    runStaffBatch,
    protect,
    LOCATOR_ATTACHMENT_SUBDIR,
    UPLOAD_DIR,
  };
}
module.exports = { loadLocatorDependencies };
