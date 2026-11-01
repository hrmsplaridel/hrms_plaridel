const { rspAdminAccess } = require('../services/moduleAdminAccess');

async function loadRspAccess(userId, db) {
  return rspAdminAccess.loadAccess(userId, db);
}

function requireRspAccess(field) {
  if (!rspAdminAccess.fields.includes(field)) {
    throw new Error(`Unknown RSP feature: ${field}`);
  }
  return async (req, res, next) => {
    if (req.user?.role === 'super_admin') return next();
    if (req.user?.role !== 'admin') {
      return res.status(403).json({ error: 'Administrator access required' });
    }
    try {
      const access = await loadRspAccess(req.user.id);
      if (!access?.[field]) {
        return res.status(403).json({ error: 'RSP access is disabled for your account' });
      }
      next();
    } catch (error) {
      console.error('[RSP access]', error);
      res.status(503).json({ error: 'RSP access could not be verified' });
    }
  };
}

function requireRspAccessIfAdmin(field) {
  const check = requireRspAccess(field);
  return (req, res, next) =>
    req.user?.role === 'admin' ? check(req, res, next) : next();
}

async function requireAnyRspAccessIfAdmin(req, res, next) {
  if (req.user?.role === 'super_admin') return next();
  if (req.user?.role !== 'admin') return next();
  try {
    const access = await loadRspAccess(req.user.id);
    if (!rspAdminAccess.anyAllowed(access)) {
      return res.status(403).json({ error: 'RSP access is disabled for your account' });
    }
    next();
  } catch (error) {
    console.error('[RSP access]', error);
    res.status(503).json({ error: 'RSP access could not be verified' });
  }
}

const {
  RSP_FORM_FIELDS,
  LD_FORM_FIELDS,
  RSP_RECRUITMENT_FIELDS,
} = require('../services/moduleAdminAccess');

async function requireAnyRspRecruitmentIfAdmin(req, res, next) {
  if (req.user?.role === 'super_admin') return next();
  if (req.user?.role !== 'admin') return next();
  try {
    const access = await loadRspAccess(req.user.id);
    if (
      access?.recruitment_allowed === true ||
      RSP_RECRUITMENT_FIELDS.some((field) => access?.[field] === true)
    ) {
      return next();
    }
    return res
      .status(403)
      .json({ error: 'RSP Recruitment Management access is disabled for your account' });
  } catch (error) {
    console.error('[RSP recruitment access]', error);
    res.status(503).json({ error: 'RSP access could not be verified' });
  }
}

function _anyFormAllowed(access, fields, parentKey) {
  if (access?.[parentKey] === true) return true;
  return fields.some((field) => access?.[field] === true);
}

/** Shared RSP/L&D forms table — allow if either module has any Forms permission. */
function requireRspOrLdFormsIfAdmin(loadLdAccess) {
  return async (req, res, next) => {
    if (req.user?.role === 'super_admin') return next();
    if (req.user?.role !== 'admin') return next();
    try {
      const rsp = await loadRspAccess(req.user.id);
      if (_anyFormAllowed(rsp, RSP_FORM_FIELDS, 'forms_allowed')) return next();
      const ld = await loadLdAccess(req.user.id);
      if (_anyFormAllowed(ld, LD_FORM_FIELDS, 'forms_allowed')) return next();
      return res.status(403).json({ error: 'Forms access is disabled for your account' });
    } catch (error) {
      console.error('[RSP/L&D forms access]', error);
      res.status(503).json({ error: 'Forms access could not be verified' });
    }
  };
}

module.exports = {
  loadRspAccess,
  requireRspAccess,
  requireRspAccessIfAdmin,
  requireAnyRspAccessIfAdmin,
  requireAnyRspRecruitmentIfAdmin,
  requireRspOrLdFormsIfAdmin,
};
