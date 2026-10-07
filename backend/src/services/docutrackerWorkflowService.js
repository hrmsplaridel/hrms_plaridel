const { normalizeStatus, mapDocumentRow } = require('./docutrackerDocumentMapper');
const { sameEntityId } = require('../utils/sameEntityId');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { resolveActiveMayor } = require('./officialSignatoryService');
const { GENERAL_PERMISSION_ACTIONS } = require('./docutrackerSystemAccessActions');
const { excludeMayorIntakeStubSql } = require('../utils/mayorIntakeStub');
const {
  getEmployeeDepartmentForDate,
  resolveDepartmentReviewers,
} = require('./departmentReviewerService');

const DYNAMIC_DEPARTMENT_ASSIGNEE_SOURCES = new Set([
  'department_reviewers',
  'submitter_department_reviewers',
]);

function isDynamicDepartmentAssigneeSource(source) {
  return DYNAMIC_DEPARTMENT_ASSIGNEE_SOURCES.has(
    String(source || '').trim().toLowerCase()
  );
}

const VALID_STATUSES = new Set([
  'draft',
  'pending',
  'in_review',
  'approved',
  'rejected',
  'returned',
  'forwarded', // legacy DB values; normalizeStatus maps to in_review
  'overdue',
  'escalated',
  'cancelled',
]);

const TERMINAL_STATUSES = new Set(['approved', 'rejected', 'cancelled']);
const DOC_ACTIONS = new Set([
  'view',
  'create',
  'create_draft',
  'edit_own_draft',
  'delete_own_draft',
  'edit',
  'download',
  'delete',
  'return',
  'forward',
  'approve',
  'reject',
  'submit',
]);
// Overdue is still "at holder / active review" — same holder actions as in_review / escalated.
const TRANSITION_ALLOWED_FROM = {
  submit: new Set(['draft', 'pending']),
  forward: new Set(['in_review', 'returned', 'escalated', 'overdue']),
  approve: new Set(['in_review', 'returned', 'escalated', 'overdue']),
  reject: new Set(['in_review', 'returned', 'escalated', 'overdue']),
  return: new Set(['in_review', 'returned', 'escalated', 'overdue']),
};

const RECOVERABLE_WORKFLOW_STATUSES = new Set([
  'in_review',
  'returned',
  'escalated',
  'overdue',
]);

let usersOfficeColumnReady = null;
let docutrackerDocumentFilesTableReady = null;

async function hasUsersOfficeIdColumn(client) {
  if (usersOfficeColumnReady !== null) return usersOfficeColumnReady;
  const result = await client.query(
    `SELECT 1
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'users'
       AND column_name = 'office_id'
     LIMIT 1`
  );
  usersOfficeColumnReady = result.rowCount > 0;
  return usersOfficeColumnReady;
}

async function hasDocutrackerDocumentFilesTable(client) {
  if (docutrackerDocumentFilesTableReady !== null) return docutrackerDocumentFilesTableReady;
  const result = await client.query(
    `SELECT 1
     FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_name = 'docutracker_document_files'
     LIMIT 1`
  );
  docutrackerDocumentFilesTableReady = result.rowCount > 0;
  return docutrackerDocumentFilesTableReady;
}

async function recordInitialDocumentFile(client, { documentId, fileName, filePath, uploadedBy }) {
  if (!documentId || !fileName || !filePath) return;
  if (!(await hasDocutrackerDocumentFilesTable(client))) return;
  await client.query(
    `INSERT INTO docutracker_document_files
       (document_id, file_name, file_path, version, uploaded_by, is_current)
     VALUES ($1, $2, $3, 1, $4, true)
     ON CONFLICT (document_id, file_name, version)
     DO UPDATE SET
       file_path = EXCLUDED.file_path,
       uploaded_by = COALESCE(EXCLUDED.uploaded_by, docutracker_document_files.uploaded_by),
       is_current = true`,
    [documentId, fileName, filePath, uploadedBy || null]
  );
}

/**
 * Next step owned by the RSP / L&D source module. Only admins act on these
 * records (RSP applications and L&D report review are admin-only routes);
 * DocuTracker links to the module and never transitions the record itself.
 */
const RSP_APPLICATION_ADMIN_ACTIONS = Object.freeze({
  submitted: { action: 'review_documents_in_rsp', label: 'Review applicant documents in RSP' },
  exam_taken: { action: 'grade_exam_in_rsp', label: 'Complete exam grading in RSP' },
  passed: { action: 'continue_hiring_in_rsp', label: 'Continue hiring steps in RSP' },
});

function sourceModuleActionForRow(row, user) {
  const role = String(user?.role || '').trim().toLowerCase();
  if (role !== 'admin') return null;
  const status = String(row.source_status || '').trim().toLowerCase();
  if (row.source_module === 'rsp' && row.source_table === 'recruitment_applications') {
    return RSP_APPLICATION_ADMIN_ACTIONS[status] || null;
  }
  if (
    row.source_module === 'ld' &&
    row.source_table === 'training_daily_reports' &&
    status === 'submitted'
  ) {
    return { action: 'review_report_in_ld', label: 'Review training report in L&D' };
  }
  return null;
}

function sourceActionForRow(row, user) {
  if (row.source_module === 'rsp' || row.source_module === 'ld') {
    return sourceModuleActionForRow(row, user);
  }
  if (row.source_module !== 'dtr' || row.source_table !== 'leave_requests') {
    return null;
  }

  const status = String(row.source_status || '').trim().toLowerCase();
  const viewerId = String(user?.id || '').trim();
  const role = String(user?.role || '').trim().toLowerCase();
  const isOwner = sameEntityId(row.source_owner_id, viewerId);
  const isDepartmentReviewer =
    sameEntityId(row.assigned_department_head_id, viewerId) ||
    row.viewer_is_department_reviewer === true;
  const isHrOrAdmin = role === 'hr' || role === 'admin';

  if (isOwner && status === 'draft') {
    return {
      action: 'complete_in_dtr',
      label: 'Complete and submit in DTR',
    };
  }
  if (isOwner && status === 'returned') {
    return {
      action: 'update_in_dtr',
      label: 'Update and resubmit in DTR',
    };
  }
  if (isDepartmentReviewer && status === 'pending_department_head') {
    return {
      action: 'department_review_in_dtr',
      label: 'Sign here, then review in DTR',
    };
  }
  if (isHrOrAdmin && (status === 'pending_hr' || status === 'pending')) {
    return {
      action: 'hr_review_in_dtr',
      label: 'Sign here, then review in DTR',
    };
  }
  return null;
}

/**
 * An L&D report marked seen/reviewed is complete (mapped to approved) but was
 * never approved, so the Approved filter must not list it.
 */
function isReviewedSourceCompletion(row) {
  if (row?.source_module !== 'ld') return false;
  const status = String(row.source_status || '').toLowerCase().trim();
  return status === 'seen' || status === 'reviewed';
}

function mapSourceStatusToDocuTracker(sourceModule, sourceStatus) {
  const status = String(sourceStatus || '').toLowerCase().trim();
  if (!status) return 'pending';

  if (sourceModule === 'ld') {
    // L&D's only review action is the admin "Mark as Seen", which the L&D
    // module shows as "Reviewed" and which ends the report's workflow.
    if (status === 'seen' || status === 'reviewed' || status === 'approved') {
      return 'approved';
    }
    if (status === 'needs_revision') return 'returned';
    return 'pending';
  }

  if (sourceModule === 'rsp') {
    // Applicants may resubmit declined documents; hiring completes at registered.
    if (status === 'document_declined') return 'returned';
    if (status === 'failed') return 'rejected';
    if (status === 'registered') return 'approved';
    if (status === 'document_approved' || status === 'exam_taken' || status === 'passed') {
      return 'in_review';
    }
    return 'pending';
  }

  if (sourceModule === 'dtr') {
    if (status === 'approved') return 'approved';
    if (status === 'returned') return 'returned';
    if (
      status === 'rejected' ||
      status === 'rejected_by_department_head' ||
      status === 'rejected_by_hr'
    ) {
      return 'rejected';
    }
    if (status === 'cancelled') return 'cancelled';
    if (
      status === 'pending_department_head' ||
      status === 'pending_hr'
    ) {
      return 'in_review';
    }
    return 'pending';
  }

  return 'pending';
}

function parseLimitOffset(filters = {}) {
  const limitVal = Number.isNaN(Number(filters.limit)) ? 50 : Math.min(Number(filters.limit), 200);
  const offsetVal = Number.isNaN(Number(filters.offset)) ? 0 : Math.max(Number(filters.offset), 0);
  return { limitVal, offsetVal };
}

function matchesTextFilter(value, q) {
  if (!q) return true;
  return String(value || '').toLowerCase().includes(q);
}

async function listSourceBackedDocuments(pool, user, filters = {}) {
  const sourceWarnings = [];
  const safeSourceQuery = async (label, sql, params = []) => {
    try {
      const result = await pool.query(sql, params);
      return result.rows || [];
    } catch (error) {
      // Keep DocuTracker usable even when some source-module tables
      // are not yet initialized in a given environment.
      if (error?.code === '42P01') {
        console.warn(`[docutracker source] skipped missing table for ${label}: ${error.message}`);
        sourceWarnings.push(`Source module data unavailable: ${label} table is missing.`);
        return [];
      }
      throw error;
    }
  };

  const sourceModuleFilter = String(filters.sourceModule || '').toLowerCase().trim();
  const typeFilter = String(filters.type || '').toLowerCase().trim();
  const allowedByType = typeFilter && typeFilter !== 'all' ? new Set([typeFilter]) : null;
  const allowedByModule =
    sourceModuleFilter && sourceModuleFilter !== 'all' ? new Set([sourceModuleFilter]) : null;
  const moduleViewPermissionCache = new Map();

  const canViewModule = async (moduleName) => {
    if (user.role === 'admin') return true;
    if (moduleViewPermissionCache.has(moduleName)) {
      return moduleViewPermissionCache.get(moduleName) === true;
    }
    const allowed = await canUserPerformTypeAction(pool, {
      user,
      documentType: moduleName,
      action: 'view',
    });
    moduleViewPermissionCache.set(moduleName, allowed === true);
    return allowed === true;
  };

  const shouldInclude = (moduleName) => {
    if (allowedByType && !allowedByType.has(moduleName)) return false;
    if (allowedByModule && !allowedByModule.has(moduleName)) return false;
    return true;
  };

  const pieces = [];
  if (shouldInclude('ld') && (await canViewModule('ld'))) {
    const ldParams = [];
    const ldWhere = ['1=1'];
    if (user.role !== 'admin') {
      ldWhere.push(`r.employee_id = $${ldParams.length + 1}`);
      ldParams.push(user.id);
    }
    const ldRows = await safeSourceQuery(
      'ld.training_daily_reports',
      `SELECT
         r.id::text AS source_record_id,
         'ld'::text AS source_module,
         'training_daily_reports'::text AS source_table,
         r.title AS source_title,
         COALESCE(NULLIF(r.description, ''), 'Training daily report submission') AS description,
         r.employee_id::text AS created_by,
         u.full_name AS creator_name,
         r.submitted_at AS created_at,
         r.updated_at AS updated_at,
         r.status AS source_status
       FROM training_daily_reports r
       JOIN users u ON u.id = r.employee_id
       WHERE ${ldWhere.join(' AND ')}`,
      ldParams
    );
    pieces.push(...ldRows);
  }

  if (shouldInclude('dtr') && (await canViewModule('dtr'))) {
    const dtrParams = [];
    const dtrWhere = ['1=1'];
    if (user.role !== 'admin') {
      dtrWhere.push(`c.employee_id = $${dtrParams.length + 1}`);
      dtrParams.push(user.id);
    }
    const dtrRows = await safeSourceQuery(
      'dtr.dtr_corrections',
      `SELECT
         c.id::text AS source_record_id,
         'dtr'::text AS source_module,
         'dtr_corrections'::text AS source_table,
         ('Correction ' || to_char(c.attendance_date, 'YYYY-MM-DD')) AS source_title,
         c.reason AS description,
         c.employee_id::text AS created_by,
         u.full_name AS creator_name,
         c.created_at AS created_at,
         c.updated_at AS updated_at,
         c.status AS source_status
       FROM dtr_corrections c
       JOIN users u ON u.id = c.employee_id
       WHERE ${dtrWhere.join(' AND ')}`,
      dtrParams
    );
    pieces.push(...dtrRows);

    const otParams = [];
    const otWhere = ['1=1'];
    if (user.role !== 'admin') {
      otWhere.push(`o.employee_id = $${otParams.length + 1}`);
      otParams.push(user.id);
    }
    const otRows = await safeSourceQuery(
      'dtr.overtime_requests',
      `SELECT
         o.id::text AS source_record_id,
         'dtr'::text AS source_module,
         'overtime_requests'::text AS source_table,
         ('Overtime ' || to_char(o.ot_date, 'YYYY-MM-DD')) AS source_title,
         COALESCE(NULLIF(o.reason, ''), 'Overtime request') AS description,
         o.employee_id::text AS created_by,
         u.full_name AS creator_name,
         o.created_at AS created_at,
         o.updated_at AS updated_at,
         o.status AS source_status
       FROM overtime_requests o
       JOIN users u ON u.id = o.employee_id
       WHERE ${otWhere.join(' AND ')}`,
      otParams
    );
    pieces.push(...otRows);

    const leaveRows = await safeSourceQuery(
      'dtr.leave_requests',
      `SELECT
         l.id::text AS source_record_id,
         'dtr'::text AS source_module,
         'leave_requests'::text AS source_table,
         (
           'Leave ' ||
           to_char(l.start_date, 'YYYY-MM-DD') ||
           CASE
             WHEN l.end_date IS NOT NULL AND l.end_date <> l.start_date
               THEN ' to ' || to_char(l.end_date, 'YYYY-MM-DD')
             ELSE ''
           END
         ) AS source_title,
         COALESCE(NULLIF(l.reason, ''), 'Leave request') AS description,
         COALESCE(l.user_id::text, l.employee_id::text) AS created_by,
         u.full_name AS creator_name,
         l.created_at AS created_at,
         l.updated_at AS updated_at,
         l.status AS source_status,
         COALESCE(l.user_id, l.employee_id)::text AS source_owner_id,
         l.assigned_department_head_id::text AS assigned_department_head_id,
         EXISTS (
           SELECT 1
           FROM leave_request_department_reviewers current_reviewer
           WHERE current_reviewer.leave_request_id = l.id
             AND current_reviewer.reviewer_id = $1::uuid
         ) AS viewer_is_department_reviewer
       FROM leave_requests l
       JOIN users u ON u.id = COALESCE(l.user_id, l.employee_id)
       WHERE ${
         user.role === 'admin' || user.role === 'hr'
           ? '1=1'
           : `(
               l.user_id = $1::uuid
               OR l.employee_id = $1::uuid
               OR l.assigned_department_head_id = $1::uuid
               OR EXISTS (
                 SELECT 1
                 FROM leave_request_department_reviewers lrr
                 WHERE lrr.leave_request_id = l.id
                   AND lrr.reviewer_id = $1::uuid
               )
               OR EXISTS (
                 SELECT 1
                 FROM leave_request_history lrh
                 WHERE lrh.leave_request_id = l.id
                   AND lrh.acted_by = $1::uuid
                   AND lrh.action IN (
                     'department_head_approved',
                     'department_head_rejected',
                     'department_head_returned'
                   )
               )
             )`
       }`,
      [user.id]
    );
    pieces.push(...leaveRows);
  }

  if (shouldInclude('rsp') && user.role === 'admin' && (await canViewModule('rsp'))) {
    const rspRows = await safeSourceQuery(
      'rsp.recruitment_applications',
      `SELECT
         a.id::text AS source_record_id,
         'rsp'::text AS source_module,
         'recruitment_applications'::text AS source_table,
         COALESCE(NULLIF(a.position_applied_for, ''), a.full_name, 'Recruitment application') AS source_title,
         COALESCE(NULLIF(a.resume_notes, ''), 'Applicant: ' || a.full_name) AS description,
         NULL::text AS created_by,
         a.full_name AS creator_name,
         a.created_at AS created_at,
         a.updated_at AS updated_at,
         a.status AS source_status
       FROM recruitment_applications a
       WHERE ${excludeMayorIntakeStubSql('a')}
         AND a.status NOT IN ('endorsed', 'rejected')`
    );
    pieces.push(...rspRows);
  }

  const q = String(filters.q || '').toLowerCase().trim();
  const statusFilter = normalizeStatus(filters.status);

  const rows = pieces
    .map((row) => {
      const mappedStatus = mapSourceStatusToDocuTracker(row.source_module, row.source_status);
      const sourceAction = sourceActionForRow(row, user);
      const viewerId = String(user?.id || '').trim();
      const role = String(user?.role || '').trim().toLowerCase();
      const isDepartmentReviewer =
        sameEntityId(row.assigned_department_head_id, viewerId) ||
        row.viewer_is_department_reviewer === true;
      const isHrOrAdmin = role === 'hr' || role === 'admin';
      // Keep leave (and similar) visible for reviewers after they sign/act so
      // the card does not vanish from Required actions while admins still see it.
      const viewerParticipatedInSource =
        row.source_table === 'leave_requests' &&
        (isDepartmentReviewer ||
          (isHrOrAdmin &&
            ['pending_hr', 'pending', 'approved', 'rejected', 'returned'].includes(
              String(row.source_status || '').toLowerCase()
            )));
      return {
        id: `source:${row.source_module}:${row.source_record_id}`,
        document_number: null,
        document_type: row.source_module,
        title: row.source_title || 'Source document',
        description: row.description || null,
        source_module: row.source_module,
        source_table: row.source_table,
        source_record_id: row.source_record_id,
        source_title: row.source_title || null,
        source_status: row.source_status || null,
        source_action: sourceAction?.action || null,
        source_action_label: sourceAction?.label || null,
        file_path: null,
        file_name: null,
        created_by: row.created_by,
        creator_name: row.creator_name || null,
        current_holder_id: null,
        current_step: null,
        status: mappedStatus,
        sent_time: null,
        deadline_time: null,
        reviewed_time: null,
        escalation_level: 0,
        needs_admin_intervention: false,
        source_only: true,
        viewer_participated_in_source: viewerParticipatedInSource,
        created_at: row.created_at,
        updated_at: row.updated_at,
      };
    })
    .filter((row) => {
      if (filters.status && filters.status !== 'All' && VALID_STATUSES.has(statusFilter)) {
        if (normalizeStatus(row.status) !== statusFilter) return false;
        if (statusFilter === 'approved' && isReviewedSourceCompletion(row)) return false;
      }
      if (!q) return true;
      return (
        matchesTextFilter(row.title, q) ||
        matchesTextFilter(row.description, q) ||
        matchesTextFilter(row.source_title, q) ||
        matchesTextFilter(row.creator_name, q)
      );
    });
  return {
    rows,
    sourceWarnings: Array.from(new Set(sourceWarnings)),
  };
}

function parseSteps(steps) {
  if (!Array.isArray(steps)) return [];
  return steps
    .map((step) => ({
      step_order: Number(step.step_order ?? step.stepOrder ?? 0),
      assignee_type: String(step.assignee_type ?? step.assigneeType ?? '').trim().toLowerCase(),
      assignee_source: String(
        step.assignee_source ?? step.assigneeSource ?? 'specific_users'
      ).trim().toLowerCase(),
      role_id: step.role_id ?? step.roleId ?? null,
      department_id: step.department_id ?? step.departmentId ?? null,
      label: step.label ?? null,
      enabled: step.enabled !== false,
      deadline_hours:
        step.deadline_hours != null
          ? Number(step.deadline_hours)
          : step.deadlineHours != null
            ? Number(step.deadlineHours)
            : null,
      requires_signature:
        step.requires_signature === true || step.requiresSignature === true,
      user_ids: Array.isArray(step.user_ids)
        ? step.user_ids
        : Array.isArray(step.userIds)
          ? step.userIds
          : [],
      allowed_actions: Array.isArray(step.allowed_actions)
        ? step.allowed_actions.map((action) => String(action).trim().toLowerCase())
        : Array.isArray(step.allowedActions)
          ? step.allowedActions.map((action) => String(action).trim().toLowerCase())
          : ['approve', 'forward', 'return', 'reject'],
    }))
    .filter((step) => step.step_order > 0)
    .sort((a, b) => a.step_order - b.step_order);
}

function validationError(message) {
  const err = new Error(message);
  err.code = 'VALIDATION';
  return err;
}

function forbiddenError(message = 'Permission denied') {
  const err = new Error(message);
  err.code = 'FORBIDDEN';
  return err;
}

function notFoundError(message = 'Resource not found') {
  const err = new Error(message);
  err.code = 'NOT_FOUND';
  return err;
}

function wrapDatabaseError(error, fallbackMessage) {
  if (!error) {
    const err = new Error(fallbackMessage);
    err.code = 'DB_FAILURE';
    return err;
  }
  if (typeof error.code === 'string' && /^[0-9A-Z]{5}$/.test(error.code)) {
    const err = new Error(fallbackMessage);
    err.code = 'DB_FAILURE';
    err.dbCode = error.code;
    err.cause = error;
    return err;
  }
  if (error.code) return error;
  const err = new Error(fallbackMessage);
  err.code = 'DB_FAILURE';
  err.cause = error;
  return err;
}

function ensureActionAllowedFromStatus(action, status) {
  const allowedFrom = TRANSITION_ALLOWED_FROM[action];
  if (!allowedFrom) return;
  if (!allowedFrom.has(status)) {
    throw validationError(
      userFacingValidationMessage(`${action} is not valid from status ${status}`)
    );
  }
}

function isDraftOrWipDocument(document, normalizedStatus = null) {
  if (!document) return false;
  const status = normalizedStatus || normalizeStatus(document.status);
  if (status === 'draft') return true;
  // Pending with no active assignment behaves as a WIP/draft.
  return (
    status === 'pending' &&
    !document.current_holder_id &&
    (document.current_step == null || Number(document.current_step) <= 0) &&
    !document.sent_time
  );
}

function userFacingValidationMessage(message) {
  if (!message) return message;
  const noSteps = message.match(/Workflow config for '([^']+)' has no steps/);
  if (noSteps) {
    const typeLabel = noSteps[1];
    return (
      `The "${typeLabel}" workflow has no routing steps configured. ` +
      'An admin must open DocuTracker → Admin → Workflows, add at least one step with assignees, and save before documents can be forwarded, approved, rejected, or returned.'
    );
  }
  const badAction = message.match(/^(\w+) is not valid from status (\w+)$/);
  if (badAction) {
    const [, action, status] = badAction;
    if (action === 'submit' && status === 'overdue') {
      return (
        'Submit is not available while this document is overdue. ' +
        'Use Forward, Approve, Reject, or Return if you are the current reviewer, or ask an admin to reassign.'
      );
    }
    return `${action} is not allowed while the document is ${status.replaceAll('_', ' ')}.`;
  }
  return message;
}

function ensureValidWorkflowConfig(config, documentType) {
  if (!config) {
    throw validationError(
      userFacingValidationMessage(
        `Missing workflow config for document_type '${documentType}'`
      )
    );
  }
  const steps = parseSteps(config.steps || []);
  if (!steps.length) {
    throw validationError(
      userFacingValidationMessage(`Workflow config for '${documentType}' has no steps`)
    );
  }
  if (steps[0].step_order !== 1) {
    throw validationError(`Workflow config for '${documentType}' must start at step 1`);
  }
  for (let i = 1; i < steps.length; i += 1) {
    if (steps[i].step_order !== steps[i - 1].step_order + 1) {
      throw validationError(`Workflow config for '${documentType}' has incorrect step order`);
    }
  }
  if (!steps.some((s) => s.enabled !== false)) {
    throw validationError(`Workflow config for '${documentType}' must have at least one enabled step`);
  }
  return steps;
}

function getStepByOrder(steps, order) {
  return steps.find((s) => s.step_order === order) || null;
}

async function validateAssignee(client, assigneeId) {
  if (!assigneeId) return false;
  const result = await client.query(
    `SELECT id
     FROM users
     WHERE id = $1
       AND (is_active IS NULL OR is_active = true)`,
    [assigneeId]
  );
  return result.rowCount > 0;
}

/**
 * Validates an optional explicit assignee override from the client.
 * Admins may pick any active user; non-admins may only pick a user that would be
 * allowed for this step when no explicit override is used (same set as resolveStepAssignees without explicit).
 */
async function sanitizeExplicitAssigneeId(client, user, rawExplicit, ctx) {
  const {
    stepConfig,
    currentHolderId,
    documentType,
    workflowVersion,
    submitterUserId,
  } = ctx;
  if (rawExplicit == null || rawExplicit === '') return null;
  const id = String(rawExplicit).trim();
  if (!id) return null;

  if (user?.role === 'admin') {
    const valid = await validateAssignee(client, id);
    if (!valid) throw validationError(`Invalid assignee '${id}'`);
    return id;
  }

  const allowed = await resolveStepAssignees(client, {
    explicitAssigneeId: null,
    stepConfig,
    currentHolderId,
    documentType,
    workflowVersion,
    submitterUserId,
  });
  const allowedSet = new Set(allowed.map((x) => String(x)));
  if (!allowedSet.has(String(id))) {
    throw validationError('Target assignee is not allowed for this workflow step');
  }
  return id;
}

async function resolveStepAssignee(client, { explicitAssigneeId, stepConfig, currentHolderId }) {
  const type = String(stepConfig?.assignee_type || '').trim().toLowerCase();

  // Explicit assignee (must be pre-sanitized at workflow entry points for non-admins).
  if (explicitAssigneeId) {
    const valid = await validateAssignee(client, explicitAssigneeId);
    if (!valid) throw validationError(`Invalid assignee '${explicitAssigneeId}'`);
    return explicitAssigneeId;
  }

  if (type === 'user' || !type) {
    const configured = Array.isArray(stepConfig?.user_ids) ? stepConfig.user_ids.filter(Boolean) : [];
    const candidate = configured[0] || currentHolderId || null;
    if (!candidate) {
      throw validationError(`No valid assignee configured for step ${stepConfig?.step_order ?? 'unknown'}`);
    }
    const valid = await validateAssignee(client, candidate);
    if (!valid) throw validationError(`Invalid assignee '${candidate}'`);
    return candidate;
  }

  if (type === 'role') {
    const roleId = String(stepConfig?.role_id || '').trim();
    if (!roleId) throw validationError(`No role_id configured for step ${stepConfig?.step_order ?? 'unknown'}`);
    const roleIds = getRoleVariants(roleId);
    const r = await client.query(
      `SELECT id
       FROM users
       WHERE role = ANY($1::text[])
         AND (is_active IS NULL OR is_active = true)
       ORDER BY full_name NULLS LAST, email NULLS LAST
       LIMIT 1`,
      [roleIds]
    );
    const candidate = r.rows?.[0]?.id || null;
    if (!candidate) throw validationError(`No active user found for role '${roleId}'`);
    return candidate;
  }

  if (type === 'department') {
    const deptId = stepConfig?.department_id;
    if (!deptId) throw validationError(`No department_id configured for step ${stepConfig?.step_order ?? 'unknown'}`);
    const r = await client.query(
      `SELECT u.id
       FROM assignments a
       JOIN users u
         ON u.id = a.employee_id
       WHERE a.department_id = $1
         AND (a.is_active IS NULL OR a.is_active = true)
         AND a.effective_from <= CURRENT_DATE
         AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
         AND (u.is_active IS NULL OR u.is_active = true)
       ORDER BY a.effective_from DESC, u.full_name NULLS LAST, u.email NULLS LAST
       LIMIT 1`,
      [deptId]
    );
    const candidate = r.rows?.[0]?.id || null;
    if (!candidate) throw validationError(`No active user assignment found for department '${deptId}'`);
    const valid = await validateAssignee(client, candidate);
    if (!valid) throw validationError(`Invalid assignee '${candidate}'`);
    return candidate;
  }

  if (type === 'office') {
    const officeId = String(stepConfig?.office_id || '').trim();
    if (!officeId) {
      throw validationError(`No office_id configured for step ${stepConfig?.step_order ?? 'unknown'}`);
    }
    const canUseOfficeId = await hasUsersOfficeIdColumn(client);
    if (!canUseOfficeId) {
      throw validationError(
        'Office-based DocuTracker routing is not installed on this database. Use role, department, or user routing instead.'
      );
    }
    const r = await client.query(
      `SELECT u.id
       FROM users u
       WHERE u.office_id = $1::uuid
         AND (u.is_active IS NULL OR u.is_active = true)
       ORDER BY u.full_name NULLS LAST, u.email NULLS LAST
       LIMIT 1`,
      [officeId]
    );
    const candidate = r.rows?.[0]?.id || null;
    if (!candidate) {
      throw validationError(
        `No active user found for office '${officeId}'. Assign employees to this office (users.office_id).`
      );
    }
    const valid = await validateAssignee(client, candidate);
    if (!valid) throw validationError(`Invalid assignee '${candidate}'`);
    return candidate;
  }

  if (currentHolderId) {
    const valid = await validateAssignee(client, currentHolderId);
    if (valid) return currentHolderId;
  }

  throw validationError(`No valid assignee configured for step ${stepConfig?.step_order ?? 'unknown'}`);
}

async function loadStepsFromNormalizedTables(client, documentType, workflowVersion) {
  const stepsRes = await client.query(
    `SELECT id, step_order, department_id, assignee_source, label, enabled
     FROM docutracker_workflow_steps
     WHERE document_type = $1
       AND workflow_version = $2
     ORDER BY step_order ASC`,
    [documentType, workflowVersion]
  );
  if (stepsRes.rowCount === 0) return [];

  const assigneeRes = await client.query(
    `SELECT ws.step_order, wsa.user_id::text AS user_id
     FROM docutracker_workflow_step_assignees wsa
     JOIN docutracker_workflow_steps ws ON ws.id = wsa.step_id
     WHERE ws.document_type = $1
       AND ws.workflow_version = $2
       AND (wsa.is_enabled IS NULL OR wsa.is_enabled = true)
     ORDER BY ws.step_order ASC,
              wsa.is_primary DESC,
              wsa.backup_rank ASC NULLS LAST`,
    [documentType, workflowVersion]
  );
  const userIdsByStep = new Map();
  for (const row of assigneeRes.rows || []) {
    const order = Number(row.step_order);
    if (!userIdsByStep.has(order)) userIdsByStep.set(order, []);
    const uid = row.user_id;
    if (uid && !userIdsByStep.get(order).includes(uid)) {
      userIdsByStep.get(order).push(uid);
    }
  }

  return stepsRes.rows
    .map((row) => ({
      step_order: Number(row.step_order),
      assignee_type: 'user',
      assignee_source: row.assignee_source || 'specific_users',
      department_id: row.department_id ?? null,
      label: row.label ?? null,
      enabled: row.enabled !== false,
      user_ids: userIdsByStep.get(Number(row.step_order)) || [],
    }))
    .filter((s) => s.step_order > 0 && s.enabled !== false);
}

async function enrichRoutingConfigRow(client, documentType, row) {
  if (!row) return null;
  let steps = parseSteps(row.steps || []);
  if (!steps.length && row.version != null) {
    const rebuilt = await loadStepsFromNormalizedTables(
      client,
      documentType,
      row.version
    );
    if (rebuilt.length) {
      return { ...row, steps: rebuilt };
    }
  }
  return row;
}

async function getRoutingConfig(client, documentType, workflowVersion = null) {
  async function fetchVersionRow(version) {
    const r = await client.query(
      `SELECT document_type, steps, review_deadline_hours, version
       FROM docutracker_routing_config_versions
       WHERE document_type = $1
         AND version = $2
       LIMIT 1`,
      [documentType, version]
    );
    return r.rows[0] || null;
  }

  async function fetchLatestRow() {
    const configRes = await client.query(
      `SELECT v.document_type, v.steps, v.review_deadline_hours, v.version
       FROM docutracker_routing_config_versions v
       JOIN (
         SELECT document_type, MAX(version) AS version
         FROM docutracker_routing_config_versions
         GROUP BY document_type
       ) latest
         ON latest.document_type = v.document_type
        AND latest.version = v.version
       WHERE v.document_type = $1
       LIMIT 1`,
      [documentType]
    );
    return configRes.rows[0] || null;
  }

  const hasRunnableSteps = (row) => row && parseSteps(row.steps || []).length > 0;

  if (workflowVersion != null) {
    const pinned = await enrichRoutingConfigRow(
      client,
      documentType,
      await fetchVersionRow(workflowVersion)
    );
    if (hasRunnableSteps(pinned)) return pinned;

    const latest = await enrichRoutingConfigRow(
      client,
      documentType,
      await fetchLatestRow()
    );
    if (hasRunnableSteps(latest)) return latest;

    return pinned || latest;
  }

  return enrichRoutingConfigRow(client, documentType, await fetchLatestRow());
}

function getRoleVariants(role) {
  const normalized = String(role || '').trim();
  if (!normalized) return [];
  const aliases = {
    hr: ['hr_staff'],
    supervisor: ['dept_head'],
    hr_staff: ['hr'],
    dept_head: ['supervisor'],
  };
  return Array.from(new Set([normalized, ...(aliases[normalized] || [])]));
}

async function fetchPermissionRows(client, { role, userId, documentType, action }) {
  const roleIds = getRoleVariants(role);
  const actionVariants = canonicalPermissionAction(action) === 'create_draft'
    ? ['create_draft', 'create']
    : [canonicalPermissionAction(action)];
  const permRes = await client.query(
    `SELECT user_id::text AS user_id,
            role_id,
            document_type,
            granted
     FROM docutracker_permissions
     WHERE action = ANY($1::text[])
       AND (document_type = $2 OR document_type = '*')
       AND (
         user_id = $3
        OR role_id = ANY($4::text[])
       )`,
    [actionVariants, documentType, userId, roleIds]
  );
  return permRes.rows;
}

/** All permission rows for an action for this user (any document_type). Used to batch list visibility. */
async function fetchAllPermissionRowsForAction(client, { role, userId, action }) {
  const roleIds = getRoleVariants(role);
  const actionVariants = canonicalPermissionAction(action) === 'create_draft'
    ? ['create_draft', 'create']
    : [canonicalPermissionAction(action)];
  const permRes = await client.query(
    `SELECT user_id::text AS user_id,
            role_id,
            document_type,
            granted
     FROM docutracker_permissions
     WHERE action = ANY($1::text[])
       AND (
         user_id = $2
        OR role_id = ANY($3::text[])
       )`,
    [actionVariants, userId, roleIds]
  );
  return permRes.rows;
}

/**
 * Departments the user reviews on [effectiveDate]: as the official Department
 * Head (head period on their position) or as an active backup reviewer.
 */
async function listReviewedDepartments(client, userId, effectiveDate = todayInHrmsTimezone()) {
  if (!userId) return [];
  const result = await client.query(
    `SELECT DISTINCT d.id, d.name
     FROM departments d
     WHERE d.id IN (
       SELECT a.department_id
       FROM assignments a
       JOIN positions p ON p.id = a.position_id AND p.department_id = a.department_id
       JOIN position_department_head_periods hp
         ON hp.position_id = p.id
        AND hp.department_id = a.department_id
        AND hp.is_active = true
        AND hp.effective_from <= $2::date
        AND (hp.effective_to IS NULL OR hp.effective_to >= $2::date)
       WHERE a.employee_id = $1::uuid
         AND a.is_active = true
         AND p.is_active = true
         AND a.effective_from <= $2::date
         AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
       UNION
       SELECT b.department_id
       FROM department_reviewer_backups b
       WHERE b.employee_id = $1::uuid
         AND b.is_active = true
         AND b.effective_from <= $2::date
         AND (b.effective_to IS NULL OR b.effective_to >= $2::date)
     )
     ORDER BY d.name`,
    [userId, effectiveDate]
  );
  return result.rows.map((row) => ({ id: row.id, name: row.name }));
}

/** Submitted documents from a department the user reviews are visible read-only; drafts stay private. */
function isDepartmentQueueDocument(document, reviewedDepartmentIds) {
  if (!document?.originating_department_id || !reviewedDepartmentIds?.size) return false;
  if (isDraftOrWipDocument(document)) return false;
  return reviewedDepartmentIds.has(String(document.originating_department_id));
}

/**
 * Filters document rows the same way canUserPerformDocumentAction(..., 'view') would.
 * Relationship-scoped only — role-level `view` on '*' must NOT grant org-wide list access.
 */
async function filterDocumentsViewableByUser(pool, user, rows, { includeDepartmentQueue = false } = {}) {
  if (!rows?.length || user?.role === 'admin') return rows || [];
  const uid = user.id;
  const ids = rows.map((r) => r.id).filter(Boolean);
  const viewPermissionRows = await fetchAllPermissionRowsForAction(pool, {
    role: user.role,
    userId: uid,
    action: 'view',
  });

  let currentStepAssigneeIds = new Set();
  let anyStepAssigneeIds = new Set();
  let historyActorDocIds = new Set();
  let signatureSignerDocIds = new Set();

  if (ids.length) {
    const [currentStepRes, anyStepRes, historyRes, signatureRes] = await Promise.all([
      pool.query(
        `SELECT DISTINCT d.id
         FROM docutracker_documents d
         INNER JOIN docutracker_routing_records rr
           ON rr.document_id = d.id AND rr.step_order = d.current_step
         INNER JOIN docutracker_routing_record_assignees a
           ON a.routing_record_id = rr.id AND a.user_id = $1::uuid
         WHERE d.id = ANY($2::uuid[])`,
        [uid, ids]
      ),
      pool.query(
        `SELECT DISTINCT d.id
         FROM docutracker_documents d
         INNER JOIN docutracker_routing_records rr
           ON rr.document_id = d.id
         INNER JOIN docutracker_routing_record_assignees a
           ON a.routing_record_id = rr.id AND a.user_id = $1::uuid
         WHERE d.id = ANY($2::uuid[])`,
        [uid, ids]
      ),
      pool.query(
        `SELECT DISTINCT document_id AS id
         FROM docutracker_document_history
         WHERE actor_id = $1::uuid
           AND document_id = ANY($2::uuid[])`,
        [uid, ids]
      ),
      pool.query(
        `SELECT DISTINCT document_id AS id
         FROM docutracker_signature_fields
         WHERE assigned_signer_id = $1::uuid
           AND document_id = ANY($2::uuid[])`,
        [uid, ids]
      ),
    ]);
    currentStepAssigneeIds = new Set(currentStepRes.rows.map((x) => x.id));
    anyStepAssigneeIds = new Set(anyStepRes.rows.map((x) => x.id));
    historyActorDocIds = new Set(historyRes.rows.map((x) => x.id));
    signatureSignerDocIds = new Set(signatureRes.rows.map((x) => x.id));
  }
  const reviewedDepartmentIds = includeDepartmentQueue && rows.some((r) => r.originating_department_id)
    ? new Set((await listReviewedDepartments(pool, uid)).map((d) => String(d.id)))
    : new Set();

  const out = [];
  for (const row of rows) {
    const userSpecificView = resolveUserSpecificPermissionFromRows(
      viewPermissionRows,
      { userId: uid, documentType: row.document_type }
    );
    if (userSpecificView === false) continue;
    const rel = getRelationshipFlags(row, user);
    if (rel.isCreator || rel.isReviewer) {
      out.push(row);
      continue;
    }
    if (currentStepAssigneeIds.has(row.id)) {
      out.push({ ...row, viewer_is_routing_assignee: true });
      continue;
    }
    if (
      anyStepAssigneeIds.has(row.id) ||
      historyActorDocIds.has(row.id) ||
      signatureSignerDocIds.has(row.id)
    ) {
      out.push({
        ...row,
        viewer_is_routing_assignee:
          anyStepAssigneeIds.has(row.id) || historyActorDocIds.has(row.id),
      });
      continue;
    }
    if (isDepartmentQueueDocument(row, reviewedDepartmentIds)) {
      out.push(row);
    }
  }

  return out;
}

function permissionPriority(row, { userId, roleIds, documentType }) {
  const isUser = row.user_id && row.user_id === userId;
  const roleSet = new Set((roleIds || []).map((r) => String(r)));
  const isRole = row.role_id && roleSet.has(String(row.role_id));
  const isSpecificType = row.document_type === documentType;
  const isWildcardType = row.document_type === '*';
  if (!isSpecificType && !isWildcardType) return -1;
  if (!isUser && !isRole) return -1;
  if (isUser && isSpecificType) return 400;
  if (isUser && isWildcardType) return 300;
  if (isRole && isSpecificType) return 200;
  if (isRole && isWildcardType) return 100;
  return -1;
}

function resolvePermissionDecisionFromRows(rows, context) {
  const ranked = rows
    .map((row) => ({ row, score: permissionPriority(row, context) }))
    .filter((entry) => entry.score >= 0)
    .sort((a, b) => b.score - a.score);
  if (!ranked.length) return null;
  return ranked[0].row.granted === true;
}

/** User-specific rows only (user_id set). Ignores role-wide grants. */
function resolveUserSpecificPermissionFromRows(rows, { userId, documentType }) {
  const userRows = rows.filter((r) => r.user_id && String(r.user_id) === String(userId));
  if (!userRows.length) return null;
  const ranked = userRows
    .map((row) => ({
      row,
      score: permissionPriority(row, { userId, roleIds: [], documentType }),
    }))
    .filter((entry) => entry.score >= 0)
    .sort((a, b) => b.score - a.score);
  if (!ranked.length) return null;
  return ranked[0].row.granted === true;
}

async function hasPermission(client, { role, userId, documentType, action }) {
  if (role === 'admin') return true;
  const canonicalAction = canonicalPermissionAction(action);
  if (!DOC_ACTIONS.has(canonicalAction)) return false;
  const rows = await fetchPermissionRows(client, {
    role,
    userId,
    documentType,
    action: canonicalAction,
  });
  return resolvePermissionDecisionFromRows(rows, {
    userId,
    roleIds: getRoleVariants(role),
    documentType,
  });
}

function getRelationshipFlags(document, user) {
  if (!user || !document) {
    return { isAdmin: false, isCreator: false, isReviewer: false };
  }
  return {
    isAdmin: user.role === 'admin',
    isCreator: sameEntityId(document.created_by, user.id),
    // Kept for backward compatibility (single-holder flows). For multi-assignee steps,
    // view/action checks should use isUserAssignedToCurrentStep().
    isReviewer: sameEntityId(document.current_holder_id, user.id),
  };
}

const WORKFLOW_STEP_ACTIONS = new Set(['forward', 'approve', 'reject', 'return']);

function canonicalPermissionAction(action) {
  const a = String(action || '').trim().toLowerCase();
  if (!a) return '';
  if (a === 'create' || a === 'create_draft' || a === 'createdraft') {
    return 'create_draft';
  }
  if (a === 'return_doc' || a === 'returndoc') return 'return';
  return a;
}

function isCurrentHolder(document, userId) {
  return !!document && !!userId && sameEntityId(document.current_holder_id, userId);
}

async function resolveEligibleDepartmentReviewers(client, { document, stepConfig, workflowVersion }) {
  return (await resolveStepAssignees(client, {
    explicitAssigneeId: null,
    stepConfig,
    currentHolderId: document.current_holder_id || null,
    documentType: document.document_type,
    workflowVersion,
    submitterUserId: document.created_by || null,
  })).map(String);
}

/**
 * Department review steps have one active reviewer: the persisted current holder,
 * and only while they are still an eligible reviewer. Authority never moves to
 * another reviewer here; that requires a persisted Admin Recovery reassignment.
 * The creator is never eligible. With activeOnly=false any eligible reviewer
 * matches (used to validate an admin recovery target).
 */
async function getDepartmentReviewAssigneeRecord(client, { document, userId, stepConfig, workflowVersion, activeOnly }) {
  if (document.created_by && sameEntityId(document.created_by, userId)) return null;
  if (activeOnly && !sameEntityId(document.current_holder_id, userId)) return null;
  let eligible;
  try {
    eligible = await resolveEligibleDepartmentReviewers(client, { document, stepConfig, workflowVersion });
  } catch (error) {
    if (activeOnly && error?.code === 'VALIDATION') return null;
    throw error;
  }
  const index = eligible.indexOf(String(userId));
  if (index < 0) return null;
  return {
    is_enabled: true,
    is_primary: index === 0,
    backup_rank: index === 0 ? null : index,
    allowed_actions: Array.isArray(stepConfig.allowed_actions)
      ? stepConfig.allowed_actions
      : ['approve', 'forward', 'return', 'reject'],
  };
}

const DEPARTMENT_REVIEW_REASSIGNMENT_MESSAGE =
  'The assigned reviewer for this department review step is no longer an eligible reviewer. An administrator must reassign this document through Admin Recovery before any workflow action can be taken.';

/** Null for non-department steps; otherwise whether the persisted holder may still review. */
async function getDepartmentReviewHolderStatus(client, document) {
  if (!document) return null;
  const config = await getRoutingConfig(client, document.document_type, document.workflow_version || null);
  const stepConfig = getStepByOrder(parseSteps(config?.steps || []), Number(document.current_step || 1));
  if (!stepConfig || !isDynamicDepartmentAssigneeSource(stepConfig.assignee_source)) return null;
  let eligible = [];
  try {
    eligible = await resolveEligibleDepartmentReviewers(client, {
      document,
      stepConfig,
      workflowVersion: document.workflow_version || config?.version || null,
    });
  } catch (error) {
    if (error?.code !== 'VALIDATION') throw error;
  }
  const holder = document.current_holder_id ? String(document.current_holder_id) : null;
  return {
    eligible,
    holderEligible: Boolean(
      holder && eligible.includes(holder) && !sameEntityId(holder, document.created_by)
    ),
  };
}

/**
 * Escalation target for an overdue department review step, or null for other steps.
 * Escalation only moves to the next eligible reviewer after the persisted holder
 * (primary, then backups by rank). An ineligible holder or an exhausted reviewer
 * chain yields no target so the document goes to Admin Recovery instead.
 */
async function resolveDepartmentReviewEscalation(client, document) {
  const status = await getDepartmentReviewHolderStatus(client, document);
  if (!status) return null;
  if (!status.holderEligible) {
    return { nextReviewerId: null, backupRank: null, reason: 'HOLDER_NOT_ELIGIBLE_REVIEWER' };
  }
  const candidates = status.eligible.filter((id) => !sameEntityId(id, document.created_by));
  const nextIndex = candidates.indexOf(String(document.current_holder_id)) + 1;
  const nextReviewerId = candidates[nextIndex] || null;
  if (!nextReviewerId) {
    return { nextReviewerId: null, backupRank: null, reason: 'NO_OTHER_ELIGIBLE_REVIEWER' };
  }
  return {
    nextReviewerId,
    backupRank: status.eligible.indexOf(nextReviewerId) || null,
    reason: null,
  };
}

async function getWorkflowStepAssigneeRecord(client, { document, userId, activeOnly = true }) {
  if (!document || !userId) return null;
  const step = Number(document.current_step || 1);
  const docType = document.document_type;

  const config = await getRoutingConfig(client, docType, document.workflow_version || null);
  const configuredStep = getStepByOrder(parseSteps(config?.steps || []), step);
  if (configuredStep && isDynamicDepartmentAssigneeSource(configuredStep.assignee_source)) {
    if (configuredStep.enabled === false) return null;
    // Stored step-assignee rows are ignored here: department review is always dynamic.
    return getDepartmentReviewAssigneeRecord(client, {
      document,
      userId,
      stepConfig: configuredStep,
      workflowVersion: document.workflow_version || config?.version || null,
      activeOnly,
    });
  }

  let r;
  if (document.workflow_version != null) {
    // Fast path: known version.
    r = await client.query(
      `SELECT a.is_enabled,
              a.allowed_actions,
              a.is_primary,
              a.backup_rank
       FROM docutracker_workflow_steps s
       JOIN docutracker_workflow_step_assignees a
         ON a.step_id = s.id
       WHERE s.document_type = $1
         AND s.workflow_version = $2
         AND s.step_order = $3
         AND (s.enabled IS NULL OR s.enabled = true)
         AND a.user_id = $4::uuid
       LIMIT 1`,
      [docType, document.workflow_version, step, userId]
    );
  } else {
    // Legacy fallback: query against the latest version for this document type.
    r = await client.query(
      `SELECT a.is_enabled,
              a.allowed_actions,
              a.is_primary,
              a.backup_rank
       FROM docutracker_workflow_steps s
       JOIN docutracker_workflow_step_assignees a
         ON a.step_id = s.id
       WHERE s.document_type = $1
         AND s.workflow_version = (
           SELECT MAX(version)
           FROM docutracker_routing_config_versions
           WHERE document_type = $1
         )
         AND s.step_order = $2
         AND (s.enabled IS NULL OR s.enabled = true)
         AND a.user_id = $3::uuid
       LIMIT 1`,
      [docType, step, userId]
    );
  }
  const stored = r.rows?.[0] || null;
  if (stored) return stored;

  // Compatibility path for legacy JSON steps.
  const stepConfig = configuredStep;
  if (!stepConfig || stepConfig.enabled === false) return null;
  const normalizedStep = await client.query(
    `SELECT id FROM docutracker_workflow_steps
     WHERE document_type = $1 AND workflow_version = $2 AND step_order = $3
     LIMIT 1`,
    [docType, document.workflow_version || config?.version || null, step]
  );
  // A removed assignment must not be resurrected from stale legacy JSON.
  if (normalizedStep.rows?.length) return null;
  const assignees = await resolveStepAssignees(client, {
    explicitAssigneeId: null,
    stepConfig,
    currentHolderId: document.current_holder_id || null,
    documentType: docType,
    workflowVersion: document.workflow_version || config?.version || null,
    submitterUserId: document.created_by || null,
  });
  const index = assignees.map(String).indexOf(String(userId));
  if (index < 0) return null;
  return {
    is_enabled: true,
    is_primary: index === 0,
    backup_rank: index === 0 ? null : index,
    allowed_actions:
      Array.isArray(stepConfig.allowed_actions)
        ? stepConfig.allowed_actions
        : ['approve', 'forward', 'return', 'reject'],
  };
}



function assigneeAllowsAction(assigneeRow, action) {
  if (!assigneeRow) return false;
  if (assigneeRow.is_enabled === false) return false;
  const allowed = Array.isArray(assigneeRow.allowed_actions) ? assigneeRow.allowed_actions : [];
  // The strict-actions migration backfills legacy empty rows. Empty is deny-all.
  if (allowed.length === 0) return false;
  return allowed.includes(action);
}

async function canUserPerformWorkflowAction(client, { user, document, action }) {
  if (!WORKFLOW_STEP_ACTIONS.has(action)) return false;
  // Every actor, including an admin, must be assigned to the active step.
  const row = await getWorkflowStepAssigneeRecord(client, { document, userId: user.id });
  return assigneeAllowsAction(row, action);
}

async function canUserPerformGeneralAction(client, { user, documentType, action }) {
  if (user?.role === 'admin') return true;
  const canonicalAction = canonicalPermissionAction(action);
  if (!GENERAL_PERMISSION_ACTIONS.has(canonicalAction)) return false;
  const explicit = await hasPermission(client, {
    role: user.role,
    userId: user.id,
    documentType,
    action: canonicalAction,
  });
  return explicit === true;
}

async function getDepartmentName(client, departmentId) {
  const result = await client.query(
    'SELECT name FROM departments WHERE id = $1::uuid LIMIT 1',
    [departmentId]
  );
  return result.rows?.[0]?.name || null;
}

/**
 * Department review: primary reviewer first, then backups by rank. The
 * submitter is never eligible; when nobody else remains the step is blocked.
 */
async function resolveDepartmentReviewStepAssignees(client, { stepConfig, source, submitterUserId }) {
  const stepLabel = stepConfig?.step_order ?? 'unknown';
  const effectiveDate = todayInHrmsTimezone();
  let departmentId = null;
  let departmentName = null;

  if (source === 'submitter_department_reviewers') {
    if (!submitterUserId) {
      throw validationError(
        `Submitter department reviewer step ${stepLabel} has no document creator`
      );
    }
    const department = await getEmployeeDepartmentForDate(client, submitterUserId, effectiveDate);
    if (!department?.departmentId) {
      throw validationError(
        'The submitter has no active department assignment, so no department reviewer can be resolved. Assign the submitter to a department before submitting.'
      );
    }
    departmentId = department.departmentId;
    departmentName = department.departmentName;
  } else {
    if (!stepConfig?.department_id) {
      throw validationError(`Department reviewer step ${stepLabel} has no department`);
    }
    departmentId = stepConfig.department_id;
  }

  const resolved = await resolveDepartmentReviewers(client, {
    departmentId,
    effectiveDate,
    excludeUserId: submitterUserId || null,
  });
  const reviewerIds = resolved.reviewers
    .map((reviewer) => String(reviewer.reviewerId))
    .filter((id) => id && !(submitterUserId && sameEntityId(id, submitterUserId)));
  if (reviewerIds.length) return reviewerIds;

  const name = departmentName || (await getDepartmentName(client, departmentId)) || 'this department';
  const configured = submitterUserId
    ? await resolveDepartmentReviewers(client, { departmentId, effectiveDate })
    : { primary: null, reviewers: [] };
  if (configured.primary && sameEntityId(configured.primary.reviewerId, submitterUserId)) {
    throw validationError(
      `No eligible reviewer is configured for ${name}. The primary reviewer cannot review their own document. Assign a backup reviewer before submitting.`
    );
  }
  if (configured.reviewers.length) {
    throw validationError(
      `No eligible reviewer is configured for ${name}. The submitter is the only configured reviewer and cannot review their own document. Assign another reviewer before submitting.`
    );
  }
  throw validationError(
    `No reviewer is configured for ${name}. Assign a primary reviewer (Department Head) or a backup reviewer before submitting.`
  );
}

async function resolveStepAssignees(client, {
  explicitAssigneeId,
  stepConfig,
  currentHolderId,
  documentType,
  workflowVersion,
  submitterUserId = null,
}) {
  const type = String(stepConfig?.assignee_type || '').trim().toLowerCase();
  const source = String(
    stepConfig?.assignee_source || stepConfig?.assigneeSource || 'specific_users'
  ).trim().toLowerCase();

  // Explicit assignee (must be pre-sanitized at workflow entry points for non-admins).
  if (explicitAssigneeId) {
    if (
      isDynamicDepartmentAssigneeSource(source) &&
      submitterUserId &&
      sameEntityId(explicitAssigneeId, submitterUserId)
    ) {
      throw validationError(
        'The document creator cannot review their own document at a department review step.'
      );
    }
    const valid = await validateAssignee(client, explicitAssigneeId);
    if (!valid) throw validationError(`Invalid assignee '${explicitAssigneeId}'`);
    return [explicitAssigneeId];
  }

  if (isDynamicDepartmentAssigneeSource(source)) {
    return resolveDepartmentReviewStepAssignees(client, { stepConfig, source, submitterUserId });
  }

  if (type === 'user' || !type) {
    // ALWAYS try to pull primary + backup assignees from the normalized table first.
    // This is the correct source of truth for both department-scoped and plain user steps.
    if (stepConfig?.step_order && documentType && workflowVersion) {
      const versionToUse = workflowVersion ?? null;
      const r = await client.query(
        `SELECT a.user_id::text AS user_id
         FROM docutracker_workflow_steps s
         JOIN docutracker_workflow_step_assignees a
           ON a.step_id = s.id
         WHERE s.document_type = $1
           AND s.workflow_version = $2
           AND s.step_order = $3
           AND (s.enabled IS NULL OR s.enabled = true)
           AND a.is_enabled = true
         ORDER BY a.is_primary DESC, a.backup_rank ASC NULLS LAST, a.created_at ASC`,
        [documentType, versionToUse, stepConfig.step_order]
      );
      const fromDb = (r.rows || []).map((x) => x.user_id).filter(Boolean);
      if (fromDb.length) return fromDb;
    }

    // Fallback: legacy JSON-configured user_ids from routing config.
    const configured =
      Array.isArray(stepConfig?.user_ids) ? stepConfig.user_ids.filter(Boolean) : [];
    const candidate = currentHolderId ? [currentHolderId] : [];
    const ids = configured.length ? configured : candidate;

    if (!ids.length) {
      throw validationError(
        `No valid assignee configured for step ${stepConfig?.step_order ?? 'unknown'}`
      );
    }
    // Filter to active users.
    const active = [];
    for (const id of ids) {
      // eslint-disable-next-line no-await-in-loop
      const ok = await validateAssignee(client, id);
      if (ok) active.push(id);
    }
    if (!active.length) {
      throw validationError(
        `No active assignee found for step ${stepConfig?.step_order ?? 'unknown'}`
      );
    }
    return active;
  }


  // For legacy step types, keep single-resolve behavior but return as a 1-element array.
  const single = await resolveStepAssignee(client, { explicitAssigneeId: null, stepConfig, currentHolderId });
  return single ? [single] : [];
}

async function isUserAssignedToCurrentStep(client, { document, userId }) {
  if (!document || !userId) return false;
  try {
    // PRIMARY PATH: read from the committed routing-record-assignees snapshot.
    // This is more reliable than re-resolving from config (config may have changed)
    // and correctly includes both primary and backup assignees.
    const step = Number(document.current_step || 1);
    const snapRes = await client.query(
      `SELECT 1
       FROM docutracker_routing_records rr
       JOIN docutracker_routing_record_assignees a
         ON a.routing_record_id = rr.id
       WHERE rr.document_id = $1
         AND rr.step_order = $2
         AND a.user_id = $3::uuid
       LIMIT 1`,
      [document.id, step, userId]
    );
    if (snapRes.rowCount > 0) return true;

    // FALLBACK: snapshot table is empty (document just created, or legacy).
    // Re-resolve from workflow config.
    const config = await getRoutingConfig(
      client,
      document.document_type,
      document.workflow_version || null
    );
    const steps = ensureValidWorkflowConfig(config, document.document_type);
    const stepCfg = getStepByOrder(steps, step);
    if (!stepCfg) return false;

    const assignees = await resolveStepAssignees(client, {
      explicitAssigneeId: null,
      stepConfig: stepCfg,
      currentHolderId: document.current_holder_id || null,
      documentType: document.document_type,
      workflowVersion: document.workflow_version || (config?.version ?? null),
      submitterUserId: document.created_by || null,
    });
    return assignees.includes(userId);
  } catch (_) {
    return false;
  }
}

async function isUserAssignedToAnyStep(client, { document, userId }) {
  if (!document || !userId) return false;
  try {
    // Routing snapshots are created when a document reaches a step. Preserve
    // their visibility even when the document is returned to an earlier step.
    const snapRes = await client.query(
      `SELECT 1
       FROM docutracker_routing_records rr
       JOIN docutracker_routing_record_assignees a
         ON a.routing_record_id = rr.id
       WHERE rr.document_id = $1
         AND a.user_id = $2::uuid
       LIMIT 1`,
      [document.id, userId]
    );
    if (snapRes.rowCount > 0) return true;

    // Check if the user has any historical actions on the document.
    const histRes = await client.query(
      `SELECT 1
       FROM docutracker_document_history
       WHERE document_id = $1
         AND actor_id = $2::uuid
       LIMIT 1`,
      [document.id, userId]
    );
    if (histRes.rowCount > 0) return true;

    return false;
  } catch (_) {
    return false;
  }
}

async function isUserAssignedSignature(client, { document, userId }) {
  if (!document?.id || !userId) return false;
  try {
    const result = await client.query(
      `SELECT 1 FROM docutracker_signature_fields
       WHERE document_id = $1 AND assigned_signer_id = $2::uuid
       LIMIT 1`,
      [document.id, userId]
    );
    return result.rowCount > 0;
  } catch (error) {
    if (error?.code === '42P01') return false;
    throw error;
  }
}

async function canUserPerformDocumentAction(client, { user, document, action }) {
  const relationship = getRelationshipFlags(document, user);
  if (relationship.isAdmin && !WORKFLOW_STEP_ACTIONS.has(action)) return true;

  const status = normalizeStatus(document.status);
  const isWip = isDraftOrWipDocument(document, status);

  // WIP (Draft) logic:
  if (isWip) {
    if (action === 'view') {
      const viewRows = await fetchPermissionRows(client, {
        role: user.role,
        userId: user.id,
        documentType: document.document_type,
        action: 'view',
      });
      const userSpecific = resolveUserSpecificPermissionFromRows(viewRows, {
        userId: user.id,
        documentType: document.document_type,
      });
      if (userSpecific === false) return false;
      if (relationship.isCreator) return true;
      return isUserAssignedSignature(client, { document, userId: user.id });
    }
    // Creator can edit or delete their own draft.
    if (action === 'edit' || action === 'delete') {
      return relationship.isCreator;
    }
    // Only authorized users (e.g. HR, Supervisors) can submit.
    if (action === 'submit') {
      return hasPermission(client, {
        role: user.role,
        userId: user.id,
        documentType: document.document_type,
        action: 'submit',
      });
    }
    return false; // No workflow actions (approve/forward) allowed for drafts.
  }

  // Once submitted (not a draft):
  if (action === 'edit' || action === 'delete') {
    // Lock document from creator once it enters workflow.
    return false;
  }

  // Workflow actions: only an assignee of the active step may act.
  if (WORKFLOW_STEP_ACTIONS.has(action)) {
    const allowedFrom = TRANSITION_ALLOWED_FROM[action];
    if (!allowedFrom?.has(status)) return false;
    if (action === 'return' && Number(document.current_step || 1) <= 1) {
      return false;
    }
    if (action === 'forward') {
      try {
        const config = await getRoutingConfig(
          client,
          document.document_type,
          document.workflow_version || null
        );
        if (!nextStepFromConfig(config, Number(document.current_step || 1))) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    const allowedByWorkflow = await canUserPerformWorkflowAction(client, {
      user,
      document,
      action,
    });
    if (!allowedByWorkflow || action !== 'approve') return allowedByWorkflow;
    try {
      if (!(await isMayorFinalApproval(client, { document }))) return true;
    } catch (_) {
      return false;
    }
    return isActiveMayor(client, user.id);
  }

  // View is relationship-scoped (not role-wide browse). User-specific deny still wins.
  if (action === 'view') {
    const viewRows = await fetchPermissionRows(client, {
      role: user.role,
      userId: user.id,
      documentType: document.document_type,
      action: 'view',
    });
    const userSpecific = resolveUserSpecificPermissionFromRows(viewRows, {
      userId: user.id,
      documentType: document.document_type,
    });
    if (userSpecific === false) return false;

    if (relationship.isCreator || relationship.isReviewer) return true;
    if (await isUserAssignedSignature(client, { document, userId: user.id })) return true;
    if (await isUserAssignedToCurrentStep(client, { document, userId: user.id })) return true;
    if (await isUserAssignedToAnyStep(client, { document, userId: user.id })) return true;
    if (document.originating_department_id) {
      const reviewed = await listReviewedDepartments(client, user.id);
      if (isDepartmentQueueDocument(document, new Set(reviewed.map((d) => String(d.id))))) {
        return true;
      }
    }
    return false;
  }

  // Other general type-level actions: create_draft / download use permission rows.
  if (GENERAL_PERMISSION_ACTIONS.has(action)) {
    return canUserPerformGeneralAction(client, {
      user,
      documentType: document.document_type,
      action,
    });
  }

  const explicit = await hasPermission(client, {
    role: user.role,
    userId: user.id,
    documentType: document.document_type,
    action,
  });
  if (explicit !== null) return explicit;
  return false; // default deny
}

async function canUserPerformTypeAction(client, { user, documentType, action }) {
  return canUserPerformGeneralAction(client, { user, documentType, action });
}

async function getEffectivePermissionExplanation(client, { user, action, documentType, document = null }) {
  const canonicalAction = canonicalPermissionAction(action);
  const relationship = getRelationshipFlags(document, user);
  const scopeType = document ? 'document' : 'type';
  if (relationship.isAdmin && !WORKFLOW_STEP_ACTIONS.has(canonicalAction)) {
    return {
      scope: scopeType,
      action: canonicalAction,
      document_type: documentType,
      explicit_matches: [],
      explicit_decision: true,
      fallback_decision: true,
      final_decision: true,
      reason: 'admin_override',
    };
  }

  // Workflow actions: explained via selected-person workflow rules.
  if (WORKFLOW_STEP_ACTIONS.has(canonicalAction)) {
    if (!document) {
      return {
        scope: scopeType,
        action: canonicalAction,
        document_type: documentType,
        explicit_matches: [],
        explicit_decision: null,
        fallback_decision: false,
        final_decision: false,
        relationship,
        reason: 'workflow_action_requires_document',
      };
    }
    const isHolder = isCurrentHolder(document, user.id);
    const isAssigned = await isUserAssignedToCurrentStep(client, { document, userId: user.id });
    const stepAssigneeRow = await getWorkflowStepAssigneeRecord(client, {
      document,
      userId: user.id,
    });
    const allowedByAssignedRule = assigneeAllowsAction(stepAssigneeRow, canonicalAction);
    const allowed = await canUserPerformDocumentAction(client, {
      user,
      document,
      action: canonicalAction,
    });
    const holderStatus = allowed ? null : await getDepartmentReviewHolderStatus(client, document);
    const reason = allowed
      ? (isHolder ? 'current_holder' : 'step_assignee')
      : holderStatus && !holderStatus.holderEligible && !isDraftOrWipDocument(document)
          ? 'reassignment_required'
      : !stepAssigneeRow
          ? 'not_assigned_to_step'
          : !allowedByAssignedRule
              ? 'assigned_but_action_not_allowed'
              : 'blocked_by_workflow_rule';
    return {
      scope: scopeType,
      action: canonicalAction,
      document_type: documentType,
      explicit_matches: [],
      explicit_decision: null,
      fallback_decision: allowed,
      final_decision: allowed,
      relationship: { ...relationship, isCurrentHolder: isHolder, isStepAssignee: isAssigned },
      reason,
    };
  }

  const rows = await fetchPermissionRows(client, {
    role: user.role,
    userId: user.id,
    documentType,
    action: canonicalAction,
  });
  const ranked = rows
    .map((row) => ({
      row,
      score: permissionPriority(row, {
        userId: user.id,
        roleIds: getRoleVariants(user.role),
        documentType,
      }),
    }))
    .filter((entry) => entry.score >= 0)
    .sort((a, b) => b.score - a.score);

  if (canonicalAction === 'view' && document) {
    const userSpecificDecision = resolveUserSpecificPermissionFromRows(rows, {
      userId: user.id,
      documentType,
    });
    const isHolder = isCurrentHolder(document, user.id);
    const isAssigned = await isUserAssignedToCurrentStep(client, {
      document,
      userId: user.id,
    });
    const isSignatureSigner = await isUserAssignedSignature(client, {
      document,
      userId: user.id,
    });
    const relationshipAllowed =
      relationship.isCreator ||
      isHolder ||
      isAssigned ||
      isSignatureSigner ||
      (await isUserAssignedToAnyStep(client, { document, userId: user.id }));

    if (userSpecificDecision === false) {
      return {
        scope: scopeType,
        action: canonicalAction,
        document_type: documentType,
        explicit_matches: ranked.map((entry) => ({
          score: entry.score,
          user_id: entry.row.user_id,
          role_id: entry.row.role_id,
          document_type: entry.row.document_type,
          granted: entry.row.granted === true,
        })),
        explicit_decision: false,
        fallback_decision: relationshipAllowed,
        final_decision: false,
        relationship: {
          ...relationship,
          isCurrentHolder: isHolder,
          isStepAssignee: isAssigned,
          isSignatureSigner,
        },
        reason: 'explicit_permission',
      };
    }

    const allowed =
      userSpecificDecision === true ? true : relationshipAllowed;
    const reason = allowed
      ? userSpecificDecision === true
        ? 'explicit_permission'
        : relationship.isCreator
          ? 'creator'
          : isHolder
            ? 'current_holder'
            : isAssigned
              ? 'step_assignee'
              : isSignatureSigner
                ? 'signature_signer'
              : 'past_participant'
      : 'relationship_required';

    return {
      scope: scopeType,
      action: canonicalAction,
      document_type: documentType,
      explicit_matches: ranked.map((entry) => ({
        score: entry.score,
        user_id: entry.row.user_id,
        role_id: entry.row.role_id,
        document_type: entry.row.document_type,
        granted: entry.row.granted === true,
      })),
      explicit_decision: userSpecificDecision,
      fallback_decision: relationshipAllowed,
      final_decision: allowed,
      relationship: {
        ...relationship,
        isCurrentHolder: isHolder,
        isStepAssignee: isAssigned,
        isSignatureSigner,
      },
      reason,
    };
  }

  const explicitDecision = ranked.length ? ranked[0].row.granted === true : null;
  const fallbackDecision = false;
  const finalDecision = explicitDecision !== null ? explicitDecision : fallbackDecision;

  return {
    scope: scopeType,
    action: canonicalAction,
    document_type: documentType,
    explicit_matches: ranked.map((entry) => ({
      score: entry.score,
      user_id: entry.row.user_id,
      role_id: entry.row.role_id,
      document_type: entry.row.document_type,
      granted: entry.row.granted === true,
    })),
    explicit_decision: explicitDecision,
    fallback_decision: fallbackDecision,
    final_decision: finalDecision,
    relationship,
    reason: explicitDecision !== null ? 'explicit_permission' : 'fallback_rule',
  };
}

async function ensureDocumentViewAccess(client, document, user) {
  return canUserPerformDocumentAction(client, {
    user,
    document,
    action: 'view',
  });
}

async function listDocuments(pool, user, filters = {}) {
  const where = [];
  const params = [];
  let i = 1;

  if (filters.type && filters.type !== 'All') {
    where.push(`d.document_type = $${i++}`);
    params.push(filters.type);
  }

  const status = normalizeStatus(filters.status);
  if (filters.status && filters.status !== 'All' && VALID_STATUSES.has(status)) {
    where.push(`d.status = $${i++}`);
    params.push(status);
  }

  if (filters.holderId) {
    where.push(`d.current_holder_id = $${i++}`);
    params.push(filters.holderId);
  }
  if (filters.createdBy) {
    where.push(`d.created_by = $${i++}`);
    params.push(filters.createdBy);
  }
  if (filters.sourceModule) {
    where.push(`d.source_module = $${i++}`);
    params.push(filters.sourceModule);
  }
  if (filters.sourceTable) {
    where.push(`d.source_table = $${i++}`);
    params.push(filters.sourceTable);
  }
  if (filters.q) {
    where.push(
      `(d.title ILIKE $${i} OR d.description ILIKE $${i} OR COALESCE(d.source_title, '') ILIKE $${i} OR COALESCE(d.document_number, '') ILIKE $${i})`
    );
    params.push(`%${filters.q}%`);
    i += 1;
  }
  const departmentScope = filters.scope === 'department';
  if (departmentScope) {
    const reviewed = await listReviewedDepartments(pool, user.id);
    if (!reviewed.length) return { documents: [], source_warnings: [] };
    where.push(`d.originating_department_id = ANY($${i++}::uuid[])`);
    params.push(reviewed.map((d) => d.id));
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const { limitVal, offsetVal } = parseLimitOffset(filters);
  params.push(limitVal, offsetVal);

  const result = await pool.query(
    `SELECT d.*,
            creator.full_name AS creator_name,
            holder.full_name AS assignee_name,
            COALESCE(
              ARRAY(
                SELECT DISTINCT sf.assigned_signer_id::text
                FROM docutracker_signature_fields sf
                WHERE sf.document_id = d.id
              ),
              '{}'::text[]
            ) AS signature_signer_ids
     FROM docutracker_documents d
     LEFT JOIN users creator ON creator.id = d.created_by
     LEFT JOIN users holder ON holder.id = d.current_holder_id
     ${whereSql}
     ORDER BY d.created_at DESC
     LIMIT $${i} OFFSET $${i + 1}`,
    params
  );
  let baseRows = result.rows;
  if (user.role !== 'admin') {
    baseRows = await filterDocumentsViewableByUser(pool, user, result.rows, {
      includeDepartmentQueue: departmentScope,
    });
  }

  if (departmentScope) {
    return {
      documents: baseRows
        .filter((row) => !isDraftOrWipDocument(row))
        .map(mapDocumentRow),
      source_warnings: [],
    };
  }

  const baseMapped = baseRows.map(mapDocumentRow);
  const { rows: sourceMapped, sourceWarnings } = await listSourceBackedDocuments(pool, user, filters);
  const sourceKeySet = new Set(
    baseMapped
      .filter((row) => row.source_module && row.source_table && row.source_record_id)
      .map((row) => `${row.source_module}:${row.source_table}:${row.source_record_id}`)
  );

  const merged = [
    ...baseMapped,
    ...sourceMapped.filter(
      (row) => !sourceKeySet.has(`${row.source_module}:${row.source_table}:${row.source_record_id}`)
    ),
  ].sort((a, b) => {
    const aTime = new Date(a.created_at || 0).getTime();
    const bTime = new Date(b.created_at || 0).getTime();
    return bTime - aTime;
  });

  return {
    documents: merged.slice(offsetVal, offsetVal + limitVal),
    source_warnings: sourceWarnings,
  };
}

async function getDocumentBundle(pool, id, user) {
  const docResult = await pool.query('SELECT * FROM docutracker_documents WHERE id = $1', [id]);
  if (!docResult.rowCount) return null;
  const docRow = docResult.rows[0];
  const canView = await ensureDocumentViewAccess(pool, docRow, user);
  if (!canView) return { forbidden: true };
  docRow.viewer_is_routing_assignee =
    await isUserAssignedToCurrentStep(pool, { document: docRow, userId: user.id }) ||
    await isUserAssignedToAnyStep(pool, { document: docRow, userId: user.id });

  const [routingResult, historyResult] = await Promise.all([
    pool.query(
      `SELECT *
       FROM docutracker_routing_records
       WHERE document_id = $1
       ORDER BY step_order ASC`,
      [id]
    ),
    pool.query(
      `SELECT h.*,
              COALESCE(NULLIF(h.actor_name, ''), u.full_name) AS actor_name
       FROM docutracker_document_history h
       LEFT JOIN users u ON u.id = h.actor_id
       WHERE document_id = $1
       ORDER BY h.created_at ASC`,
      [id]
    ),
  ]);

  return {
    document: mapDocumentRow(docRow),
    routing: routingResult.rows,
    history: historyResult.rows,
  };
}

async function insertHistory(client, payload) {
  await client.query(
    `INSERT INTO docutracker_document_history
     (document_id, action, actor_id, from_step, to_step, from_status, to_status, remarks, is_overdue_log, is_escalation_log, escalation_level)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, COALESCE($9, false), COALESCE($10, false), $11)`,
    [
      payload.document_id,
      payload.action,
      payload.actor_id || null,
      payload.from_step || null,
      payload.to_step || null,
      payload.from_status || null,
      payload.to_status || null,
      payload.remarks || null,
      payload.is_overdue_log || false,
      payload.is_escalation_log || false,
      payload.escalation_level || null,
    ]
  );
}

async function insertNotification(client, payload) {
  if (!payload.user_id) return;
  await client.query(
    `INSERT INTO docutracker_notifications
     (document_id, user_id, type, event_key, title, body)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (document_id, user_id, type, event_key)
     WHERE event_key IS NOT NULL
     DO NOTHING`,
    [
      payload.document_id,
      payload.user_id,
      payload.type,
      payload.event_key || null,
      payload.title || null,
      payload.body || null,
    ]
  );
}

async function insertNotificationIfNotRecent(client, payload, dedupeMinutes = 15) {
  if (!payload.user_id) return false;
  const explicitEventKey = String(payload.event_key || '').trim() || null;
  if (explicitEventKey) {
    const byKey = await client.query(
      `SELECT id
       FROM docutracker_notifications
       WHERE document_id = $1
         AND user_id = $2
         AND type = $3
         AND event_key = $4
       LIMIT 1`,
      [payload.document_id, payload.user_id, payload.type, explicitEventKey]
    );
    if (byKey.rowCount > 0) return false;

    // A caller-supplied event key identifies one logical workflow event.
    // Different keys must remain distinct even when their title/body match,
    // such as assignment to the same step after a return/resume cycle.
    await insertNotification(client, {
      ...payload,
      event_key: explicitEventKey,
    });
    return true;
  }
  const existing = await client.query(
    `SELECT id
     FROM docutracker_notifications
     WHERE document_id = $1
       AND user_id = $2
       AND type = $3
       AND COALESCE(title, '') = COALESCE($4, '')
       AND COALESCE(body, '') = COALESCE($5, '')
       AND created_at >= now() - make_interval(mins => $6::int)
     LIMIT 1`,
    [
      payload.document_id,
      payload.user_id,
      payload.type,
      payload.title || null,
      payload.body || null,
      dedupeMinutes,
    ]
  );
  if (existing.rowCount > 0) return false;
  await insertNotification(client, { ...payload, event_key: null });
  return true;
}

async function createDocument(pool, user, input) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    if (!input.document_type || !input.title) {
      throw new Error('document_type and title are required');
    }

    const canCreate = await canUserPerformTypeAction(client, {
      user,
      documentType: input.document_type,
      action: 'create_draft',
    });
    if (!canCreate) {
      throw forbiddenError('You do not have permission to create this document type');
    }

    const routingConfig = await getRoutingConfig(client, input.document_type);
    const steps = ensureValidWorkflowConfig(routingConfig, input.document_type);
    const workflowVersion = routingConfig?.version || 1;
    if (input.document_number) {
      const duplicateCheck = await client.query(
        `SELECT id
         FROM docutracker_documents
         WHERE document_number = $1
         LIMIT 1`,
        [input.document_number]
      );
      if (duplicateCheck.rowCount > 0) {
        throw validationError(`Document number '${input.document_number}' already exists`);
      }
    }

    // WIP/draft is represented as status='pending' with no active holder or step.
    // Workflow starts only after an explicit submit transition.
    const stepOne = getStepByOrder(steps, 1);
    if (!stepOne) {
      throw validationError(`Workflow config for '${input.document_type}' must include step 1`);
    }
    const rawStatus = normalizeStatus(input.status || 'pending');
    if (rawStatus !== 'draft' && rawStatus !== 'pending') {
      throw validationError('Only draft/WIP creation is allowed');
    }
    const initialStatus = rawStatus === 'draft' ? 'pending' : rawStatus;
    if (initialStatus !== 'pending' || !VALID_STATUSES.has(initialStatus)) {
      throw validationError(
        'New documents are created as WIP (pending) and must be submitted to start workflow'
      );
    }

    const creatorDepartment = await getEmployeeDepartmentForDate(
      client,
      user.id,
      todayInHrmsTimezone()
    );
    const originatingDepartmentId = creatorDepartment?.departmentId || null;

    const docRes = await client.query(
      `INSERT INTO docutracker_documents
       (document_number, document_type, title, description,
        source_module, source_table, source_record_id, source_title,
        file_path, file_name, created_by, originating_department_id,
        current_holder_id, current_step,
        status, sent_time, deadline_time, workflow_version)
       VALUES ($1, $2, $3, $4,
               $5, $6, $7, $8,
               $9, $10, $11, $12,
               NULL, NULL,
               $13, NULL, NULL, $14)
       RETURNING *`,
      [
        input.document_number || null,
        input.document_type,
        input.title,
        input.description || null,
        input.source_module || null,
        input.source_table || null,
        input.source_record_id || null,
        input.source_title || null,
        input.file_path || null,
        input.file_name || null,
        user.id,
        originatingDepartmentId,
        initialStatus,
        workflowVersion,
      ]
    );

    const doc = docRes.rows[0];

    await recordInitialDocumentFile(client, {
      documentId: doc.id,
      fileName: input.file_name || null,
      filePath: input.file_path || null,
      uploadedBy: user.id,
    });

    await insertHistory(client, {
      document_id: doc.id,
      action: 'created',
      actor_id: user.id,
      to_step: null,
      to_status: initialStatus,
      remarks: input.description || null,
    });

    await client.query('COMMIT');
    return mapDocumentRow(doc);
  } catch (error) {
    await client.query('ROLLBACK');
    if (error?.code === '23505' && String(error?.constraint || '').includes('document_number')) {
      throw validationError('Document number already exists');
    }
    throw error;
  } finally {
    client.release();
  }
}

const STEP_SIGNATURE_GATED_ACTIONS = new Set(['approve', 'forward']);

async function canAddOwnSignatureToDocument(client, { document, user }) {
  if (!document || !user?.id) return false;
  const status = normalizeStatus(document.status);
  if (TERMINAL_STATUSES.has(status)) return false;
  if (isDraftOrWipDocument(document, status)) return false;
  const row = await getWorkflowStepAssigneeRecord(client, {
    document,
    userId: user.id,
  });
  return Boolean(row && row.is_enabled !== false);
}

async function hasUserSignedDocument(client, { documentId, userId }) {
  const result = await client.query(
    `SELECT 1 FROM docutracker_signature_fields
     WHERE document_id = $1
       AND signed_by = $2::uuid
       AND signed_at IS NOT NULL
     LIMIT 1`,
    [documentId, userId]
  );
  return result.rowCount > 0;
}

// Document types whose final approval (issuing the document) belongs to the
// active Mayor only, regardless of who is assigned to the last step.
const MAYOR_FINAL_AUTHORITY_TYPES = new Set(['memo']);

async function isMayorFinalApproval(client, { document, config }) {
  if (!MAYOR_FINAL_AUTHORITY_TYPES.has(String(document?.document_type || ''))) {
    return false;
  }
  const routing = config || await getRoutingConfig(
    client,
    document.document_type,
    document.workflow_version || null
  );
  if (!routing) return false;
  return !nextStepFromConfig(routing, Number(document.current_step || 1));
}

async function isActiveMayor(client, userId) {
  const mayor = await resolveActiveMayor(client, todayInHrmsTimezone());
  return Boolean(mayor && sameEntityId(mayor.employee_id, userId));
}

function nextStepFromConfig(config, currentStep) {
  const steps = parseSteps(config?.steps || []);
  for (let order = currentStep + 1; order <= steps.length; order += 1) {
    const s = steps.find((step) => step.step_order === order) || null;
    if (!s) continue;
    if (s.enabled === false) continue;
    return s;
  }
  return null;
}

function previousStepFromConfig(config, currentStep) {
  const steps = parseSteps(config?.steps || []);
  for (let order = currentStep - 1; order >= 1; order -= 1) {
    const s = steps.find((step) => step.step_order === order) || null;
    if (!s) continue;
    if (s.enabled === false) continue;
    return s;
  }
  return null;
}

async function transitionDocument(pool, user, documentId, action, payload = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const docRes = await client.query(
      'SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE',
      [documentId]
    );
    if (!docRes.rowCount) {
      throw notFoundError('Document not found');
    }

    const doc = docRes.rows[0];
    const status = normalizeStatus(doc.status);
    const step = Number(doc.current_step || 1);
    const idempotencyKey =
      typeof payload.idempotency_key === 'string' && payload.idempotency_key.trim()
        ? payload.idempotency_key.trim()
        : null;
    const canView = await ensureDocumentViewAccess(client, doc, user);
    if (!canView) {
      throw forbiddenError('You do not have access to this document');
    }

    if (idempotencyKey) {
      const previousRequest = await client.query(
        `SELECT actor_id, response_payload
         FROM docutracker_transition_requests
         WHERE document_id = $1
           AND action = $2
           AND idempotency_key = $3
         LIMIT 1`,
        [documentId, action, idempotencyKey]
      );
      if (previousRequest.rowCount > 0) {
        const previous = previousRequest.rows[0];
        if (previous.actor_id && previous.actor_id !== user.id) {
          throw forbiddenError('Idempotency key already used by a different actor');
        }
        await client.query('COMMIT');
        return previous.response_payload || mapDocumentRow(doc);
      }
    }

    if (TERMINAL_STATUSES.has(status)) {
      throw validationError(`Cannot ${action} document in ${status} status`);
    }
    ensureActionAllowedFromStatus(action, status);

    if (action === 'approve' && MAYOR_FINAL_AUTHORITY_TYPES.has(String(doc.document_type || ''))) {
      const finalApproval = await isMayorFinalApproval(client, { document: doc });
      if (
        finalApproval &&
        (await canUserPerformWorkflowAction(client, { user, document: doc, action })) &&
        !(await isActiveMayor(client, user.id))
      ) {
        throw forbiddenError('Only the Mayor can give final approval and issue this Memo.');
      }
      if (
        finalApproval &&
        !(await hasUserSignedDocument(client, { documentId, userId: user.id }))
      ) {
        throw validationError('Sign the Memo before giving final approval.');
      }
    }

    if (WORKFLOW_STEP_ACTIONS.has(action)) {
      const holderStatus = await getDepartmentReviewHolderStatus(client, doc);
      if (holderStatus && !holderStatus.holderEligible) {
        throw validationError(DEPARTMENT_REVIEW_REASSIGNMENT_MESSAGE);
      }
    }

    const allowed = await canUserPerformDocumentAction(client, {
      user,
      document: doc,
      action,
    });
    if (!allowed) {
      throw forbiddenError(`You do not have permission to ${action} this document`);
    }

    if (action === 'submit' && user.role !== 'admin') {
      if (doc.created_by !== user.id) {
        throw forbiddenError('Only the document creator can submit this document');
      }
      if (!isDraftOrWipDocument(doc, status)) {
        throw validationError('Only an unassigned draft can be submitted');
      }
    }

    const config = await getRoutingConfig(
      client,
      doc.document_type,
      doc.workflow_version || null
    );
    const steps = ensureValidWorkflowConfig(config, doc.document_type);
    const currentConfigStep = getStepByOrder(steps, step);
    if (!currentConfigStep) {
      throw validationError(
        `Document step ${step} is not valid for configured workflow '${doc.document_type}'`
      );
    }

    if (WORKFLOW_STEP_ACTIONS.has(action)) {
      const allowedWorkflow = await canUserPerformWorkflowAction(client, {
        user,
        document: doc,
        action,
      });
      if (!allowedWorkflow) {
        throw forbiddenError(
          'Only an assigned reviewer for the current workflow step can perform this action'
        );
      }
      if (
        STEP_SIGNATURE_GATED_ACTIONS.has(action) &&
        currentConfigStep.requires_signature === true &&
        !(await hasUserSignedDocument(client, { documentId, userId: user.id }))
      ) {
        throw validationError(
          `This step requires your signature. Open the document and sign it before you ${action}.`
        );
      }
    }
    if (action !== 'submit' && !doc.current_holder_id) {
      // current_holder_id is still used for UI and legacy flows; keep this guard for now.
      throw validationError('Document has no current holder. Reassign before performing this action');
    }

    const reviewHours = config?.review_deadline_hours || 1;
    const now = new Date();
    // Use per-step deadline when moving to a step; fallback to config default.
    const computeDeadline = (stepConfig) => {
      const hrs = Number(stepConfig?.deadline_hours ?? reviewHours);
      const safe = Number.isFinite(hrs) && hrs > 0 ? hrs : reviewHours;
      return new Date(now.getTime() + safe * 60 * 60 * 1000);
    };
    let nextDeadline = new Date(now.getTime() + reviewHours * 60 * 60 * 1000);

    let nextStatus = status;
    let nextStep = step;
    let nextHolder = doc.current_holder_id;
    let nextStepAssignees = [];
    let historyAction = action;
    let notificationType = null;
    let transitionExplicitSanitized = null;

    if (action === 'submit') {
      nextStatus = 'in_review';
      nextStep = 1;
      const stepOne = getStepByOrder(steps, 1);
      nextDeadline = computeDeadline(stepOne);
      transitionExplicitSanitized = await sanitizeExplicitAssigneeId(
        client,
        user,
        payload.current_holder_id || payload.target_holder_id,
        {
          stepConfig: stepOne,
          currentHolderId: doc.current_holder_id || user.id,
          documentType: doc.document_type,
          workflowVersion: doc.workflow_version || (config?.version ?? null),
          submitterUserId: doc.created_by || null,
        }
      );
      const stepOneAssignees = await resolveStepAssignees(client, {
        explicitAssigneeId: transitionExplicitSanitized,
        stepConfig: stepOne,
        currentHolderId: doc.current_holder_id || user.id,
        documentType: doc.document_type,
        workflowVersion: doc.workflow_version || (config?.version ?? null),
        submitterUserId: doc.created_by || null,
      });
      nextHolder = stepOneAssignees[0] || null;
      nextStepAssignees = stepOneAssignees;
      if (!nextHolder) {
        throw validationError('No valid next assignee exists for step 1');
      }
      historyAction = 'submitted';
      notificationType = 'assigned';
    } else if (action === 'forward') {
      const nextCfgStep = nextStepFromConfig(config, step);
      if (!nextCfgStep) {
        throw validationError('Cannot forward from last workflow step');
      }
      nextStep = nextCfgStep.step_order;
      nextDeadline = computeDeadline(nextCfgStep);
      transitionExplicitSanitized = await sanitizeExplicitAssigneeId(
        client,
        user,
        payload.current_holder_id || payload.target_holder_id,
        {
          stepConfig: nextCfgStep,
          currentHolderId: doc.current_holder_id,
          documentType: doc.document_type,
          workflowVersion: doc.workflow_version || (config?.version ?? null),
          submitterUserId: doc.created_by || null,
        }
      );
      const nextAssignees = await resolveStepAssignees(client, {
        explicitAssigneeId: transitionExplicitSanitized,
        stepConfig: nextCfgStep,
        currentHolderId: doc.current_holder_id,
        documentType: doc.document_type,
        workflowVersion: doc.workflow_version || (config?.version ?? null),
        submitterUserId: doc.created_by || null,
      });
      nextHolder = nextAssignees[0] || null;
      nextStepAssignees = nextAssignees;
      if (!nextHolder) {
        throw validationError(`No valid next assignee exists for step ${nextStep}`);
      }
      // Keep document in a consistent "active" state while routing.
      nextStatus = 'in_review';
      historyAction = 'forwarded';
      notificationType = 'assigned';
    } else if (action === 'approve') {
      const nextCfgStep = nextStepFromConfig(config, step);
      if (!nextCfgStep) {
        nextStatus = 'approved';
        nextStep = step;
        nextHolder = null;
      } else {
        nextStatus = 'in_review';
        nextStep = nextCfgStep.step_order;
        nextDeadline = computeDeadline(nextCfgStep);
        transitionExplicitSanitized = await sanitizeExplicitAssigneeId(
          client,
          user,
          payload.current_holder_id || payload.target_holder_id,
          {
            stepConfig: nextCfgStep,
            currentHolderId: doc.current_holder_id,
            documentType: doc.document_type,
            workflowVersion: doc.workflow_version || (config?.version ?? null),
            submitterUserId: doc.created_by || null,
          }
        );
        const nextAssignees = await resolveStepAssignees(client, {
          explicitAssigneeId: transitionExplicitSanitized,
          stepConfig: nextCfgStep,
          currentHolderId: doc.current_holder_id,
          documentType: doc.document_type,
          workflowVersion: doc.workflow_version || (config?.version ?? null),
          submitterUserId: doc.created_by || null,
        });
        nextHolder = nextAssignees[0] || null;
        nextStepAssignees = nextAssignees;
        if (!nextHolder) {
          throw validationError(`No valid next assignee exists for step ${nextStep}`);
        }
        notificationType = 'assigned';
      }
      historyAction = 'approved';
    } else if (action === 'reject') {
      nextStatus = 'rejected';
      nextHolder = null;
      historyAction = 'rejected';
      notificationType = 'rejected';
    } else if (action === 'return') {
      if (step <= 1) {
        throw validationError('Cannot return document from first step');
      }
      const previousCfgStep = previousStepFromConfig(config, step);
      if (!previousCfgStep) {
        throw validationError('Cannot return: no previous enabled step found');
      }
      const previousStep = previousCfgStep.step_order;
      const previousRecordRes = await client.query(
        `SELECT assignee_id
         FROM docutracker_routing_records
         WHERE document_id = $1
           AND step_order = $2
         ORDER BY updated_at DESC NULLS LAST, created_at DESC
         LIMIT 1`,
        [documentId, previousStep]
      );
      let previousAssignee = previousRecordRes.rows[0]?.assignee_id || null;
      if (!previousAssignee) {
        transitionExplicitSanitized = await sanitizeExplicitAssigneeId(
          client,
          user,
          payload.current_holder_id || payload.target_holder_id,
          {
            stepConfig: previousCfgStep,
            currentHolderId: doc.created_by,
            documentType: doc.document_type,
            workflowVersion: doc.workflow_version || (config?.version ?? null),
            submitterUserId: doc.created_by || null,
          }
        );
        const previousAssignees = await resolveStepAssignees(client, {
          explicitAssigneeId: transitionExplicitSanitized,
          stepConfig: previousCfgStep,
          currentHolderId: doc.created_by,
          documentType: doc.document_type,
          workflowVersion: doc.workflow_version || (config?.version ?? null),
          submitterUserId: doc.created_by || null,
        });
        previousAssignee = previousAssignees[0] || null;
        nextStepAssignees = previousAssignees;
        if (!previousAssignee) {
          throw validationError(`No valid previous assignee exists for return step ${previousStep}`);
        }
      } else {
        transitionExplicitSanitized = null;
        const validPrevAssignee = await validateAssignee(client, previousAssignee);
        if (!validPrevAssignee) {
          throw validationError(`Invalid assignee '${previousAssignee}' for return step`);
        }
      }

      nextStatus = 'returned';
      nextStep = previousStep;
      nextHolder = previousAssignee;
      nextDeadline = computeDeadline(previousCfgStep);
      historyAction = 'returned';
      notificationType = 'returned';
    } else {
      throw new Error(`Unsupported action ${action}`);
    }

    const docUpdate = await client.query(
      `UPDATE docutracker_documents
       SET status = $1,
           current_step = $2,
           current_holder_id = $3,
           sent_time = $4,
           reviewed_time = CASE WHEN $5 THEN now() ELSE reviewed_time END,
           deadline_time = $6,
           escalation_level = CASE WHEN $7 THEN 0 ELSE escalation_level END,
           needs_admin_intervention = CASE WHEN $8 THEN false ELSE needs_admin_intervention END,
           updated_at = now()
       WHERE id = $9
       RETURNING *`,
      [
        nextStatus,
        nextStep,
        nextHolder,
        now,
        action !== 'submit',
        nextStatus === 'approved' || nextStatus === 'rejected' ? null : nextDeadline,
        nextStatus === 'approved' || nextStatus === 'rejected',
        nextStatus !== 'overdue',
        documentId,
      ]
    );

    const updated = docUpdate.rows[0];

    // Mark the CURRENT step as reviewed/closed when moving away or ending.
    // (Submit is opening step 1, so it should not mark anything reviewed.)
    //
    // Routing row `status` participates in idx_docutracker_routing_records_one_active_per_doc
    // (active = pending|in_review|escalated|overdue). The document's nextStatus is often still
    // `in_review` when handing off to the next step — never write that onto the outgoing step row
    // or we violate one-active-per-document alongside the new step's row.
    if (action !== 'submit') {
      const outgoingRoutingStatus =
        action === 'approve' || action === 'forward' ? 'approved' : nextStatus;
      await client.query(
        `UPDATE docutracker_routing_records
         SET reviewed_time = $3,
             status = $4,
             remarks = COALESCE($5, remarks),
             updated_at = now()
         WHERE document_id = $1
           AND step_order = $2`,
        [documentId, step, now, outgoingRoutingStatus, payload.remarks || null]
      );
    }

    if (nextHolder) {
      // Snapshot the assignee list for this step (allows multiple reviewers).
      const nextStepCfg = getStepByOrder(steps, nextStep);
      // Department review backups are fallback candidates, not co-reviewers.
      const resolvedAssignees = nextStepCfg && isDynamicDepartmentAssigneeSource(nextStepCfg.assignee_source)
        ? [nextHolder]
        : nextStepCfg
        ? await resolveStepAssignees(client, {
            explicitAssigneeId: transitionExplicitSanitized,
            stepConfig: nextStepCfg,
            currentHolderId: nextHolder,
            documentType: doc.document_type,
            workflowVersion: doc.workflow_version || (config?.version ?? null),
            submitterUserId: doc.created_by || null,
          })
        : [nextHolder];
      nextStepAssignees = resolvedAssignees;

      const routingUpsert = await client.query(
        `INSERT INTO docutracker_routing_records
         (document_id, step_order, assignee_id, sent_time, deadline_time, reviewed_time, status, remarks)
         VALUES ($1, $2, $3, now(), $4, $5, $6, $7)
         ON CONFLICT (document_id, step_order)
         DO UPDATE SET assignee_id = EXCLUDED.assignee_id,
                       reviewed_time = EXCLUDED.reviewed_time,
                       sent_time = EXCLUDED.sent_time,
                       deadline_time = EXCLUDED.deadline_time,
                       status = EXCLUDED.status,
                       remarks = EXCLUDED.remarks,
                       updated_at = now()
         RETURNING id`,
        [
          documentId,
          nextStep,
          nextHolder,
          updated.deadline_time,
          null,
          nextStatus,
          payload.remarks || null,
        ]
      );

      const routingRecordId = routingUpsert.rows?.[0]?.id || null;
      if (routingRecordId) {
        await client.query(`DELETE FROM docutracker_routing_record_assignees WHERE routing_record_id = $1`, [
          routingRecordId,
        ]);
        for (const uid of Array.from(new Set(resolvedAssignees)).filter(Boolean)) {
          // eslint-disable-next-line no-await-in-loop
          await client.query(
            `INSERT INTO docutracker_routing_record_assignees (routing_record_id, user_id)
             VALUES ($1, $2)
             ON CONFLICT DO NOTHING`,
            [routingRecordId, uid]
          );
        }
      }
    }

    await insertHistory(client, {
      document_id: documentId,
      action: historyAction,
      actor_id: user.id,
      from_step: step,
      to_step: nextStep,
      from_status: status,
      to_status: nextStatus,
      remarks: payload.remarks || null,
    });

    if (idempotencyKey) {
      await client.query(
        `INSERT INTO docutracker_transition_requests
         (document_id, action, idempotency_key, actor_id, response_payload)
         VALUES ($1, $2, $3, $4, $5::jsonb)
         ON CONFLICT (document_id, action, idempotency_key)
         DO NOTHING`,
        [documentId, action, idempotencyKey, user.id, JSON.stringify(mapDocumentRow(updated))]
      );
    }

    if (notificationType) {
      const notificationEventKey = idempotencyKey
        ? `${notificationType}:doc:${documentId}:step:${nextStep}:req:${idempotencyKey}`
        : null;

      if (notificationType === 'assigned') {
        // Notify ALL assignees for the next step (primary + backups).
        const allNextAssignees = Array.from(new Set(
          [...nextStepAssignees, nextHolder].filter(Boolean)
        ));
        for (const uid of allNextAssignees) {
          // eslint-disable-next-line no-await-in-loop
          await insertNotificationIfNotRecent(client, {
            document_id: documentId,
            user_id: uid,
            type: 'assigned',
            event_key: notificationEventKey,
            step_order: nextStep,
            escalation_level: updated.escalation_level,
            title: 'Document requires your review',
            body: `${doc.title} was forwarded and requires your review.`,
          });
        }
      } else if (notificationType === 'returned') {
        // Notify the current holder (who sent it back) AND the person it's returned to.
        await insertNotificationIfNotRecent(client, {
          document_id: documentId,
          user_id: nextHolder,
          type: 'returned',
          event_key: notificationEventKey,
          step_order: nextStep,
          escalation_level: updated.escalation_level,
          title: 'Document returned to you',
          body: `${doc.title} was returned and requires your attention.`,
        });
      } else if (notificationType === 'rejected') {
        await insertNotificationIfNotRecent(client, {
          document_id: documentId,
          user_id: doc.created_by,
          type: 'rejected',
          event_key: notificationEventKey,
          step_order: nextStep,
          escalation_level: updated.escalation_level,
          title: 'Document rejected',
          body: `${doc.title} was rejected.`,
        });
      }
    }


    await client.query('COMMIT');
    return mapDocumentRow(updated);
  } catch (error) {
    await client.query('ROLLBACK');
    throw wrapDatabaseError(error, 'Unable to process workflow transition due to a database error');
  } finally {
    client.release();
  }
}

async function updateDocumentMetadata(pool, user, documentId, payload = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const docRes = await client.query('SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE', [
      documentId,
    ]);
    if (!docRes.rowCount) {
      throw notFoundError('Document not found');
    }
    const doc = docRes.rows[0];
    const canView = await ensureDocumentViewAccess(client, doc, user);
    if (!canView) {
      throw forbiddenError('You do not have access to this document');
    }

    const canEdit = await canUserPerformDocumentAction(client, {
      user,
      document: doc,
      action: 'edit',
    });
    if (!canEdit) {
      throw forbiddenError('You do not have permission to edit this document');
    }

    const allowedFields = ['title', 'description', 'file_path', 'file_name', 'deadline_time', 'needs_admin_intervention'];
    const updates = [];
    const values = [];
    let i = 1;

    for (const field of allowedFields) {
      if (payload[field] !== undefined) {
        updates.push(`${field} = $${i++}`);
        values.push(payload[field]);
      }
    }
    if (!updates.length) {
      throw validationError('No editable metadata fields provided');
    }
    updates.push('updated_at = now()');
    values.push(documentId);
    const result = await client.query(
      `UPDATE docutracker_documents
       SET ${updates.join(', ')}
       WHERE id = $${i}
       RETURNING *`,
      values
    );
    const updated = result.rows[0];

    await insertHistory(client, {
      document_id: documentId,
      action: 'metadata_updated',
      actor_id: user.id,
      from_step: doc.current_step,
      to_step: updated.current_step,
      from_status: normalizeStatus(doc.status),
      to_status: normalizeStatus(updated.status),
      remarks: payload.remarks || null,
    });

    await client.query('COMMIT');
    return mapDocumentRow(updated);
  } catch (error) {
    await client.query('ROLLBACK');
    throw wrapDatabaseError(error, 'Unable to update document due to a database error');
  } finally {
    client.release();
  }
}

async function recoverDocumentAssignment(pool, user, documentId, payload = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (user?.role !== 'admin') {
      throw forbiddenError('Only administrators can recover a document assignment');
    }
    const docRes = await client.query(
      'SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE',
      [documentId]
    );
    if (!docRes.rowCount) {
      throw notFoundError('Document not found');
    }

    const doc = docRes.rows[0];
    const status = normalizeStatus(doc.status);
    if (!RECOVERABLE_WORKFLOW_STATUSES.has(status)) {
      throw validationError('Only an active workflow document can be reassigned');
    }

    const assigneeId = String(payload.current_holder_id || '').trim();
    const remarks = String(payload.remarks || '').trim();
    if (!assigneeId) {
      throw validationError('current_holder_id is required');
    }
    if (!remarks) {
      throw validationError('Remarks are required for an administrative reassignment');
    }
    if (!(await validateAssignee(client, assigneeId))) {
      throw validationError('The recovery assignee must be an active user');
    }

    const config = await getRoutingConfig(
      client,
      doc.document_type,
      doc.workflow_version || null
    );
    const steps = ensureValidWorkflowConfig(config, doc.document_type);
    const currentStep = Number(doc.current_step || 0);
    const stepConfig = getStepByOrder(steps, currentStep);
    if (!stepConfig || stepConfig.enabled === false) {
      throw validationError(`Document step ${currentStep} is not enabled in its workflow`);
    }

    const configuredAssignee = await getWorkflowStepAssigneeRecord(client, {
      document: doc,
      userId: assigneeId,
      activeOnly: false,
    });
    if (!configuredAssignee || configuredAssignee.is_enabled === false) {
      throw validationError('The recovery assignee is not configured for the current workflow step');
    }

    const routingRes = await client.query(
      `SELECT id
       FROM docutracker_routing_records
       WHERE document_id = $1 AND step_order = $2
       FOR UPDATE`,
      [documentId, currentStep]
    );
    if (!routingRes.rowCount) {
      throw validationError('The current workflow step has no routing record to recover');
    }

    const defaultHours = Number(config?.review_deadline_hours || 1);
    const configuredHours = Number(stepConfig.deadline_hours ?? defaultHours);
    const reviewHours = Number.isFinite(configuredHours) && configuredHours > 0
      ? configuredHours
      : defaultHours;
    const deadline = new Date(Date.now() + reviewHours * 60 * 60 * 1000);

    const updateRes = await client.query(
      `UPDATE docutracker_documents
       SET current_holder_id = $1,
           deadline_time = $2,
           needs_admin_intervention = false,
           updated_at = now()
       WHERE id = $3
       RETURNING *`,
      [assigneeId, deadline, documentId]
    );
    const updated = updateRes.rows[0];
    const routingRecordId = routingRes.rows[0].id;

    await client.query(
      `UPDATE docutracker_routing_records
       SET assignee_id = $1,
           sent_time = now(),
           deadline_time = $2,
           reviewed_time = NULL,
           status = $3,
           remarks = $4,
           updated_at = now()
       WHERE id = $5`,
      [assigneeId, deadline, status, remarks, routingRecordId]
    );

    const resolvedAssignees = isDynamicDepartmentAssigneeSource(stepConfig.assignee_source)
      ? [assigneeId]
      : await resolveStepAssignees(client, {
          explicitAssigneeId: null,
          stepConfig,
          currentHolderId: assigneeId,
          documentType: doc.document_type,
          workflowVersion: doc.workflow_version || config?.version || null,
          submitterUserId: doc.created_by || null,
        });
    const snapshotAssignees = Array.from(
      new Set([...resolvedAssignees, assigneeId].map(String).filter(Boolean))
    );
    await client.query(
      'DELETE FROM docutracker_routing_record_assignees WHERE routing_record_id = $1',
      [routingRecordId]
    );
    for (const snapshotUserId of snapshotAssignees) {
      // eslint-disable-next-line no-await-in-loop
      await client.query(
        `INSERT INTO docutracker_routing_record_assignees (routing_record_id, user_id)
         VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [routingRecordId, snapshotUserId]
      );
    }

    await insertHistory(client, {
      document_id: documentId,
      action: 'assigned',
      actor_id: user.id,
      from_step: currentStep,
      to_step: currentStep,
      from_status: status,
      to_status: status,
      remarks,
    });
    await insertNotification(client, {
      document_id: documentId,
      user_id: assigneeId,
      type: 'assigned',
      event_key: `assigned:recovery:${documentId}:${currentStep}:${Date.now()}`,
      title: 'Document reassigned to you',
      body: `${doc.title || 'A document'} requires your review.`,
    });

    await client.query('COMMIT');
    return mapDocumentRow(updated);
  } catch (error) {
    await client.query('ROLLBACK');
    throw wrapDatabaseError(error, 'Unable to recover document assignment due to a database error');
  } finally {
    client.release();
  }
}

async function addDocumentRemark(pool, user, documentId, payload = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const docRes = await client.query('SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE', [
      documentId,
    ]);
    if (!docRes.rowCount) {
      throw notFoundError('Document not found');
    }
    const doc = docRes.rows[0];
    const canView = await ensureDocumentViewAccess(client, doc, user);
    if (!canView) {
      throw forbiddenError('You do not have access to this document');
    }

    const remarks = String(payload.remarks || '').trim();
    if (!remarks) {
      throw new Error('remarks are required');
    }

    await insertHistory(client, {
      document_id: documentId,
      action: 'remark',
      actor_id: user.id,
      from_step: doc.current_step,
      to_step: doc.current_step,
      from_status: normalizeStatus(doc.status),
      to_status: normalizeStatus(doc.status),
      remarks,
    });

    await client.query('COMMIT');
    return true;
  } catch (error) {
    await client.query('ROLLBACK');
    throw wrapDatabaseError(error, 'Unable to add remark due to a database error');
  } finally {
    client.release();
  }
}

module.exports = {
  DOC_ACTIONS,
  VALID_STATUSES,
  mapDocumentRow,
  sourceActionForRow,
  mapSourceStatusToDocuTracker,
  isReviewedSourceCompletion,
  permissionPriority,
  resolvePermissionDecisionFromRows,
  ensureValidWorkflowConfig,
  hasPermission,
  canUserPerformDocumentAction,
  canAddOwnSignatureToDocument,
  canUserPerformTypeAction,
  filterDocumentsViewableByUser,
  listReviewedDepartments,
  getEffectivePermissionExplanation,
  parseSteps,
  resolveStepAssignees,
  resolveDepartmentReviewEscalation,
  isDraftOrWipDocument,
  listDocuments,
  getDocumentBundle,
  createDocument,
  transitionDocument,
  insertNotificationIfNotRecent,
  updateDocumentMetadata,
  recoverDocumentAssignment,
  addDocumentRemark,
};
