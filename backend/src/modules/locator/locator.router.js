'use strict';
const { loadLocatorDependencies } = require('./dependencies');
const { createLocatorRuntime } = require('./locator.runtime');

function createLocatorRouter(dependencies = loadLocatorDependencies()) {
  const { express, protect, requireAdminOrHr, requireDtrFeatureIfAdmin, requireLocatorFinalRole } =
    dependencies;
  const router = express.Router();
  const runtime = createLocatorRuntime(dependencies);
  const { uploadLocatorAttachmentMw } = runtime;
  const controllers = {
    ...require('./controllers/availability.controller')(runtime),
    ...require('./controllers/types.controller')(runtime),
    ...require('./controllers/requests.controller')(runtime),
    ...require('./controllers/staffFiling.controller')(runtime),
    ...require('./controllers/paperRecording.controller')(runtime),
    ...require('./controllers/submit.controller')(runtime),
    ...require('./controllers/corrections.controller')(runtime),
    ...require('./controllers/requestActions.controller')(runtime),
    ...require('./controllers/attachments.controller')(runtime),
    ...require('./controllers/history.controller')(runtime),
    ...require('./controllers/departmentQueue.controller')(runtime),
    ...require('./controllers/departmentDecisions.controller')(runtime),
    ...require('./controllers/finalQueue.controller')(runtime),
    ...require('./controllers/finalDecisions.controller')(runtime),
    ...require('./controllers/revoke.controller')(runtime),
  };
  // Preserve the print mount, endpoint order and authorization middleware.
  router.use('/print', protect, require('../../routes/locatorPrintTemplates'));
  router.get(
    '/final-reviewer/me',
    protect,
    requireLocatorFinalRole,
    controllers.getFinalReviewerAccess
  );
  router.get('/submission-availability', protect, controllers.getSubmissionAvailability);
  router.get('/context', protect, controllers.getContext);
  router.get('/shift-coverage', protect, controllers.getShiftCoverage);
  router.get('/department-head/check', protect, controllers.getDepartmentReviewerAccess);
  router.get('/types', protect, controllers.listTypes);
  router.post(
    '/types',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('locator_allowed'),
    controllers.createType
  );
  router.put(
    '/types/:id',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('locator_allowed'),
    controllers.updateType
  );
  router.delete(
    '/types/:id',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('locator_allowed'),
    controllers.deleteType
  );
  router.get('/my', protect, controllers.listMyRequests);
  router.get(
    '/admin/filing-employees',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('locator_allowed'),
    controllers.listFilingEmployees
  );
  router.post(
    '/admin/file',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('locator_allowed'),
    uploadLocatorAttachmentMw,
    controllers.fileForEmployees
  );
  router.get('/admin/paper-signatories', protect, requireAdminOrHr,
    requireDtrFeatureIfAdmin('locator_allowed'), controllers.paperSignatorySuggestions);
  router.post('/admin/approved-paper', protect, requireAdminOrHr,
    requireDtrFeatureIfAdmin('locator_allowed'), uploadLocatorAttachmentMw, controllers.recordApprovedPaper);
  router.post('/submit', protect, controllers.submitRequest);
  router.post(
    '/submit-with-attachment',
    protect,
    uploadLocatorAttachmentMw,
    controllers.submitWithAttachment
  );
  router.post(
    '/admin/corrections',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('locator_allowed'),
    uploadLocatorAttachmentMw,
    controllers.recordCorrection
  );
  router.patch('/:id/cancel', protect, controllers.cancelRequest);
  router.patch('/:id/resubmit', protect, controllers.resubmitRequest);
  router.post('/:id/attachment', protect, uploadLocatorAttachmentMw, controllers.uploadAttachment);
  router.delete('/:id/attachment', protect, controllers.deleteAttachment);
  router.get('/:id/history', protect, controllers.getRequestHistory);
  router.get('/:id/attachment', protect, controllers.downloadAttachment);
  router.get('/department-head', protect, controllers.listDepartmentRequests);
  router.patch('/:id/department-head-approve', protect, controllers.approveDepartment);
  router.patch('/:id/department-head-reject', protect, controllers.rejectDepartment);
  router.patch('/:id/department-head-return', protect, controllers.returnDepartment);
  router.get(
    '/admin',
    protect,
    requireLocatorFinalRole,
    requireDtrFeatureIfAdmin('locator_allowed'),
    controllers.listFinalReviewRequests
  );
  router.patch(
    '/:id/return-for-correction',
    protect,
    requireLocatorFinalRole,
    requireDtrFeatureIfAdmin('locator_allowed'),
    controllers.returnForCorrection
  );
  router.patch(
    '/:id/approve',
    protect,
    requireLocatorFinalRole,
    requireDtrFeatureIfAdmin('locator_allowed'),
    controllers.approveFinal
  );
  router.patch(
    '/:id/revoke',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('locator_allowed'),
    controllers.revokeRequest
  );
  router.patch(
    '/:id/reject',
    protect,
    requireLocatorFinalRole,
    requireDtrFeatureIfAdmin('locator_allowed'),
    controllers.rejectFinal
  );
  return router;
}
module.exports = { createLocatorRouter };
