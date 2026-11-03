'use strict';

const POLICIES = new Set(['mayor', 'blank', 'actual_reviewer']);
const blankOfficial = () => ({ id: null, employee_id: null, name: '', position_title: '' });

function normalizePrintPolicy(value = 'mayor') {
  if (!POLICIES.has(value)) {
    throw Object.assign(new Error('Choose a valid printed signatory rule.'), { statusCode: 400 });
  }
  return value;
}

function requestPrintPolicy(row) {
  return row?.workflow_snapshot?.self_filing_signatory_policy ?? 'mayor';
}

function officialStep(snapshot, role) {
  const steps = snapshot?.steps || [];
  const source = step => typeof step === 'string' ? step : step?.assignee_source;
  const matches = role === 'department'
    ? ['department', 'submitter_department_reviewers', 'department_reviewers']
    : ['hr', 'final_hr_reviewers'];
  const explicit = role === 'department'
    ? steps.findIndex(step => matches.includes(source(step)))
    : steps.findLastIndex(step => matches.includes(source(step)));
  if (explicit >= 0) return explicit;
  // Custom user steps have no semantic role: use the first recommendation
  // and last electronic HR step, consistent with shared form placement.
  const custom = steps.map((step, index) => source(step) === 'specific_users' ? index : -1).filter(index => index >= 0);
  return role === 'department' ? custom[0] ?? -1 : custom.at(-1) ?? -1;
}

async function workflowPrimaryApplicant(db, row, step, resolvers = {}) {
  const applicant = row.employee_id || row.user_id;
  if (!applicant || !step) return false;
  const source = typeof step === 'string' ? step : step.assignee_source;
  let primary;
  if (source === 'specific_users') {
    primary = step.user_ids?.[0];
  } else if (['department', 'submitter_department_reviewers', 'department_reviewers'].includes(source)) {
    const departmentId = source === 'department_reviewers' ? step.department_id : row.department_id || row.review_department_id;
    if (!departmentId) return false;
    const resolve = resolvers.resolveDepartmentReviewers || require('./departmentReviewerService').resolveDepartmentReviewers;
    primary = (await resolve(db, {
      departmentId,
      effectiveDate: row.slip_date_text || row.submitted_on || require('../utils/dateRangeParser').todayInHrmsTimezone(),
    })).primary?.reviewerId;
  } else if (['hr', 'final_hr_reviewers'].includes(source)) {
    const resolve = resolvers.resolveFinalLeaveReviewerConfiguration || require('./leaveFinalReviewerService').resolveFinalLeaveReviewerConfiguration;
    primary = (await resolve(db)).primary?.id;
  }
  return Boolean(primary && String(primary) === String(applicant));
}

async function selfFilingOfficial(db, row, role, mayor, stepIndex = null) {
  const policy = requestPrintPolicy(row);
  if (policy === 'mayor') return mayor || blankOfficial();
  if (policy !== 'actual_reviewer') return blankOfficial();
  const snapshot = row?.workflow_snapshot;
  const step = stepIndex ?? officialStep(snapshot, role);
  const decision = snapshot?.decisions?.find(item => item.step === step && item.action === 'approve');
  const applicant = row.employee_id || row.user_id;
  if (!decision?.actor_id || String(decision.actor_id) === String(applicant)) return blankOfficial();
  const profile = decision.reviewer || await require('./approvalWorkflows').reviewerProfile(db, decision.actor_id);
  return { ...profile, id: decision.actor_id, employee_id: decision.actor_id,
    name: decision.reviewer?.name || decision.signature?.signer_name_snapshot || profile?.name || '', position_title: profile?.position_title || '' };
}

module.exports = { normalizePrintPolicy, requestPrintPolicy, selfFilingOfficial, workflowPrimaryApplicant };
