/**
 * Require a specific role. Must be used AFTER authMiddleware.
 * requireAdmin: only admin
 * requireRole(role): only that role
 */
function requireAdmin(req, res, next) {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access required' });
  }
  next();
}

/** Admin, HR, or supervisor (e.g. for approving overtime/leave). */
function requireAdminOrSupervisor(req, res, next) {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'hr' && role !== 'supervisor') {
    return res.status(403).json({ error: 'Admin, HR, or supervisor access required' });
  }
  next();
}

function requireRole(role) {
  return (req, res, next) => {
    if (req.user?.role !== role) {
      return res.status(403).json({ error: `Role '${role}' required` });
    }
    next();
  };
}

module.exports = { requireAdmin, requireAdminOrSupervisor, requireRole };
