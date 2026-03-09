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

function requireRole(role) {
  return (req, res, next) => {
    if (req.user?.role !== role) {
      return res.status(403).json({ error: `Role '${role}' required` });
    }
    next();
  };
}

module.exports = { requireAdmin, requireRole };
