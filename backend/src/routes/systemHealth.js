'use strict';
const express = require('express');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');

function createSystemHealthRouter(monitor, authenticate = authMiddleware) {
  const router = express.Router();
  router.get('/', authenticate, requireSuperAdmin, (req, res) => {
    res.set('Cache-Control', 'no-store');
    const hours = req.query.hours === undefined ? 24 : Number(req.query.hours);
    if (![1, 24, 168].includes(hours)) {
      return res.status(400).json({ error: 'hours must be 1, 24, or 168' });
    }
    return res.json(monitor.snapshot(hours));
  });
  return router;
}

module.exports = { createSystemHealthRouter };
