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

function mirroredWorkflow({ key, title, effectiveDate, departmentGroups, finalGroup }) {
  return {
    key,
    title,
    source_label: 'Synced from DTR',
    effective_date: effectiveDate,
    system_managed: true,
    steps: [
      {
        step_order: 1,
        label: 'Department Review',
        assignee_summary: departmentStepSummary(departmentGroups),
        groups: departmentGroups,
      },
      {
        step_order: 2,
        label: 'Final HR Review',
        assignee_summary: finalStepSummary(finalGroup.primary, finalGroup.backups),
        groups: [finalGroup],
      },
    ],
  };
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

  return {
    effective_date: date,
    workflows: [
      mirroredWorkflow({
        key: 'leave',
        title: 'Leave Request',
        effectiveDate: date,
        departmentGroups,
        finalGroup,
      }),
      mirroredWorkflow({
        key: 'locator',
        title: 'Locator Slip',
        effectiveDate: date,
        departmentGroups,
        finalGroup,
      }),
    ],
  };
}

module.exports = {
  listHrWorkflowMirrors,
  normalizeEffectiveDate,
};
