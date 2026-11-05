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
  RSP_RECRUITMENT_FIELDS,
} = require('../services/moduleAdminAccess');

/** Match the server action to the same tab/form controls shown in Manage Access. */
async function requireRspApplicationAccessIfAdmin(req, res, next) {
  if (req.user?.role !== 'admin') return next();
  const path = String(req.route?.path || req.path || '');
  let fields = ['applications_allowed'];
  if (path === '/') {
    fields = RSP_RECRUITMENT_FIELDS;
  } else if (path === '/tat-applicant-choices' || path === '/final-hiring/sources') {
    fields = ['applications_allowed', 'final_requirements_allowed', 'form_turn_around_time_allowed'];
  } else if (path.startsWith('/exam-results')) {
    fields = ['exam_results_allowed'];
  } else if (/\/(?:final-interview(?:-outcome)?|orientation(?:-attendance)?)$/.test(path)) {
    fields = ['scheduling_allowed'];
  } else if (path.includes('/final-requirements') || /\/(?:hr-account-setup-monitoring|hired-link|send-credentials|send-hire-email|csc-approval)$/.test(path)) {
    fields = ['final_requirements_allowed'];
  } else if (path.includes('/hr-forms/')) {
    const form = path.includes('/applicants-profile/') ? 'form_applicants_profile_allowed'
      : path.includes('/selection-lineup/') ? 'form_selection_lineup_allowed'
      : path.includes('/turn-around-time/') ? 'form_turn_around_time_allowed' : null;
    fields = ['applications_allowed', 'final_requirements_allowed', ...(form ? [form] : [])];
  } else if (/\/(?:required-form|work-experience|applicants-profile|selection-lineup)(?:\/|$)/.test(path)) {
    fields = ['applications_allowed', 'final_requirements_allowed'];
  }
  try {
    const access = await loadRspAccess(req.user.id);
    if (!fields.some(field => access?.[field] === true)) {
      return res.status(403).json({ error: 'This RSP feature is disabled for your account' });
    }
    return next();
  } catch (error) {
    console.error('[RSP application access]', error);
    return res.status(503).json({ error: 'RSP access could not be verified' });
  }
}

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

const FORM_PERMISSIONS = Object.freeze({
  bi_form_entries: ['rsp', 'form_bi_allowed'],
  applicants_profile_entries: ['rsp', 'form_applicants_profile_allowed'],
  selection_lineup_entries: ['rsp', 'form_selection_lineup_allowed'],
  computation_of_points_entries: ['rsp', 'form_computation_of_points_allowed'],
  work_experience_sheet_entries: ['rsp', 'form_work_experience_allowed'],
  turn_around_time_entries: ['rsp', 'form_turn_around_time_allowed'],
  ojt_work_immersion_evaluation_entries: ['rsp', 'form_ojt_allowed'],
  training_need_analysis_entries: ['ld', 'form_tna_allowed'],
  action_brainstorming_coaching_entries: ['ld', 'form_action_brainstorming_allowed'],
  idp_entries: ['ld', 'form_idp_allowed'],
  learning_application_plan_entries: ['ld', 'form_lap_allowed'],
  // Archived form types without a separate control retain their module gate.
  performance_evaluation_entries: ['rsp', 'forms_allowed'],
  comparative_assessment_entries: ['rsp', 'forms_allowed'],
  promotion_certification_entries: ['rsp', 'forms_allowed'],
});

/** Authorize the requested form, including recycle, restore and edit-history. */
function requireRspOrLdFormsIfAdmin(loadLdAccess) {
  return async (req, res, next) => {
    if (req.user?.role === 'super_admin') return next();
    if (req.user?.role !== 'admin') return next();
    try {
      const permission = FORM_PERMISSIONS[req.params?.table];
      if (!permission) return res.status(400).json({ error: 'Unknown table' });
      const [module, field] = permission;
      const access = module === 'rsp'
        ? await loadRspAccess(req.user.id)
        : await loadLdAccess(req.user.id);
      if (access?.[field] === true) return next();
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
  requireRspApplicationAccessIfAdmin,
};
