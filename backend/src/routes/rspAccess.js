const express = require('express');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');
const { rspAdminAccess } = require('../services/moduleAdminAccess');

const router = express.Router();

router.get('/me', authMiddleware, async (req, res) => {
  if (req.user?.role !== 'admin') {
    return res.json({ ...rspAdminAccess.falseDefaults });
  }
  try {
    res.json(await rspAdminAccess.loadAccess(req.user.id));
  } catch (error) {
    console.error('[RSP access GET /me]', error);
    res.status(503).json({ error: 'RSP access could not be verified' });
  }
});

router.get('/', authMiddleware, requireSuperAdmin, async (_req, res) => {
  try {
    res.json({ admins: await rspAdminAccess.listAdmins() });
  } catch (error) {
    console.error('[RSP access GET]', error);
    res.status(500).json({ error: 'Failed to load RSP access' });
  }
});

router.put('/:adminId', authMiddleware, requireSuperAdmin, async (req, res) => {
  const result = await rspAdminAccess.updateAccess({
    adminId: req.params.adminId,
    body: req.body || {},
    actorUserId: req.user.id,
  });
  res.status(result.status).json(result.body);
});

module.exports = router;
