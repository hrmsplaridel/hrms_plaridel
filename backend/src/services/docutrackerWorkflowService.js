const VALID_STATUSES = new Set([
  'pending',
  'in_review',
  'approved',
  'rejected',
  'returned',
  'forwarded',
  'overdue',
  'escalated',
  'cancelled',
]);

const TERMINAL_STATUSES = new Set(['approved', 'rejected', 'cancelled']);
const DOC_ACTIONS = new Set([
  'view',
  'create',
  'edit',
  'download',
  'delete',
  'return',
  'forward',
  'approve',
  'reject',
  'submit',
]);
const TRANSITION_ALLOWED_FROM = {
  submit: new Set(['pending', 'returned']),
  forward: new Set(['in_review', 'forwarded', 'escalated']),
  approve: new Set(['in_review', 'forwarded', 'escalated']),
  reject: new Set(['in_review', 'forwarded', 'escalated']),
  return: new Set(['in_review', 'forwarded', 'escalated']),
};

function normalizeStatus(value) {
  if (!value) return 'pending';
  const s = String(value).toLowerCase().trim().replaceAll(' ', '_');
  if (s === 'inreview') return 'in_review';
  return s;
}

function mapDocumentRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    document_number: row.document_number,
    document_type: row.document_type,
    title: row.title,
    description: row.description,
    source_module: row.source_module,
    source_table: row.source_table,
    source_record_id: row.source_record_id,
    source_title: row.source_title,
    file_path: row.file_path,
    file_name: row.file_name,
    created_by: row.created_by,
    current_holder_id: row.current_holder_id,
    current_step: row.current_step,
    status: normalizeStatus(row.status),
    sent_time: row.sent_time,
    deadline_time: row.deadline_time,
    reviewed_time: row.reviewed_time,
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

async function resolveStepAssignee(client, { explicitAssigneeId, stepConfig, currentHolderId }) {
  const configured = Array.isArray(stepConfig?.user_ids) ? stepConfig.user_ids.filter(Boolean) : [];
  const candidate = explicitAssigneeId || configured[0] || currentHolderId || null;
  if (!candidate) {
    throw validationError(`No valid assignee configured for step ${stepConfig?.step_order ?? 'unknown'}`);
  }
  const valid = await validateAssignee(client, candidate);
  if (!valid) {
    throw validationError(`Invalid assignee '${candidate}'`);
  }
  return candidate;
}

async function getRoutingConfig(client, documentType) {
  const configRes = await client.query(
    `SELECT document_type, steps, review_deadline_hours
     FROM docutracker_routing_configs
     WHERE document_type = $1`,
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
  const permRes = await client.query(
    `SELECT user_id::text AS user_id,
            role_id,
            document_type,
            granted
     FROM docutracker_permissions
     WHERE action = $1
       AND (document_type = $2 OR document_type = '*')
       AND (
         user_id = $3
        OR role_id = ANY($4::text[])
       )`,
    [action, documentType, userId, roleIds]
  );
  return permRes.rows;
}

function permissionPriority(row, { userId, role, documentType }) {
  const isUser = row.user_id && row.user_id === userId;
  const isRole = row.role_id && row.role_id === role;
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
  if (!DOC_ACTIONS.has(action)) return false;
  const rows = await fetchPermissionRows(client, {
    role,
    userId,
    documentType,
    action,
  });
  return resolvePermissionDecisionFromRows(rows, {
    userId,
    role,
    documentType,
  });
}

function getRelationshipFlags(document, user) {
  return {
    isAdmin: user.role === 'admin',
    isCreator: !!document && document.created_by === user.id,
    isReviewer: !!document && document.current_holder_id === user.id,
  };
}

function evaluateRelationshipFallback(action, relationship) {
  if (relationship.isAdmin) return true;
  if (relationship.isReviewer) {
    return new Set(['view', 'forward', 'approve', 'reject', 'return', 'submit']).has(action);
  }
  if (relationship.isCreator) {
    return new Set(['view', 'create', 'submit']).has(action);
  }
  return false;
}

async function canUserPerformDocumentAction(client, { user, document, action }) {
  const relationship = getRelationshipFlags(document, user);
  if (relationship.isAdmin) return true;
  const explicit = await hasPermission(client, {
    role: user.role,
    userId: user.id,
    documentType: document.document_type,
    action,
  });
  if (explicit !== null) return explicit;
  return evaluateRelationshipFallback(action, relationship);
}

async function canUserPerformTypeAction(client, { user, documentType, action }) {
  if (user.role === 'admin') return true;
  const explicit = await hasPermission(client, {
    role: user.role,
    userId: user.id,
    documentType,
    action,
  });
  if (explicit !== null) return explicit;
  // By default, authenticated users can create documents unless explicitly denied.
  return action === 'create';
}

async function getEffectivePermissionExplanation(client, { user, action, documentType, document = null }) {
  const relationship = getRelationshipFlags(document, user);
  const scopeType = document ? 'document' : 'type';
  if (relationship.isAdmin) {
    return {
      scope: scopeType,
      action,
      document_type: documentType,
      explicit_matches: [],
      explicit_decision: true,
      fallback_decision: true,
      final_decision: true,
      reason: 'admin_override',
    };
  }

  const rows = await fetchPermissionRows(client, {
    role: user.role,
    userId: user.id,
    documentType,
    action,
  });
  const ranked = rows
    .map((row) => ({ row, score: permissionPriority(row, { userId: user.id, role: user.role, documentType }) }))
    .filter((entry) => entry.score >= 0)
    .sort((a, b) => b.score - a.score);

  const explicitDecision = ranked.length ? ranked[0].row.granted === true : null;
  const fallbackDecision = scopeType === 'document'
    ? evaluateRelationshipFallback(action, relationship)
    : action === 'create';
  const finalDecision = explicitDecision !== null ? explicitDecision : fallbackDecision;

  return {
    scope: scopeType,
    action,
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
    where.push(`document_type = $${i++}`);
    params.push(filters.type);
  }

  const status = normalizeStatus(filters.status);
  if (filters.status && filters.status !== 'All' && VALID_STATUSES.has(status)) {
    where.push(`status = $${i++}`);
    params.push(status);
  }

  if (filters.holderId) {
    where.push(`current_holder_id = $${i++}`);
    params.push(filters.holderId);
  }
  if (filters.createdBy) {
    where.push(`created_by = $${i++}`);
    params.push(filters.createdBy);
  }
  if (filters.sourceModule) {
    where.push(`source_module = $${i++}`);
    params.push(filters.sourceModule);
  }
  if (filters.sourceTable) {
    where.push(`source_table = $${i++}`);
    params.push(filters.sourceTable);
  }
  if (filters.q) {
    where.push(
      `(title ILIKE $${i} OR description ILIKE $${i} OR COALESCE(source_title, '') ILIKE $${i} OR COALESCE(document_number, '') ILIKE $${i})`
    );
    params.push(`%${filters.q}%`);
    i += 1;
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const { limitVal, offsetVal } = parseLimitOffset(filters);
  params.push(limitVal, offsetVal);

  const result = await pool.query(
    `SELECT *
     FROM docutracker_documents
     ${whereSql}
     ORDER BY created_at DESC
     LIMIT $${i} OFFSET $${i + 1}`,
    params
  );
  let baseRows = result.rows;
  if (user.role !== 'admin') {
    const visibilityChecks = await Promise.all(
      result.rows.map((row) =>
        canUserPerformDocumentAction(pool, {
          user,
          document: row,
          action: 'view',
        })
      )
    );
    baseRows = result.rows.filter((_, index) => visibilityChecks[index]);
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
      action: 'create',
    });
    if (!canCreate) {
      throw forbiddenError('You do not have permission to create this document type');
    }

    const routingConfig = await getRoutingConfig(client, input.document_type);
    const steps = ensureValidWorkflowConfig(routingConfig, input.document_type);
    const reviewHours = routingConfig?.review_deadline_hours || 1;
    const now = new Date();
    const deadline = input.deadline_time
      ? new Date(input.deadline_time)
      : new Date(now.getTime() + reviewHours * 60 * 60 * 1000);
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

    const currentHolder = await resolveStepAssignee(client, {
      explicitAssigneeId: input.current_holder_id,
      stepConfig: getStepByOrder(steps, 1),
      currentHolderId: user.id,
    });
    const initialStatus = normalizeStatus(input.status || 'pending');
    if (!VALID_STATUSES.has(initialStatus)) {
      throw new Error('Invalid status');
    }

    const docRes = await client.query(
      `INSERT INTO docutracker_documents
       (document_number, document_type, title, description,
        source_module, source_table, source_record_id, source_title,
        file_path, file_name, created_by, current_holder_id, current_step,
        status, sent_time, deadline_time)
       VALUES ($1, $2, $3, $4,
               $5, $6, $7, $8,
               $9, $10, $11, $12, 1,
               $13, now(), $14)
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
        currentHolder,
        initialStatus,
        deadline,
      ]
    );

    const doc = docRes.rows[0];

    await client.query(
      `INSERT INTO docutracker_routing_records
       (document_id, step_order, assignee_id, sent_time, deadline_time, status, remarks)
       VALUES ($1, 1, $2, now(), $3, $4, $5)
       ON CONFLICT (document_id, step_order)
       DO UPDATE SET assignee_id = EXCLUDED.assignee_id,
                     sent_time = EXCLUDED.sent_time,
                     deadline_time = EXCLUDED.deadline_time,
                     status = EXCLUDED.status,
                     remarks = EXCLUDED.remarks,
                     updated_at = now()`,
      [doc.id, currentHolder, deadline, initialStatus, 'Initial assignment']
    );

    await insertHistory(client, {
      document_id: doc.id,
      action: 'created',
      actor_id: user.id,
      to_step: 1,
      to_status: initialStatus,
      remarks: input.description || null,
    });

    await insertNotificationIfNotRecent(client, {
      document_id: doc.id,
      user_id: currentHolder,
      type: 'assigned',
      step_order: 1,
      title: 'New document assigned',
      body: `${doc.title} requires your review.`,
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
  return steps.find((step) => step.step_order === currentStep + 1) || null;
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

    const config = await getRoutingConfig(client, doc.document_type);
    const steps = ensureValidWorkflowConfig(config, doc.document_type);
    const currentConfigStep = getStepByOrder(steps, step);
    if (!currentConfigStep) {
      throw validationError(
        `Document step ${step} is not valid for configured workflow '${doc.document_type}'`
      );
    }

    if (user.role !== 'admin' && doc.current_holder_id && doc.current_holder_id !== user.id) {
      throw validationError('Only the current holder can perform this action');
    }
    if (action !== 'submit' && !doc.current_holder_id && user.role !== 'admin') {
      throw validationError('Document has no current holder. Reassign before performing this action');
    }

    const reviewHours = config?.review_deadline_hours || 1;
    const now = new Date();
    const nextDeadline = new Date(now.getTime() + reviewHours * 60 * 60 * 1000);

    let nextStatus = status;
    let nextStep = step;
    let nextHolder = doc.current_holder_id;
    let historyAction = action;
    let notificationType = null;

    if (action === 'submit') {
      nextStatus = 'in_review';
      nextStep = 1;
      const stepOne = getStepByOrder(steps, 1);
      nextHolder = await resolveStepAssignee(client, {
        explicitAssigneeId: payload.current_holder_id || payload.target_holder_id,
        stepConfig: stepOne,
        currentHolderId: doc.current_holder_id || user.id,
      });
      historyAction = 'submitted';
      notificationType = 'assigned';
    } else if (action === 'forward') {
      const nextCfgStep = nextStepFromConfig(config, step);
      if (!nextCfgStep) {
        throw validationError('Cannot forward from last workflow step');
      }
      nextStep = nextCfgStep.step_order;
      nextHolder = await resolveStepAssignee(client, {
        explicitAssigneeId: payload.current_holder_id || payload.target_holder_id,
        stepConfig: nextCfgStep,
        currentHolderId: doc.current_holder_id,
      });
      nextStatus = 'forwarded';
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
        nextHolder = await resolveStepAssignee(client, {
          explicitAssigneeId: payload.current_holder_id || payload.target_holder_id,
          stepConfig: nextCfgStep,
          currentHolderId: doc.current_holder_id,
        });
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
      const previousStep = step - 1;
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
        const previousCfgStep = getStepByOrder(steps, previousStep);
        previousAssignee = await resolveStepAssignee(client, {
          explicitAssigneeId: payload.current_holder_id || payload.target_holder_id,
          stepConfig: previousCfgStep,
          currentHolderId: doc.created_by,
        });
      } else {
        const validPrevAssignee = await validateAssignee(client, previousAssignee);
        if (!validPrevAssignee) {
          throw validationError(`Invalid assignee '${previousAssignee}' for return step`);
        }
      }

      nextStatus = 'returned';
      nextStep = previousStep;
      nextHolder = previousAssignee;
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
           updated_at = now()
       WHERE id = $7
       RETURNING *`,
      [
        nextStatus,
        nextStep,
        nextHolder,
        now,
        action !== 'submit',
        nextStatus === 'approved' || nextStatus === 'rejected' ? doc.deadline_time : nextDeadline,
        documentId,
      ]
    );

    const updated = docUpdate.rows[0];

    if (nextHolder) {
      await client.query(
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
                       updated_at = now()`,
        [
          documentId,
          nextStep,
          nextHolder,
          updated.deadline_time,
          action === 'submit' ? null : now,
          nextStatus,
          payload.remarks || null,
        ]
      );
    } else {
      await client.query(
        `UPDATE docutracker_routing_records
         SET reviewed_time = $3,
             status = $4,
             remarks = $5,
             updated_at = now()
         WHERE document_id = $1
           AND step_order = $2`,
        [documentId, step, now, nextStatus, payload.remarks || null]
      );
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
      let targetUserId = null;
      if (notificationType === 'assigned') {
        targetUserId = nextHolder;
      } else if (notificationType === 'returned') {
        targetUserId = nextHolder;
      } else if (notificationType === 'rejected') {
        targetUserId = doc.created_by;
      }
      await insertNotificationIfNotRecent(client, {
        document_id: documentId,
        user_id: targetUserId,
        type: notificationType,
        step_order: nextStep,
        escalation_level: updated.escalation_level,
        title:
          notificationType === 'assigned'
            ? 'Document requires your review'
            : `Document ${notificationType}`,
        body: `${doc.title} was ${historyAction}.`,
      });
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
