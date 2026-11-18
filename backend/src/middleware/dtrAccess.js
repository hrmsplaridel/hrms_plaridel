const { pool } = require('../config/db');
const { dtrActionParents, dtrActionFields } = require('../services/dtrActionPermissions');

async function loadDtrAccess(userId, db = pool) {
  const result = await db.query(
    `SELECT COALESCE((SELECT reports_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS reports_allowed,
            COALESCE((SELECT manage_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS manage_allowed,
            COALESCE((SELECT employees_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS employees_allowed,
            COALESCE((SELECT leave_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS leave_allowed,
            COALESCE((SELECT approvals_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS approvals_allowed,
            COALESCE((SELECT locator_allowed FROM dtr_admin_access
                      WHERE admin_user_id = $1::uuid), false) AS locator_allowed,
            ${dtrActionFields.map(field => `COALESCE((SELECT ${field} FROM dtr_admin_access
              WHERE admin_user_id = $1::uuid), false) AS ${field}`).join(', ')}`,
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
  const fields = ['employees_allowed', 'leave_allowed', 'approvals_allowed', 'locator_allowed'];
  if (!fields.includes(feature)) throw new Error(`Unknown DTR feature: ${feature}`);
  return requireDtrAccessIfAdmin(feature);
};

function requireDtrActionIfAdmin(field) {
  if (!Object.hasOwn(dtrActionParents, field)) throw new Error(`Unknown DTR action: ${field}`);
  const check = async (req, res, next) => {
    // Preserve existing HR and reviewer role checks; this is an admin access grant.
    if (req.user?.role !== 'admin') return next();
    try {
      const access = await loadDtrAccess(req.user.id);
      if (access?.[dtrActionParents[field]] !== true || access?.[field] !== true) {
        return res.status(403).json({ error: 'This action is disabled for your account', code: 'DTR_ACTION_DISABLED' });
      }
      return next();
    } catch (error) {
      console.error('[DTR action access]', error);
      return res.status(503).json({ error: 'Action access could not be verified' });
    }
  };
  check.dtrAction = field;
  return check;
}

// Personal credit history remains available; other employees' ledger requires a tool grant.
function requireLeaveLedgerIfAdmin(req, res, next) {
  const target = String(req.query?.user_id || '').trim();
  const all = ['all_users', 'include_all_users'].some(key =>
    ['1', 'true', 'yes'].includes(String(req.query?.[key] || '').trim().toLowerCase()));
  if (!all && (!target || target === req.user?.id)) return next();
  return requireDtrActionIfAdmin('leave_ledger_allowed')(req, res, next);
}

module.exports = {
  loadDtrAccess,
  requireDtrReportsAccess,
  requireDtrManageAccess,
  requireDtrReportsIfAdmin,
  requireDtrManageIfAdmin,
  requireDtrFeatureIfAdmin,
  requireDtrActionIfAdmin,
  requireLeaveLedgerIfAdmin,
  requireAnyDtrAccessIfAdmin,
  requireAnyDtrAccessForList,
};
