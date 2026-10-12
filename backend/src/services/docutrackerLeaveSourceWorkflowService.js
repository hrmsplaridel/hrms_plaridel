'use strict';

const { mapSourceStatusToDocuTracker } = require('./docutrackerWorkflowService');
const {
  resolveFinalLeaveReviewerConfiguration,
} = require('./leaveFinalReviewerService');

/**
 * Read-only view of a DTR leave request's two-stage workflow (the same
 * Department Review → Final HR Review stages DocuTracker mirrors from DTR)
 * plus its persisted leave_request_history, for the linked-leave detail page.
 * DTR stays the source of truth; nothing here changes leave state.
 */

const DEPARTMENT_DECISIONS = new Set([
  'department_head_approved',
  'department_head_rejected',
  'department_head_returned',
]);

const FINAL_STAGE_STATUSES = new Set(['pending_hr', 'pending']);

function historyStatus(leaveStatus) {
  const status = String(leaveStatus || '').trim().toLowerCase();
  if (!status) return null;
  if (status === 'draft') return 'draft';
  return mapSourceStatusToDocuTracker('dtr', status);
}

function indicator(kind, label) {
  return { kind, label };
}

function lastAction(history, predicate) {
  let found = null;
  for (const entry of history) {
    if (predicate(entry)) found = entry;
  }
  return found;
}

function departmentIndicator(status, history) {
  const decision = lastAction(history, (h) => DEPARTMENT_DECISIONS.has(h.action));
  if (decision) {
    return {
      department_head_approved: indicator('approved', 'APPROVED'),
      department_head_rejected: indicator('rejected', 'REJECTED'),
      department_head_returned: indicator('returned', 'RETURNED'),
    }[decision.action];
  }
  if (status === 'pending_department_head') return indicator('current', 'CURRENT');
  if (status === 'cancelled') {
    const cancel = lastAction(history, (h) => h.action === 'cancelled');
    if (cancel?.from_status === 'pending_department_head') {
      return indicator('cancelled', 'CANCELLED');
    }
  }
  const reachedFinal = history.some((h) => FINAL_STAGE_STATUSES.has(h.to_status));
  if (reachedFinal) return indicator('upcoming', 'NOT REQUIRED');
  return indicator('upcoming', 'WAITING');
}

function finalIndicator(status, history) {
  if (status === 'approved') return indicator('approved', 'APPROVED');
  if (status === 'rejected_by_hr' || status === 'rejected') {
    return indicator('rejected', 'REJECTED');
  }
  if (FINAL_STAGE_STATUSES.has(status)) return indicator('current', 'CURRENT');
  if (status === 'returned') {
    const returned = lastAction(history, (h) => h.to_status === 'returned');
    if (returned && FINAL_STAGE_STATUSES.has(returned.from_status)) {
      return indicator('returned', 'RETURNED');
    }
  }
  if (status === 'cancelled') {
    const cancel = lastAction(history, (h) => h.action === 'cancelled');
    if (cancel && FINAL_STAGE_STATUSES.has(cancel.from_status)) {
      return indicator('cancelled', 'CANCELLED');
    }
  }
  return indicator('upcoming', 'WAITING');
}

/** Step indicators for a leave status + ordered history rows. */
function leaveStepIndicators(status, history) {
  const normalized = String(status || '').trim().toLowerCase();
  return {
    department: departmentIndicator(normalized, history),
    final: finalIndicator(normalized, history),
  };
}

function currentStepFor(status) {
  if (status === 'pending_department_head') return 1;
  if (FINAL_STAGE_STATUSES.has(status) || status === 'approved') return 2;
  return null;
}

function finalDeciderId(history) {
  const decision = lastAction(
    history,
    (h) =>
      FINAL_STAGE_STATUSES.has(h.from_status) &&
      ['approved', 'rejected', 'rejected_by_hr', 'returned'].includes(h.to_status)
  );
  return decision?.acted_by || null;
}

/** Mirrors the DocuTracker leave list relationship rule. */
async function canViewLeaveSource(db, user, leaveRequestId) {
  const role = String(user?.role || '').trim().toLowerCase();
  if (role === 'admin' || role === 'hr') {
    const exists = await db.query(
      'SELECT 1 FROM leave_requests WHERE id = $1::uuid LIMIT 1',
      [leaveRequestId]
    );
    return exists.rowCount > 0;
  }
  const result = await db.query(
    `SELECT 1
     FROM leave_requests l
     WHERE l.id = $1::uuid
       AND (
         l.user_id = $2::uuid
         OR l.employee_id = $2::uuid
         OR l.assigned_department_head_id = $2::uuid
         OR EXISTS (
           SELECT 1 FROM leave_request_department_reviewers lrr
           WHERE lrr.leave_request_id = l.id AND lrr.reviewer_id = $2::uuid
         )
         OR EXISTS (
           SELECT 1 FROM leave_request_history lrh
           WHERE lrh.leave_request_id = l.id
             AND lrh.acted_by = $2::uuid
             AND lrh.action IN (
               'department_head_approved',
               'department_head_rejected',
               'department_head_returned'
             )
         )
       )
     LIMIT 1`,
    [leaveRequestId, user?.id]
  );
  return result.rowCount > 0;
}

async function getLeaveSourceWorkflow(
  db,
  user,
  leaveRequestId,
  { finalReviewerResolver = resolveFinalLeaveReviewerConfiguration } = {}
) {
  const id = String(leaveRequestId || '').trim();
  if (!id || !user?.id) return null;
  if (!(await canViewLeaveSource(db, user, id))) return null;

  const leave = await db.query(
    `SELECT l.status,
            l.assigned_department_head_id::text AS assigned_department_head_id,
            head.full_name AS assigned_department_head_name
     FROM leave_requests l
     LEFT JOIN users head ON head.id = l.assigned_department_head_id
     WHERE l.id = $1::uuid`,
    [id]
  );
  if (leave.rowCount === 0) return null;
  const { status, assigned_department_head_id, assigned_department_head_name } =
    leave.rows[0];

  const historyResult = await db.query(
    `SELECT h.id::text AS id,
            h.action,
            h.from_status,
            h.to_status,
            h.acted_by::text AS acted_by,
            h.acted_at,
            h.remarks,
            actor.full_name AS actor_name
     FROM leave_request_history h
     LEFT JOIN users actor ON actor.id = h.acted_by
     WHERE h.leave_request_id = $1::uuid
     ORDER BY h.acted_at ASC, h.id ASC`,
    [id]
  );
  const history = historyResult.rows;

  const departmentReviewers = await db.query(
    `SELECT reviewer_id::text AS id,
            reviewer_name_snapshot AS name,
            reviewer_role AS role,
            backup_rank
     FROM leave_request_department_reviewers
     WHERE leave_request_id = $1::uuid
     ORDER BY (reviewer_role = 'primary') DESC, backup_rank ASC NULLS LAST, created_at ASC`,
    [id]
  );
  let stepOneReviewers = departmentReviewers.rows;
  if (stepOneReviewers.length === 0 && assigned_department_head_id) {
    stepOneReviewers = [
      {
        id: assigned_department_head_id,
        name: assigned_department_head_name || 'Department head',
        role: 'primary',
        backup_rank: null,
      },
    ];
  }

  let stepTwoReviewers;
  const deciderId = finalDeciderId(history);
  if (deciderId) {
    const decider = history.find((h) => h.acted_by === deciderId);
    stepTwoReviewers = [
      { id: deciderId, name: decider?.actor_name || 'HR reviewer', role: 'primary', backup_rank: null },
    ];
  } else {
    const configured = await finalReviewerResolver(db);
    stepTwoReviewers = [
      ...(configured.primary ? [{ ...configured.primary, role: 'primary' }] : []),
      ...(configured.backups || []).map((reviewer, index) => ({
        ...reviewer,
        role: 'backup',
        backup_rank: reviewer.backup_rank ?? index + 1,
      })),
    ].map((reviewer) => ({
      id: reviewer.id ? String(reviewer.id) : null,
      name: reviewer.name || reviewer.full_name || 'HR reviewer',
      role: reviewer.role,
      backup_rank: reviewer.role === 'backup' ? reviewer.backup_rank : null,
    }));
  }

  const indicators = leaveStepIndicators(status, history);
  const documentId = `source:dtr:${id}`;
  return {
    source_status: status,
    status: mapSourceStatusToDocuTracker('dtr', status),
    current_step: currentStepFor(String(status || '').toLowerCase()),
    steps: [
      {
        step_order: 1,
        label: 'Department Review',
        indicator: indicators.department,
        reviewers: stepOneReviewers,
      },
      {
        step_order: 2,
        label: 'Final HR Review',
        indicator: indicators.final,
        reviewers: stepTwoReviewers,
      },
    ],
    history: history.map((h) => {
      const from = historyStatus(h.from_status);
      const to = historyStatus(h.to_status);
      return {
        id: h.id,
        document_id: documentId,
        action: h.action,
        actor_id: h.acted_by,
        actor_name: h.actor_name,
        from_status: from === to ? null : from,
        to_status: to,
        remarks: h.remarks,
        created_at: h.acted_at instanceof Date ? h.acted_at.toISOString() : h.acted_at,
      };
    }),
  };
}

module.exports = {
  canViewLeaveSource,
  getLeaveSourceWorkflow,
  leaveStepIndicators,
};
