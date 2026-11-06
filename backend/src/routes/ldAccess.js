const express = require('express');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');
const { ldAdminAccess } = require('../services/moduleAdminAccess');

const router = express.Router();

router.get('/me', authMiddleware, async (req, res) => {
  if (req.user?.role !== 'admin') {
    return res.json({ ...ldAdminAccess.falseDefaults });
  }
  try {
    res.json(await ldAdminAccess.loadAccess(req.user.id));
  } catch (error) {
    console.error('[L&D access GET /me]', error);
    res.status(503).json({ error: 'L&D access could not be verified' });
  }
});

router.get('/', authMiddleware, requireSuperAdmin, async (_req, res) => {
  try {
    res.json({ admins: await ldAdminAccess.listAdmins() });
  } catch (error) {
    console.error('[L&D access GET]', error);
    res.status(500).json({ error: 'Failed to load L&D access' });
  }
});

router.put('/:adminId', authMiddleware, requireSuperAdmin, async (req, res) => {
  const result = await ldAdminAccess.updateAccess({
    adminId: req.params.adminId,
    body: req.body || {},
    actorUserId: req.user.id,
  });
  res.status(result.status).json(result.body);
});

module.exports = router;
