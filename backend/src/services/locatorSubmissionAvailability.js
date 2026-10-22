'use strict';

const { getDepartmentReviewSnapshotForDate } = require('./departmentHeadService');
const { resolveLocatorRouting } = require('./locatorRouting');
const { assertLeaveSubmissionReviewer } = require('./leaveFinalReviewerService');

// Advisory routing preflight only. Submission repeats these same domain checks
// in its transaction, along with date/shift, attachment, signature and conflict checks.
async function getLocatorSubmissionAvailability(db, employeeId, effectiveDate) {
  const configured = await db.query(
    `SELECT code, label, filing_access, approval_route, mayor_employment_types, approval_workflow_id
     FROM locator_request_types WHERE is_active = true
     ORDER BY sort_order, label, code`
  );
  const fileable = configured.rows.filter(type =>
    ['employee', 'both'].includes(type.filing_access || 'employee'));
  if (!fileable.length) {
    return { can_submit: false, effective_date: effectiveDate, types: [],
      reason: 'No active locator request types allow employee filing. Contact HR before filing.' };
  }
  const snapshot = await getDepartmentReviewSnapshotForDate(db, employeeId, effectiveDate);
  const types = [];
  for (const type of fileable) {
    let routing;
    try {
      routing = await resolveLocatorRouting(db, employeeId, type, snapshot?.departmentHeadUserId,snapshot);
      if (!routing.workflow && routing.route === 'hr') {
        await assertLeaveSubmissionReviewer(db, employeeId, 'locator', null, snapshot);
      }
      types.push({ code: type.code, label: type.label, route: routing.route, can_submit: true });
    } catch (error) {
      // Configuration/readiness failures are expected; DB/programming failures
      // must reach the route's error handler instead of granting availability.
      if (error.statusCode !== 409) throw error;
      types.push({ code: type.code, label: type.label,
        route: routing?.route || type.approval_route || 'hr', can_submit: false,
        reason: error.message });
    }
  }
  const canSubmit = types.some(type => type.can_submit);
  const result = { can_submit: canSubmit, effective_date: effectiveDate, types };
  if (!canSubmit) {
    const reasons = [...new Set(types.map(type => type.reason))];
    result.reason = reasons.length === 1 ? reasons[0]
      : 'No locator type has an available approval route. ' +
        types.map(type => `${type.label}: ${type.reason}`).join(' ');
  }
  return result;
}

module.exports = { getLocatorSubmissionAvailability };
