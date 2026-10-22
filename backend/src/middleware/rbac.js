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

function requireSuperAdmin(req, res, next) {
  if (req.user?.role !== 'super_admin') {
    return res.status(403).json({ error: 'Super-admin access required' });
  }
  next();
}

function requireAdminOrSuperAdmin(req, res, next) {
  if (req.user?.role !== 'admin' && req.user?.role !== 'super_admin') {
    return res.status(403).json({ error: 'Administrator access required' });
  }
  next();
}

/** Municipal Mayor only (final decisions / leave & DocuTracker signatory). */
function requireMayor(req, res, next) {
  if (req.user?.role !== 'mayor') {
    return res.status(403).json({ error: 'Mayor access required' });
  }
  next();
}

/** Mayor's Office Staff only (intake and operational processing). */
function requireMayorOfficeStaff(req, res, next) {
  if (req.user?.role !== 'mayor_office_staff') {
    return res.status(403).json({ error: "Mayor's Office Staff access required" });
  }
  next();
}

/** Either Municipal Mayor or Mayor's Office Staff (read / shared endorsement access). */
function requireMayorEndorsementAccess(req, res, next) {
  const role = String(req.user?.role || '').toLowerCase();
  if (role !== 'mayor' && role !== 'mayor_office_staff') {
    return res.status(403).json({ error: "Mayor's Office access required" });
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

/** Admin or HR (for leave approval and other HR functions). */
function requireAdminOrHr(req, res, next) {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'hr') {
    return res.status(403).json({ error: 'Admin or HR access required' });
  }
  next();
}

module.exports = {
  requireAdmin,
  requireSuperAdmin,
  requireAdminOrSuperAdmin,
  requireMayor,
  requireMayorOfficeStaff,
  requireMayorEndorsementAccess,
  requireAdminOrHr,
  requireAdminOrSupervisor,
  requireRole,
};
