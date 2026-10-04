const express = require('express');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');

function createSystemBackupsRouter(service, authenticate = authMiddleware) {
  const router = express.Router();
  router.use(authenticate, requireSuperAdmin, (_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
  const handle = fn => async (req, res) => {
    try { await fn(req, res); }
    catch (error) {
      res.status(error.status || 503).json({ error: error.status ? error.message : 'Backup service unavailable. Check server backup storage and database connectivity.' });
    }
  };
  router.get('/', handle(async (_req, res) => res.json(await service.snapshot())));
  router.put('/settings', handle(async (req, res) => res.json(await service.configure(req.body, req.user.id))));
  router.post('/', handle(async (req, res) => res.status(202).json(await service.request('manual', req.user.id))));
  return router;
}
module.exports = { createSystemBackupsRouter };
