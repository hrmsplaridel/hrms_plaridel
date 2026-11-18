'use strict';
const { loadLeaveDependencies } = require('./dependencies');
const { createLeaveRuntime } = require('./leave.runtime');

function createLeaveRouter(dependencies = loadLeaveDependencies()) {
  const {
    authMiddleware,
    express,
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin,
    requireDtrActionIfAdmin,
    requireLeaveLedgerIfAdmin,
    requireLeaveFinalRole,
  } = dependencies;
  const router = express.Router();
  router.use('/print', authMiddleware, require('../../routes/leavePrintTemplates'));
  router.use('/routing', authMiddleware, require('../../routes/leaveRouting'));
  const runtime = createLeaveRuntime(dependencies);
  const { uploadLeaveAttachmentMemoryMw, uploadLeaveAttachmentMw } = runtime;
  const controllers = {
    ...require('./controllers/availability.controller')(runtime),
    ...require('./controllers/types.controller')(runtime),
    ...require('./controllers/workingDays.controller')(runtime),
    ...require('./controllers/draft.controller')(runtime),
    ...require('./controllers/submit.controller')(runtime),
    ...require('./controllers/submitWithAttachment.controller')(runtime),
    ...require('./controllers/update.controller')(runtime),
    ...require('./controllers/requestActions.controller')(runtime),
    ...require('./controllers/requestQueries.controller')(runtime),
    ...require('./controllers/signatories.controller')(runtime),
    ...require('./controllers/administration.controller')(runtime),
    ...require('./controllers/reviewQueries.controller')(runtime),
    ...require('./controllers/departmentDecisions.controller')(runtime),
    ...require('./controllers/finalDecisions.controller')(runtime),
    ...require('./controllers/revoke.controller')(runtime),
    ...require('./controllers/balances.controller')(runtime),
    ...require('./controllers/attachments.controller')(runtime),
  };

  const staffControllers = require('./controllers/staffFiling.controller')(runtime, controllers);
  const staffAccess = [protect, requireAdminOrHr, requireDtrFeatureIfAdmin('leave_allowed')];
  const balancesAccess = [...staffAccess, requireDtrActionIfAdmin('leave_balances_allowed')];
  const paperAccess = [...staffAccess, requireDtrActionIfAdmin('leave_paper_allowed')];
  const openingControllers = require('./controllers/openingBalances.controller')(runtime);
  router.get('/admin/opening-balances', ...balancesAccess, openingControllers.listOpeningBalances);
  router.post('/admin/opening-balances/import', ...balancesAccess, openingControllers.importOpeningBalances);
  router.post('/admin/opening-balances/:userId/usage', ...balancesAccess, openingControllers.verifyOpeningUsage);
  router.get('/admin/opening-balances/:userId', ...balancesAccess, openingControllers.getOpeningBalances);
  router.post('/admin/opening-balances/:userId', ...balancesAccess, openingControllers.saveOpeningBalances);
  router.get('/admin/filing-employees', ...paperAccess, staffControllers.listFilingEmployees);
  router.get('/admin/paper-signatories', ...paperAccess, staffControllers.paperSignatorySuggestions);
  router.get('/admin/submission-availability', ...paperAccess, staffControllers.staffSubmissionAvailability);
  router.get('/admin/working-days', ...paperAccess, (req,res) => {
    if (typeof req.query.employee_id !== 'string') return res.status(400).json({error:'Select a valid employee.'});
    return controllers.previewWorkingDays(req,res,req.query.employee_id);
  });
  router.post('/admin/file', ...paperAccess, uploadLeaveAttachmentMemoryMw, staffControllers.fileForEmployees);

  // Registration order is part of the existing API contract. Keep /:id after fixed paths.
  router.get(
    '/final-reviewer/me',
    protect,
    requireLeaveFinalRole,
    controllers.getFinalReviewerEligibility,
  );
  router.get('/submission-availability', protect, controllers.getSubmissionAvailability);
  router.get('/types', protect, controllers.listTypes);
  router.post(
    '/types',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('leave_allowed'),
    requireDtrActionIfAdmin('leave_types_allowed'),
    controllers.createType,
  );
  router.put(
    '/types/:id',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('leave_allowed'),
    requireDtrActionIfAdmin('leave_types_allowed'),
    controllers.updateType,
  );
  router.get('/working-days', protect, controllers.previewWorkingDays);
  router.post('/draft', protect, controllers.saveDraft);
  router.post('/submit', protect, controllers.submitLeave);
  router.post(
    '/submit-with-attachment',
    protect,
    uploadLeaveAttachmentMemoryMw,
    controllers.submitWithAttachment,
  );
  router.put('/:id', protect, controllers.updateLeave);
  router.patch('/:id/discard', protect, controllers.discardDraft);
  router.patch('/:id/cancel', protect, controllers.cancelLeave);
  router.get('/my/context', protect, controllers.getEmployeeContext);
  router.get('/my', protect, controllers.listMyRequests);
  router.get('/my/:id/history', protect, controllers.getMyHistory);
  router.get('/signatories', protect, controllers.getSignatories);
  router.post(
    '/admin/forced-leave-deduction',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('leave_allowed'),
    requireDtrActionIfAdmin('leave_year_end_allowed'),
    controllers.deductForcedLeave,
  );
  router.post(
    '/admin/monthly-accrual',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('leave_allowed'),
    requireDtrActionIfAdmin('leave_month_end_allowed'),
    controllers.runMonthlyAccrual,
  );
  router.get(
    '/filter-options',
    protect,
    requireLeaveFinalRole,
    requireDtrFeatureIfAdmin('leave_allowed'),
    controllers.getReviewFilters,
  );
  router.get(
    '/',
    protect,
    requireLeaveFinalRole,
    requireDtrFeatureIfAdmin('leave_allowed'),
    controllers.listFinalReviewRequests,
  );
  router.get(
    '/pending',
    protect,
    requireLeaveFinalRole,
    requireDtrFeatureIfAdmin('leave_allowed'),
    controllers.listPendingRequests,
  );
  router.get('/department-head/check', protect, controllers.getDepartmentReviewerAccess);
  router.get('/department-head/filter-options', protect, controllers.getDepartmentReviewFilters);
  router.get('/department-head', protect, controllers.listDepartmentRequests);
  router.patch('/:id/department-head-approve', protect, controllers.approveDepartment);
  router.patch('/:id/department-head-reject', protect, controllers.rejectDepartment);
  router.patch('/:id/department-head-return', protect, controllers.returnDepartment);
  router.patch(
    '/:id/approve',
    protect,
    requireLeaveFinalRole,
    requireDtrFeatureIfAdmin('leave_allowed'),
    controllers.approveFinal,
  );
  router.patch(
    '/:id/reject',
    protect,
    requireLeaveFinalRole,
    requireDtrFeatureIfAdmin('leave_allowed'),
    controllers.rejectFinal,
  );
  router.patch(
    '/:id/revoke',
    protect,
    requireLeaveFinalRole,
    requireDtrFeatureIfAdmin('leave_allowed'),
    controllers.revokeLeave,
  );
  router.patch(
    '/:id/return',
    protect,
    requireLeaveFinalRole,
    requireDtrFeatureIfAdmin('leave_allowed'),
    controllers.returnFinal,
  );
  router.get('/ledger', protect, requireLeaveLedgerIfAdmin, controllers.getLedger);
  router.get('/admin/leave-card/:userId/ledger', ...staffAccess,
    requireDtrActionIfAdmin('leave_card_allowed'), (req, res) => {
      if (!require('uuid').validate(req.params.userId)) {
        return res.status(400).json({ error: 'Select a valid employee.' });
      }
      req.query = { ...req.query, user_id: req.params.userId, all_users: 'false', include_all_users: 'false' };
      return controllers.getLedger(req, res);
    });
  router.get('/:id/form-credits', protect, controllers.getFormCredits);
  router.get('/balances/:userId', protect, controllers.getBalances);
  router.post(
    '/balances/:userId/adjustments',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('leave_allowed'),
    requireDtrActionIfAdmin('leave_balances_allowed'),
    controllers.adjustBalance,
  );
  router.put(
    '/balances/:userId',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('leave_allowed'),
    requireDtrActionIfAdmin('leave_balances_allowed'),
    controllers.rejectBalanceReplacement,
  );
  router.post('/:id/attachment', protect, uploadLeaveAttachmentMw, controllers.uploadAttachment);
  router.delete('/:id/attachment', protect, controllers.deleteAttachment);
  router.get('/:id/attachment', protect, controllers.downloadAttachment);
  router.get('/:id', protect, controllers.getRequest);
  router.get(
    '/admin/year-end-forced-leave',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('leave_allowed'),
    requireDtrActionIfAdmin('leave_year_end_allowed'),
    controllers.previewYearEndForcedLeave,
  );
  router.post(
    '/admin/year-end-forced-leave/apply',
    protect,
    requireAdminOrHr,
    requireDtrFeatureIfAdmin('leave_allowed'),
    requireDtrActionIfAdmin('leave_year_end_allowed'),
    controllers.applyYearEndForcedLeave,
  );
  return router;
}
module.exports = { createLeaveRouter };
