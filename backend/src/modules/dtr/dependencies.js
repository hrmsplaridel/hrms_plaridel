'use strict';
// Resolve existing shared dependencies once per router instance.
function loadDtrDependencies() {
  const express = require('express');
  const { withHeavyWork } = require('../../middleware/heavyWork');
  const { mapConcurrent, dtrRowConcurrency } = require('../../services/heavyWorkQueue');
  const { pool } = require('../../config/db');
  const { authMiddleware } = require('../../middleware/auth');
  const {
    requireAdmin,
    requireAdminOrHr,
    requireAdminOrSupervisor,
  } = require('../../middleware/rbac');
  const {
    requireDtrReportsIfAdmin,
    requireDtrManageIfAdmin,
    requireAnyDtrAccessForList,
  } = require('../../middleware/dtrAccess');
  const {
    loadHolidayOverlayMap,
    resolveAttendanceHolidayOverlay,
  } = require('../../services/holidayOverlay');
  const { broadcastBiometricUpdate } = require('../../websockets/biometricStream');
  const {
    getShiftType: resolveShiftType,
    getExpectedWorkMinutes: resolveExpectedWorkMinutes,
    getExpectedWorkMinutesForCoverage,
    getExpectedAmEndMinutes,
    getExpectedPmStartMinutes,
    computeClockOutUndertimeMinutes,
    getExpectedLogsForDay: resolveExpectedLogsForDay,
    computeTotalHoursFromRecord,
    resolveSingleSessionPunches,
  } = require('../../services/shiftAttendance');
  const {
    evaluateLocatorCoverage,
    locatorCoverageSegments,
    locatorSegmentsForMissingPunches,
    mergeLocatorCoverages,
  } = require('../../services/locatorCoverage');
  const { resolveDtrDailySummaryScope } = require('../../services/dtrDailySummaryAccess');
  const {
    attendancePolicyPayload,
    calculateAttendanceReportDeduction,
    calculateAttendancePolicyPenalties,
    loadAttendancePolicyContext,
    normalizeAttendancePolicy,
    resolveAttendancePolicy,
  } = require('../../services/attendancePolicyResolver');
  const { validateDtrPunchDates } = require('../../services/dtrPunchDateValidation');
  const { addDaysToIsoDate, isAttendanceDateFinalized } = require('../../services/dtrReportCutoff');
  const {
    loadScheduleOverrides,
    resolvedWorkingDay,
  } = require('../../services/employeeScheduleOverrides');
  const protect = [authMiddleware];
  /** Noon in minutes from midnight. */
  const NOON_MINUTES = 12 * 60;
  /** Default timezone for interpreting shift rules vs log timestamps. */
  const {
    isOvernight,
    overnightPenalties,
    hasShiftEnded,
  } = require('../../services/shiftTimeline');
  const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';
  const MAX_DTR_RANGE_DAYS = 62;
  const DEFAULT_DTR_PAGE_SIZE = 500;
  const MAX_DTR_PAGE_SIZE = 2000;
  const MAX_DTR_BULK_REPORT_EMPLOYEES = 100;
  const {
    getAttendancePolicyCache,
    setAttendancePolicyCache,
  } = require('../../services/attendancePolicyCache');
  /** 1 PM in minutes. */
  const ONE_PM_MINUTES = 13 * 60;
  return {
    express,
    withHeavyWork,
    mapConcurrent,
    dtrRowConcurrency,
    pool,
    authMiddleware,
    requireAdmin,
    requireAdminOrHr,
    requireAdminOrSupervisor,
    requireDtrReportsIfAdmin,
    requireDtrManageIfAdmin,
    requireAnyDtrAccessForList,
    loadHolidayOverlayMap,
    resolveAttendanceHolidayOverlay,
    broadcastBiometricUpdate,
    resolveShiftType,
    resolveExpectedWorkMinutes,
    getExpectedWorkMinutesForCoverage,
    getExpectedAmEndMinutes,
    getExpectedPmStartMinutes,
    computeClockOutUndertimeMinutes,
    resolveExpectedLogsForDay,
    computeTotalHoursFromRecord,
    resolveSingleSessionPunches,
    evaluateLocatorCoverage,
    locatorCoverageSegments,
    locatorSegmentsForMissingPunches,
    mergeLocatorCoverages,
    resolveDtrDailySummaryScope,
    attendancePolicyPayload,
    calculateAttendanceReportDeduction,
    calculateAttendancePolicyPenalties,
    loadAttendancePolicyContext,
    normalizeAttendancePolicy,
    resolveAttendancePolicy,
    validateDtrPunchDates,
    addDaysToIsoDate,
    isAttendanceDateFinalized,
    loadScheduleOverrides,
    resolvedWorkingDay,
    protect,
    NOON_MINUTES,
    isOvernight,
    overnightPenalties,
    hasShiftEnded,
    HRMS_TIMEZONE,
    MAX_DTR_RANGE_DAYS,
    DEFAULT_DTR_PAGE_SIZE,
    MAX_DTR_PAGE_SIZE,
    MAX_DTR_BULK_REPORT_EMPLOYEES,
    getAttendancePolicyCache,
    setAttendancePolicyCache,
    ONE_PM_MINUTES,
  };
}
module.exports = { loadDtrDependencies };
