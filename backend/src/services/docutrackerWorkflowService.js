const { coalesceDocumentTitle } = require('../utils/docutrackerDisplayTitle');
const { sameEntityId } = require('../utils/sameEntityId');

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
  submit: new Set(['draft', 'pending', 'returned']),
  forward: new Set(['in_review', 'escalated', 'overdue']),
  approve: new Set(['in_review', 'escalated', 'overdue']),
  reject: new Set(['in_review', 'escalated', 'overdue']),
  return: new Set(['in_review', 'escalated', 'overdue']),
};

function normalizeStatus(value) {
  if (!value) return 'pending';
  const s = String(value).toLowerCase().trim().replaceAll(' ', '_');
  if (s === 'inreview') return 'in_review';
  // Backward-compatibility: treat legacy 'forwarded' as active in_review.
  if (s === 'forwarded') return 'in_review';
  return s;
}

function mapDocumentRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    document_number: row.document_number,
    document_type: row.document_type,
    title: coalesceDocumentTitle(row),
    description: row.description,
    source_module: row.source_module,
    source_table: row.source_table,
    source_record_id: row.source_record_id,
    source_title: row.source_title,
    file_path: row.file_path,
    file_name: row.file_name,
    created_by: row.created_by,
    creator_name: row.creator_name ?? null,
    current_holder_id: row.current_holder_id,
    current_step: row.current_step,
    status: normalizeStatus(row.status),
    sent_time: row.sent_time,
    deadline_time: row.deadline_time,
    reviewed_time: row.reviewed_time,
    workflow_version: row.workflow_version,
    escalation_level: row.escalation_level,
    needs_admin_intervention: row.needs_admin_intervention,
    source_only: row.source_only === true,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function mapSourceStatusToDocuTracker(sourceModule, sourceStatus) {
  const status = String(sourceStatus || '').toLowerCase().trim();
  if (!status) return 'pending';

  if (sourceModule === 'ld') {
    if (status === 'approved') return 'approved';
    if (status === 'needs_revision') return 'returned';
    if (status === 'seen' || status === 'reviewed') return 'in_review';
    return 'pending';
  }

  if (sourceModule === 'rsp') {
    if (status === 'document_declined' || status === 'failed') return 'rejected';
    if (status === 'registered' || status === 'passed') return 'approved';
    if (status === 'document_approved' || status === 'exam_taken') return 'in_review';
    return 'pending';
  }

  if (sourceModule === 'dtr') {
    if (status === 'approved') return 'approved';
    if (status === 'returned') return 'returned';
    if (status === 'rejected') return 'rejected';
    if (status === 'cancelled') return 'cancelled';
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
       WHERE ${dtrWhere.join(' AND ')}`,
      dtrParams
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
         l.status AS source_status
       FROM leave_requests l
       JOIN users u ON u.id = COALESCE(l.user_id, l.employee_id)
       WHERE ${
         user.role === 'admin'
           ? '1=1'
           : '(l.user_id = $1::uuid OR l.employee_id = $1::uuid)'
       }`,
      user.role === 'admin' ? [] : [user.id]
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
       FROM recruitment_applications a`
    );
    pieces.push(...rspRows);
  }

  const q = String(filters.q || '').toLowerCase().trim();
  const statusFilter = normalizeStatus(filters.status);

  const rows = pieces
    .map((row) => {
      const mappedStatus = mapSourceStatusToDocuTracker(row.source_module, row.source_status);
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
        created_at: row.created_at,
        updated_at: row.updated_at,
      };
    })
    .filter((row) => {
      if (filters.status && filters.status !== 'All' && VALID_STATUSES.has(statusFilter)) {
        if (normalizeStatus(row.status) !== statusFilter) return false;
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
      user_ids: Array.isArray(step.user_ids)
        ? step.user_ids
        : Array.isArray(step.userIds)
          ? step.userIds
          : [],
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
    throw validationError(`${action} is not valid from status ${status}`);
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

function ensureValidWorkflowConfig(config, documentType) {
  if (!config) {
    throw validationError(`Missing workflow config for document_type '${documentType}'`);
  }
  const steps = parseSteps(config.steps || []);
  if (!steps.length) {
    throw validationError(`Workflow config for '${documentType}' has no steps`);
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
  const { stepConfig, currentHolderId, documentType, workflowVersion } = ctx;
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

async function getRoutingConfig(client, documentType, workflowVersion = null) {
  if (workflowVersion != null) {
    const r = await client.query(
      `SELECT document_type, steps, review_deadline_hours, version
       FROM docutracker_routing_config_versions
       WHERE document_type = $1
         AND version = $2
       LIMIT 1`,
      [documentType, workflowVersion]
    );
    if (r.rowCount > 0) return r.rows[0];
  }

  // Fallback: latest version.
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
 * Filters document rows the same way canUserPerformDocumentAction(..., 'view') would,
 * using batched queries + a narrow fallback to isUserAssignedToCurrentStep when needed.
 */
async function filterDocumentsViewableByUser(pool, user, rows) {
  if (!rows?.length || user?.role === 'admin') return rows || [];
  const uid = user.id;
  const role = user.role;
  const roleIds = getRoleVariants(role);

  const ids = rows.map((r) => r.id).filter(Boolean);
  const allPermRows = await fetchAllPermissionRowsForAction(pool, {
    role,
    userId: uid,
    action: 'view',
  });

  let assigneeIdSet = new Set();
  if (ids.length) {
    const ar = await pool.query(
      `SELECT DISTINCT d.id
       FROM docutracker_documents d
       INNER JOIN docutracker_routing_records rr
         ON rr.document_id = d.id AND rr.step_order = d.current_step
       INNER JOIN docutracker_routing_record_assignees a
         ON a.routing_record_id = rr.id AND a.user_id = $1::uuid
       WHERE d.id = ANY($2::uuid[])`,
      [uid, ids]
    );
    assigneeIdSet = new Set(ar.rows.map((x) => x.id));
  }

  const uniqueTypes = [...new Set(rows.map((r) => r.document_type).filter(Boolean))];
  const viewAllowedByType = new Map();
  for (const dt of uniqueTypes) {
    const rowsForType = allPermRows.filter((r) => r.document_type === dt || r.document_type === '*');
    const decision = resolvePermissionDecisionFromRows(rowsForType, {
      userId: uid,
      roleIds,
      documentType: dt,
    });
    viewAllowedByType.set(dt, decision === true);
  }

  const needFallback = [];
  const out = [];
  for (const row of rows) {
    const rel = getRelationshipFlags(row, user);
    if (rel.isCreator || rel.isReviewer) {
      out.push(row);
      continue;
    }
    if (assigneeIdSet.has(row.id)) {
      out.push(row);
      continue;
    }
    const allow = viewAllowedByType.get(row.document_type);
    if (allow === true) {
      out.push(row);
      continue;
    }
    needFallback.push(row);
  }

  if (!needFallback.length) return out;

  const fallbackChecks = await Promise.all(
    needFallback.map((row) =>
      isUserAssignedToCurrentStep(pool, { document: row, userId: uid }).catch(() => false)
    )
  );
  for (let i = 0; i < needFallback.length; i += 1) {
    if (fallbackChecks[i]) out.push(needFallback[i]);
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
const GENERAL_PERMISSION_ACTIONS = new Set(['view', 'create', 'create_draft', 'download']);

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

async function getWorkflowStepAssigneeRecord(client, { document, userId }) {
  if (!document || !userId) return null;
  const step = Number(document.current_step || 1);
  const docType = document.document_type;

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
         AND a.user_id = $3::uuid
       LIMIT 1`,
      [docType, step, userId]
    );
  }
  return r.rows?.[0] || null;
}



function assigneeAllowsAction(assigneeRow, action) {
  if (!assigneeRow) return null; // unknown (likely legacy config)
  if (assigneeRow.is_enabled === false) return false;
  const allowed = Array.isArray(assigneeRow.allowed_actions) ? assigneeRow.allowed_actions : [];
  // Treat empty allowed_actions as "allow all workflow actions" for backward compatibility.
  if (allowed.length === 0) return true;
  return allowed.includes(action);
}

async function canUserPerformWorkflowAction(client, { user, document, action }) {
  if (!WORKFLOW_STEP_ACTIONS.has(action)) return false;
  if (user?.role === 'admin') return true;
  if (isCurrentHolder(document, user.id)) return true;

  // Prefer normalized table restrictions when available.
  const row = await getWorkflowStepAssigneeRecord(client, { document, userId: user.id });
  const allowedByRow = assigneeAllowsAction(row, action);
  if (allowedByRow === true) return true;
  if (allowedByRow === false) return false;

  // Fallback to legacy behavior (no per-action assignments): holder or step assignee.
  return isUserAssignedToCurrentStep(client, { document, userId: user.id });
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

async function resolveStepAssignees(client, { explicitAssigneeId, stepConfig, currentHolderId, documentType, workflowVersion }) {
  const type = String(stepConfig?.assignee_type || '').trim().toLowerCase();

  // Explicit assignee (must be pre-sanitized at workflow entry points for non-admins).
  if (explicitAssigneeId) {
    const valid = await validateAssignee(client, explicitAssigneeId);
    if (!valid) throw validationError(`Invalid assignee '${explicitAssigneeId}'`);
    return [explicitAssigneeId];
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
    });
    return assignees.includes(userId);
  } catch (_) {
    return false;
  }
}

async function isUserAssignedToAnyStep(client, { document, userId }) {
  if (!document || !userId) return false;
  try {
    // Check if the user is assigned to ANY step in the committed routing records.
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

async function canUserPerformDocumentAction(client, { user, document, action }) {
  const relationship = getRelationshipFlags(document, user);
  if (relationship.isAdmin) return true;

  const status = normalizeStatus(document.status);
  const isWip = isDraftOrWipDocument(document, status);

  // WIP (Draft) logic:
  if (isWip) {
    // Creator can view, edit, or delete their own draft.
    if (action === 'view' || action === 'edit' || action === 'delete') {
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

  // Workflow actions: ONLY admin OR current holder OR assigned-to-step.
  if (WORKFLOW_STEP_ACTIONS.has(action)) {
    return canUserPerformWorkflowAction(client, { user, document, action });
  }

  // General type-level actions: view/create/download are permission-table driven.
  if (GENERAL_PERMISSION_ACTIONS.has(action)) {
    // View has extra "relationship" allowances on a specific document.
    if (action === 'view') {
      if (relationship.isCreator || relationship.isReviewer) return true;
      if (await isUserAssignedToCurrentStep(client, { document, userId: user.id })) return true;
      if (await isUserAssignedToAnyStep(client, { document, userId: user.id })) return true;
    }
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
  if (relationship.isAdmin) {
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
    const allowed = await canUserPerformWorkflowAction(client, {
      user,
      document,
      action: canonicalAction,
    });
    const reason = allowed
      ? (isHolder
          ? 'current_holder'
          : allowedByAssignedRule === false
              ? 'assigned_but_action_not_allowed'
              : 'step_assignee')
      : (allowedByAssignedRule === false
          ? 'assigned_but_action_not_allowed'
          : 'not_assigned_to_step');
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

  const explicitDecision = ranked.length ? ranked[0].row.granted === true : null;
  const fallbackDecision = scopeType === 'document'
    ? (canonicalAction === 'view' && (relationship.isCreator || relationship.isReviewer))
    : false;
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

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const { limitVal, offsetVal } = parseLimitOffset(filters);
  params.push(limitVal, offsetVal);

  const result = await pool.query(
    `SELECT d.*, creator.full_name AS creator_name
     FROM docutracker_documents d
     LEFT JOIN users creator ON creator.id = d.created_by
     ${whereSql}
     ORDER BY d.created_at DESC
     LIMIT $${i} OFFSET $${i + 1}`,
    params
  );
  let baseRows = result.rows;
  if (user.role !== 'admin') {
    baseRows = await filterDocumentsViewableByUser(pool, user, result.rows);
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

  const [routingResult, historyResult] = await Promise.all([
    pool.query(
      `SELECT *
       FROM docutracker_routing_records
       WHERE document_id = $1
       ORDER BY step_order ASC`,
      [id]
    ),
    pool.query(
      `SELECT *
       FROM docutracker_document_history
       WHERE document_id = $1
       ORDER BY created_at ASC`,
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

function buildNotificationEventKey(payload = {}) {
  const docId = payload.document_id || 'unknown-doc';
  const type = payload.type || 'unknown';
  if (type === 'assigned') {
    return `assigned:doc:${docId}:step:${payload.step_order ?? 'na'}`;
  }
  if (type === 'returned') {
    return `returned:doc:${docId}:step:${payload.step_order ?? 'na'}`;
  }
  if (type === 'rejected') {
    return `rejected:doc:${docId}:step:${payload.step_order ?? 'na'}`;
  }
  if (type === 'escalated') {
    return `escalated:doc:${docId}:level:${payload.escalation_level ?? 'na'}`;
  }
  if (type === 'overdue') {
    return `overdue:doc:${docId}:level:${payload.escalation_level ?? 'na'}`;
  }
  return `${type}:doc:${docId}`;
}

async function insertNotificationIfNotRecent(client, payload, dedupeMinutes = 15) {
  if (!payload.user_id) return false;
  const eventKey = payload.event_key || buildNotificationEventKey(payload);
  if (eventKey) {
    const byKey = await client.query(
      `SELECT id
       FROM docutracker_notifications
       WHERE document_id = $1
         AND user_id = $2
         AND type = $3
         AND event_key = $4
       LIMIT 1`,
      [payload.document_id, payload.user_id, payload.type, eventKey]
    );
    if (byKey.rowCount > 0) return false;
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
  await insertNotification(client, { ...payload, event_key: eventKey });
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

    const docRes = await client.query(
      `INSERT INTO docutracker_documents
       (document_number, document_type, title, description,
        source_module, source_table, source_record_id, source_title,
        file_path, file_name, created_by, current_holder_id, current_step,
        status, sent_time, deadline_time, workflow_version)
       VALUES ($1, $2, $3, $4,
               $5, $6, $7, $8,
               $9, $10, $11, NULL, NULL,
               $12, NULL, NULL, $13)
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
        initialStatus,
        workflowVersion,
      ]
    );

    const doc = docRes.rows[0];

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

    const allowed = await canUserPerformDocumentAction(client, {
      user,
      document: doc,
      action,
    });
    if (!allowed) {
      throw forbiddenError(`You do not have permission to ${action} this document`);
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

    if (WORKFLOW_STEP_ACTIONS.has(action) && user.role !== 'admin') {
      const allowedWorkflow = await canUserPerformWorkflowAction(client, {
        user,
        document: doc,
        action,
      });
      if (!allowedWorkflow) {
        throw validationError(
          'Only the current holder or an assigned reviewer for the current workflow step can perform this action'
        );
      }
    }
    if (action !== 'submit' && !doc.current_holder_id && user.role !== 'admin') {
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
        }
      );
      const stepOneAssignees = await resolveStepAssignees(client, {
        explicitAssigneeId: transitionExplicitSanitized,
        stepConfig: stepOne,
        currentHolderId: doc.current_holder_id || user.id,
        documentType: doc.document_type,
        workflowVersion: doc.workflow_version || (config?.version ?? null),
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
        }
      );
      const nextAssignees = await resolveStepAssignees(client, {
        explicitAssigneeId: transitionExplicitSanitized,
        stepConfig: nextCfgStep,
        currentHolderId: doc.current_holder_id,
        documentType: doc.document_type,
        workflowVersion: doc.workflow_version || (config?.version ?? null),
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
          }
        );
        const nextAssignees = await resolveStepAssignees(client, {
          explicitAssigneeId: transitionExplicitSanitized,
          stepConfig: nextCfgStep,
          currentHolderId: doc.current_holder_id,
          documentType: doc.document_type,
          workflowVersion: doc.workflow_version || (config?.version ?? null),
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
          }
        );
        const previousAssignees = await resolveStepAssignees(client, {
          explicitAssigneeId: transitionExplicitSanitized,
          stepConfig: previousCfgStep,
          currentHolderId: doc.created_by,
          documentType: doc.document_type,
          workflowVersion: doc.workflow_version || (config?.version ?? null),
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
      const resolvedAssignees = nextStepCfg
        ? await resolveStepAssignees(client, {
            explicitAssigneeId: transitionExplicitSanitized,
            stepConfig: nextStepCfg,
            currentHolderId: nextHolder,
            documentType: doc.document_type,
            workflowVersion: doc.workflow_version || (config?.version ?? null),
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
      throw new Error('No editable fields provided');
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
  permissionPriority,
  resolvePermissionDecisionFromRows,
  ensureValidWorkflowConfig,
  hasPermission,
  canUserPerformDocumentAction,
  canUserPerformTypeAction,
  getEffectivePermissionExplanation,
  listDocuments,
  getDocumentBundle,
  createDocument,
  transitionDocument,
  updateDocumentMetadata,
  addDocumentRemark,
};
