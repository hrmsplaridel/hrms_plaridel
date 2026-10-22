'use strict';
const { loadDtrDependencies } = require('./dependencies');
const { createDtrRuntime } = require('./dtr.runtime');

function createDtrRouter(dependencies = loadDtrDependencies()) {
  const {
    express,
    protect,
    requireAdmin,
    requireAdminOrHr,
    requireAdminOrSupervisor,
    requireAnyDtrAccessForList,
    requireDtrManageIfAdmin,
    requireDtrReportsIfAdmin,
    withHeavyWork,
  } = dependencies;
  const router = express.Router();
  const runtime = createDtrRuntime(dependencies);
  const controllers = {
    listDtrDailySummaries: runtime.listDtrDailySummaries,
    ...require('./controllers/reportYears.controller')(runtime),
    ...require('./controllers/bulkReport.controller')(runtime),
    ...require('./controllers/dashboard.controller')(runtime),
    ...require('./controllers/shifts.controller')(runtime),
    ...require('./controllers/today.controller')(runtime),
    ...require('./controllers/create.controller')(runtime),
    ...require('./controllers/update.controller')(runtime),
    ...require('./controllers/recalculate.controller')(runtime),
    ...require('./controllers/deletions.controller')(runtime),
    ...require('./controllers/restore.controller')(runtime),
    ...require('./controllers/holidays.controller')(runtime),
  };
  // Preserve endpoint order, guards, and the bulk-report heavy-work wrapper.
  router.get('/report-years', protect, controllers.getReportYears);
  router.get('/', protect, requireAnyDtrAccessForList, controllers.listDtrDailySummaries);
  router.post(
    '/bulk-report',
    protect,
    requireAdminOrSupervisor,
    requireDtrReportsIfAdmin,
    withHeavyWork(controllers.getBulkReport)
  );
  router.get(
    '/summary',
    protect,
    requireAdminOrSupervisor,
    requireDtrManageIfAdmin,
    controllers.getDashboardSummary
  );
  router.get('/shift-for-date', protect, requireAdminOrHr, controllers.getShiftForDate);
  router.get('/my-shift-today', protect, controllers.getMyShiftToday);
  router.get('/today', protect, controllers.getTodayRecord);
  router.post('/', protect, requireAdminOrHr, requireDtrManageIfAdmin, controllers.createRecord);
  router.put('/:id', protect, requireAdminOrHr, requireDtrManageIfAdmin, controllers.updateRecord);
  router.post(
    '/:id/recalculate',
    protect,
    requireAdminOrHr,
    requireDtrManageIfAdmin,
    controllers.recalculateRecord
  );
  router.get(
    '/deletions',
    protect,
    requireAdmin,
    requireDtrManageIfAdmin,
    controllers.listDeletions
  );
  router.post(
    '/deletions/:deletionId/restore',
    protect,
    requireAdmin,
    requireDtrManageIfAdmin,
    controllers.restoreRecord
  );
  router.delete('/:id', protect, requireAdmin, requireDtrManageIfAdmin, controllers.deleteRecord);
  router.post(
    '/sync-holidays',
    protect,
    requireAdmin,
    requireDtrManageIfAdmin,
    controllers.syncHolidays
  );
  return router;
}
module.exports = { createDtrRouter };
