const { pool } = require('../config/db');

async function loadDtrAccess(userId, db = pool) {
  const result = await db.query(
    `SELECT COALESCE((SELECT reports_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS reports_allowed,
            COALESCE((SELECT manage_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS manage_allowed,
            COALESCE((SELECT corrections_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS corrections_allowed,
            COALESCE((SELECT employees_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS employees_allowed,
            COALESCE((SELECT leave_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS leave_allowed,
            COALESCE((SELECT approvals_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS approvals_allowed,
            COALESCE((SELECT locator_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS locator_allowed`,
    [userId]
  );
  return result.rows[0];
}

function requireDtrAccess(field) {
  return async (req, res, next) => {
    if (req.user?.role === 'super_admin') return next();
    if (req.user?.role !== 'admin') {
      return res.status(403).json({ error: 'Administrator access required' });
    }
    try {
      const access = await loadDtrAccess(req.user.id);
      if (!access?.[field]) {
        return res.status(403).json({ error: 'DTR access is disabled for your account' });
      }
      next();
    } catch (error) {
      console.error('[DTR access]', error);
      res.status(503).json({ error: 'DTR access could not be verified' });
    }
  };
}

function requireDtrAccessIfAdmin(field) {
  const check = requireDtrAccess(field);
  return (req, res, next) => req.user?.role === 'admin'
    ? check(req, res, next)
    : next();
}

async function requireAnyDtrAccessIfAdmin(req, res, next) {
  if (req.user?.role !== 'admin') return next();
  try {
    const access = await loadDtrAccess(req.user.id);
    if (!access?.reports_allowed && !access?.manage_allowed) {
      return res.status(403).json({ error: 'DTR access is disabled for your account' });
    }
    next();
  } catch (error) {
    console.error('[DTR access]', error);
    res.status(503).json({ error: 'DTR access could not be verified' });
  }
}

function requireAnyDtrAccessForList(req, res, next) {
  if (req.user?.role === 'admin' &&
      String(req.query?.employee_id || '') === String(req.user.id) &&
      !req.query?.employee_ids && !req.query?.department_id) {
    return next();
  }
  return requireAnyDtrAccessIfAdmin(req, res, next);
}

const requireDtrReportsAccess = requireDtrAccess('reports_allowed');
const requireDtrManageAccess = requireDtrAccess('manage_allowed');
const requireDtrReportsIfAdmin = requireDtrAccessIfAdmin('reports_allowed');
const requireDtrManageIfAdmin = requireDtrAccessIfAdmin('manage_allowed');
const requireDtrFeatureIfAdmin = (feature) => {
  const fields = ['corrections_allowed', 'employees_allowed', 'leave_allowed', 'approvals_allowed', 'locator_allowed'];
  if (!fields.includes(feature)) throw new Error(`Unknown DTR feature: ${feature}`);
  return requireDtrAccessIfAdmin(feature);
};

module.exports = {
  loadDtrAccess,
  requireDtrReportsAccess,
  requireDtrManageAccess,
  requireDtrReportsIfAdmin,
  requireDtrManageIfAdmin,
  requireDtrFeatureIfAdmin,
  requireAnyDtrAccessIfAdmin,
  requireAnyDtrAccessForList,
};
