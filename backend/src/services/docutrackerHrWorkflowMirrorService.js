'use strict';

const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const {
  resolveDepartmentReviewers,
} = require('./departmentReviewerService');
const {
  resolveFinalLeaveReviewerConfiguration,
} = require('./leaveFinalReviewerService');

function normalizeEffectiveDate(value) {
  const date = String(value || todayInHrmsTimezone()).trim();
  const parsed = new Date(`${date}T00:00:00Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
    !Number.isFinite(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== date
  ) {
    const error = new TypeError('effective_date must be a valid YYYY-MM-DD date');
    error.statusCode = 400;
    throw error;
  }
  return date;
}

function reviewerPayload(reviewer, fallbackRole) {
  if (!reviewer) return null;
  return {
    id: reviewer.reviewerId || reviewer.id,
    name: reviewer.reviewerName || reviewer.name || 'Unknown reviewer',
    role: reviewer.reviewerRole || fallbackRole,
    backup_rank: reviewer.backupRank ?? null,
  };
}

function departmentStepSummary(groups) {
  const headCount = groups.filter((group) => group.primary != null).length;
  const backupCount = groups.reduce(
    (total, group) => total + group.backups.length,
    0
  );
  if (headCount === 0 && backupCount === 0) {
    return 'Dynamic by department · No active reviewers';
  }
  return `Dynamic by department · ${headCount} head${headCount === 1 ? '' : 's'} · ${backupCount} backup${backupCount === 1 ? '' : 's'}`;
}

function finalStepSummary(primary, backups) {
  if (!primary && backups.length === 0) return 'No final HR reviewer configured';
  const primaryLabel = primary ? `Primary: ${primary.name}` : 'No primary reviewer';
  return `${primaryLabel} · ${backups.length} backup${backups.length === 1 ? '' : 's'}`;
}

async function listHrWorkflowMirrors(
  db,
  {
    effectiveDate,
    departmentReviewerResolver = resolveDepartmentReviewers,
    finalReviewerResolver = resolveFinalLeaveReviewerConfiguration,
  } = {}
) {
  const date = normalizeEffectiveDate(effectiveDate);
  const departments = await db.query(
    `SELECT id, name
     FROM departments
     WHERE is_active = true
     ORDER BY name, id`
  );

  const departmentGroups = await Promise.all(
    departments.rows.map(async (department) => {
      const reviewers = await departmentReviewerResolver(db, {
        departmentId: department.id,
        effectiveDate: date,
      });
      return {
        scope_id: department.id,
        scope_name: department.name,
        primary: reviewerPayload(reviewers.primary, 'primary'),
        backups: (reviewers.backups || [])
          .map((reviewer) => reviewerPayload(reviewer, 'backup'))
          .filter(Boolean),
      };
    })
  );

  const finalReviewers = await finalReviewerResolver(db, date);
  const finalPrimary = reviewerPayload(finalReviewers.primary, 'primary');
  const finalBackups = (finalReviewers.backups || [])
    .map((reviewer) => reviewerPayload(reviewer, 'backup'))
    .filter(Boolean);
  const finalGroup = {
    scope_id: null,
    scope_name: 'Office-wide',
    primary: finalPrimary,
    backups: finalBackups,
  };

  const configured=await db.query(`SELECT 'leave' AS module,t.id::text AS type_id,t.display_name AS type_name,
      w.name,w.current_version,v.steps,v.employment_types,w.id::text AS workflow_id
    FROM leave_types t JOIN approval_workflows w ON w.id=t.approval_workflow_id
    JOIN approval_workflow_versions v ON v.workflow_id=w.id AND v.version=w.current_version
    WHERE t.is_active=true
    UNION ALL
    SELECT 'locator',t.id::text,t.label,w.name,w.current_version,v.steps,v.employment_types,w.id::text
    FROM locator_request_types t JOIN approval_workflows w ON w.id=t.approval_workflow_id
    JOIN approval_workflow_versions v ON v.workflow_id=w.id AND v.version=w.current_version
    WHERE t.is_active=true ORDER BY module,type_name`);
  let mayorGroup=null;
  const engine=require('./approvalWorkflows');
  if(configured.rows.some(w=>w.steps.some(s=>['mayor','manual_mayor'].includes(engine.stepKind(s))))) {
    const mayor=await require('./officialSignatoryService').resolveActiveMayor(db,date);
    mayorGroup={scope_id:null,scope_name:'Municipal Mayor',primary:mayor?{id:mayor.employee_id,name:mayor.name,role:'primary'}:null,backups:[]};
  }
  const selectedIds=[...new Set(configured.rows.flatMap(w=>w.steps.flatMap(s=>typeof s==='object'?s.user_ids||[]:[])))];
  const selected=selectedIds.length?(await db.query('SELECT id,full_name AS name FROM users WHERE id=ANY($1::uuid[]) AND is_active=true',[selectedIds])).rows:[];
  function mirrorStep(step,index) {
    const source=typeof step==='object'?step.assignee_source:{department:'submitter_department_reviewers',hr:'final_hr_reviewers',mayor:'active_mayor',manual_mayor:'manual_mayor'}[step];
    let groups=source==='submitter_department_reviewers'?departmentGroups:source==='department_reviewers'?departmentGroups.filter(g=>g.scope_id===step.department_id):source==='final_hr_reviewers'?[finalGroup]:mayorGroup?[mayorGroup]:[];
    let summary=source==='submitter_department_reviewers' || source==='department_reviewers'?departmentStepSummary(groups):source==='final_hr_reviewers'?finalStepSummary(finalPrimary,finalBackups):source==='manual_mayor'?'Signs the printed form manually':mayorGroup?.primary?.name||'No eligible active Mayor';
    if(source==='specific_users') {
      const reviewers=step.user_ids.map(id=>selected.find(r=>String(r.id)===String(id))||null);
      const primary=reviewers[0],backups=reviewers.slice(1).filter(Boolean).map((r,i)=>({...r,backup_rank:i+1}));
      groups=[{scope_id:null,scope_name:'Selected reviewers',primary,backups}];
      summary=finalStepSummary(primary,backups);
    }
    return {step_order:index+1,label:engine.stepLabel(step),assignee_summary:summary,groups};
  }
  const workflowsByVersion = new Map();
  for (const workflow of configured.rows) {
    const key = workflow.workflow_id
      ? `workflow:${workflow.workflow_id}:v${workflow.current_version}`
      : `${workflow.module}:${workflow.type_id}`;
    let mirror = workflowsByVersion.get(key);
    if (!mirror) {
      mirror = {
        key, title: `${workflow.name} v${workflow.current_version}`,
        source_label: 'Synced from DTR', effective_date: date, system_managed: true,
        employment_types: workflow.employment_types,
        steps: workflow.steps.map(mirrorStep), used_by: [],
      };
      workflowsByVersion.set(key, mirror);
    }
    if (!mirror.used_by.some(type => type.module === workflow.module && type.type_id === workflow.type_id)) {
      mirror.used_by.push({ module: workflow.module, type_id: workflow.type_id, type_name: workflow.type_name });
    }
  }
  const configuredMirrors = [...workflowsByVersion.values()]
    .sort((a, b) => a.title.localeCompare(b.title) || a.key.localeCompare(b.key));

  return {
    effective_date: date,
    reviewer_assignments: {department_groups:departmentGroups,final_group:finalGroup},
    workflows: configuredMirrors,
  };
}

module.exports = {
  listHrWorkflowMirrors,
  normalizeEffectiveDate,
};
