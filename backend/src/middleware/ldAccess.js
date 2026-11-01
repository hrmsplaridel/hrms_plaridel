const { ldAdminAccess } = require('../services/moduleAdminAccess');

async function loadLdAccess(userId, db) {
  return ldAdminAccess.loadAccess(userId, db);
}

function requireLdAccess(field) {
  if (!ldAdminAccess.fields.includes(field)) {
    throw new Error(`Unknown L&D feature: ${field}`);
  }
  return async (req, res, next) => {
    if (req.user?.role === 'super_admin') return next();
    if (req.user?.role !== 'admin') {
      return res.status(403).json({ error: 'Administrator access required' });
    }
    try {
      const access = await loadLdAccess(req.user.id);
      if (!access?.[field]) {
        return res.status(403).json({ error: 'L&D access is disabled for your account' });
      }
      next();
    } catch (error) {
      console.error('[L&D access]', error);
      res.status(503).json({ error: 'L&D access could not be verified' });
    }
  };
}

function requireLdAccessIfAdmin(field) {
  const check = requireLdAccess(field);
  return (req, res, next) =>
    req.user?.role === 'admin' ? check(req, res, next) : next();
}

async function requireAnyLdAccessIfAdmin(req, res, next) {
  if (req.user?.role === 'super_admin') return next();
  if (req.user?.role !== 'admin') return next();
  try {
    const access = await loadLdAccess(req.user.id);
    if (!ldAdminAccess.anyAllowed(access)) {
      return res.status(403).json({ error: 'L&D access is disabled for your account' });
    }
    next();
  } catch (error) {
    console.error('[L&D access]', error);
    res.status(503).json({ error: 'L&D access could not be verified' });
  }
}

module.exports = {
  loadLdAccess,
  requireLdAccess,
  requireLdAccessIfAdmin,
  requireAnyLdAccessIfAdmin,
};
