const express = require('express');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');

function createAttendanceResetRouter(service, authenticate = authMiddleware) {
  const router = express.Router();
  router.use(authenticate, requireSuperAdmin, (_req, res, next) => {
    res.set('Cache-Control', 'no-store'); next();
  });
  const handle = fn => async (req, res) => {
    try { res.json(await fn(req)); }
    catch (error) {
      if (!error.status) console.error('[attendance reset]', error.message);
      res.status(error.status || 503).json({ error: error.status ? error.message
        : 'Attendance reset could not be completed. Refresh the preview before trying again.' });
    }
  };
  router.get('/employees', handle(req => service.employees(req.query.search)));
  router.post('/preview', handle(req => service.preview(req.body, req.user.id)));
  router.post('/apply', handle(req => service.apply(req.body, req.user.id)));
  return router;
}
module.exports = { createAttendanceResetRouter };
