'use strict';
const express = require('express');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');

function createSystemHealthRouter(monitor, authenticate = authMiddleware, backups = null) {
  const router = express.Router();
  router.get('/', authenticate, requireSuperAdmin, async (req, res) => {
    res.set('Cache-Control', 'no-store');
    const hours = req.query.hours === undefined ? 24 : Number(req.query.hours);
    if (![1, 24, 168].includes(hours)) {
      return res.status(400).json({ error: 'hours must be 1, 24, or 168' });
    }
    const result = monitor.snapshot(hours);
    if (backups) {
      try {
        const { health, lastSuccess, settings } = await backups.snapshot();
        result.backup = { health, lastSuccessAt: lastSuccess?.finishedAt || null, scheduled: settings.enabled };
      } catch (_) { result.backup = { health: 'unavailable', lastSuccessAt: null }; }
    }
    return res.json(result);
  });
  return router;
}

module.exports = { createSystemHealthRouter };
