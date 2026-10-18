'use strict';
module.exports = function createLocatorComponent({
  assertLeaveSubmissionReviewer,
  broadcastLocatorUpdated,
  createLocatorSubmissionService,
  fetchLocatorSlipDetails,
  findLocatorRequestConflicts,
  getDepartmentReviewSnapshotForDate,
  getLocatorTypeByCode,
  locatorNotifications,
  mapLocatorRow,
  pool,
  recordLocatorWorkflowEvent,
  resolveFinalLeaveReviewers,
  snapshotLocatorReviewers,
  validateLocatorWorkingDayForEmployee,
}) {
  const locatorSubmissionService = createLocatorSubmissionService({
    dbPool: pool,
    getReviewSnapshot: getDepartmentReviewSnapshotForDate,
    validateWorkingDay: validateLocatorWorkingDayForEmployee,
    getLocatorTypeByCode,
    findConflicts: findLocatorRequestConflicts,
    fetchSlipDetails: fetchLocatorSlipDetails,
    mapInsertedRow: mapLocatorRow,
    notifyAfterSubmit: async (db, payload) => {
      if (payload.status === 'approved') {
        return locatorNotifications.notifyEmployee(db, {
          employeeUserId: payload.employeeUserId,
          slipId: payload.slipId,
          type: 'locator_approved_hr',
          title: 'Locator request filed and approved',
          body: 'HR filed and approved a locator request for you.',
        });
      }
      await locatorNotifications.notifyAfterSubmit(db, payload);
      if (payload.filedBy)
        await locatorNotifications.notifyEmployee(db, {
          employeeUserId: payload.employeeUserId,
          slipId: payload.slipId,
          type: 'locator_filed_by_staff',
          title: 'Locator request filed for you',
          body: 'HR/admin filed a locator request for you. It is awaiting approval.',
        });
    },
    broadcastSubmitted: (row) => broadcastLocatorUpdated('submitted', row),
    recordHistory: recordLocatorWorkflowEvent,
    snapshotReviewers: snapshotLocatorReviewers,
    assertSubmissionReviewer: (db, applicantId, snapshot) =>
      assertLeaveSubmissionReviewer(db, applicantId, 'locator', null, snapshot),
    canApproveForEmployee: async (db, employeeId, actor) => {
      if (String(employeeId) === String(actor.id)) return false;
      const reviewers = await resolveFinalLeaveReviewers(db);
      return reviewers.some((r) => String(r.id) === String(actor.id));
    },
  });
  return { locatorSubmissionService };
};
