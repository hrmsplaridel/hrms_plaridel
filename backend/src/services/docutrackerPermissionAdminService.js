const { writeGovernanceAudit } = require('./docutrackerGovernanceAudit');
const { defaultRolePermissions } = require('./docutrackerPermissionDefaults');
const {
  RELEASE_ACTION,
  SYSTEM_ACCESS_ACTIONS,
} = require('./docutrackerSystemAccessActions');
const {
  getEffectivePermissionExplanation,
  getRoleVariants,
  permissionPriority,
  resolveUserSpecificPermissionFromRows,
} = require('./docutrackerWorkflowService');

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const BUILT_IN_DOCUMENT_TYPES = new Set(['memo', 'purchaseRequest']);
const CANONICAL_ROLES = new Set(['admin', 'hr', 'supervisor', 'employee']);
const SYSTEM_PERMISSION_ACTIONS = SYSTEM_ACCESS_ACTIONS;

class PermissionAdminError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.name = 'PermissionAdminError';
    this.status = status;
  }
}

function normalizePermissionAction(value) {
  const action = String(value || '').trim().toLowerCase();
  if (action === 'create' || action === 'createdraft') return 'create_draft';
  return action;
}

function permissionActionVariants(value) {
  const action = normalizePermissionAction(value);
  return action === 'create_draft' ? ['create_draft', 'create'] : [action];
}

function normalizeRoleId(value) {
  const roleId = String(value || '').trim().toLowerCase();
  if (roleId === 'hr_staff') return 'hr';
  if (roleId === 'dept_head') return 'supervisor';
  return roleId;
}

function validateUuid(value, label) {
  const normalized = String(value || '').trim();
  if (!UUID_RE.test(normalized)) {
    throw new PermissionAdminError(`${label} must be a valid UUID.`);
  }
  return normalized;
}

function validatePermissionAction(value) {
  const action = normalizePermissionAction(value);
  if (!SYSTEM_PERMISSION_ACTIONS.includes(action)) {
    throw new PermissionAdminError(
      `Invalid permission action. Allowed actions: ${SYSTEM_PERMISSION_ACTIONS.join(', ')}.`
    );
  }
  return action;
}

async function validateDocumentType(client, value) {
  const documentType = String(value || '').trim();
  if (!documentType) {
    throw new PermissionAdminError('Document type is required.');
  }
  if (documentType === '*' || BUILT_IN_DOCUMENT_TYPES.has(documentType)) {
    return documentType;
  }
  if (!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(documentType)) {
    throw new PermissionAdminError('Document type is invalid.');
  }

  const configured = await client.query(
    `SELECT EXISTS (
       SELECT 1 FROM docutracker_routing_configs WHERE document_type = $1
       UNION ALL
       SELECT 1 FROM docutracker_workflow_steps WHERE document_type = $1
     ) AS known`,
    [documentType]
  );
  if (configured.rows?.[0]?.known !== true) {
    throw new PermissionAdminError('Document type is not configured in DocuTracker.');
  }
  return documentType;
}

function validateRoleId(value) {
  const roleId = normalizeRoleId(value);
  if (!CANONICAL_ROLES.has(roleId)) {
    throw new PermissionAdminError('Role is not supported by DocuTracker.');
  }
  return roleId;
}

async function loadActiveUser(client, value) {
  const userId = validateUuid(value, 'User ID');
  const result = await client.query(
    `SELECT id::text AS id, full_name, role, is_active
     FROM users
     WHERE id = $1::uuid
     LIMIT 1`,
    [userId]
  );
  const user = result.rows?.[0];
  if (!user) throw new PermissionAdminError('Employee was not found.', 404);
  if (user.is_active === false) {
    throw new PermissionAdminError('Permissions cannot be assigned to an inactive employee.');
  }
  return {
    id: String(user.id),
    full_name: user.full_name || 'Unknown employee',
    role: normalizeRoleId(user.role || 'employee'),
    is_active: true,
  };
}

function validateScope({ userId, roleId }) {
  const hasUser = userId != null && String(userId).trim() !== '';
  const hasRole = roleId != null && String(roleId).trim() !== '';
  if (hasUser === hasRole) {
    throw new PermissionAdminError('Provide exactly one permission target: employee or role.');
  }
  return { hasUser, hasRole };
}

async function validateTarget(client, { userId, roleId }) {
  const scope = validateScope({ userId, roleId });
  if (scope.hasUser) {
    const user = await loadActiveUser(client, userId);
    return { userId: user.id, roleId: null, user };
  }
  return { userId: null, roleId: validateRoleId(roleId), user: null };
}

function rowSnapshot(row) {
  if (!row) return null;
  return {
    id: row.id,
    user_id: row.user_id,
    role_id: row.role_id,
    document_type: row.document_type,
    action: normalizePermissionAction(row.action),
    granted: row.granted === true,
    updated_at: row.updated_at,
  };
}

async function readMatchingRules(
  client,
  { userId, roleId, documentType, action = null, lock = false }
) {
  const params = [documentType];
  const where = ['document_type = $1'];
  let index = 2;
  if (userId) {
    where.push(`user_id = $${index++}::uuid`);
    params.push(userId);
  } else {
    where.push(`role_id = $${index++}`);
    params.push(roleId);
    where.push('user_id IS NULL');
  }
  if (action) {
    where.push(`action = ANY($${index++}::text[])`);
    params.push(permissionActionVariants(action));
  }
  const result = await client.query(
    `SELECT * FROM docutracker_permissions
     WHERE ${where.join(' AND ')}
     ORDER BY updated_at DESC NULLS LAST, created_at DESC, id DESC${lock ? ' FOR UPDATE' : ''}`,
    params
  );
  return result.rows || [];
}

async function upsertPermissionRule(
  client,
  { userId, roleId, documentType, action, granted }
) {
  const conflictTarget = userId
    ? '(user_id, document_type, action) WHERE user_id IS NOT NULL'
    : '(role_id, document_type, action) WHERE role_id IS NOT NULL';
  const result = await client.query(
    `INSERT INTO docutracker_permissions
       (user_id, role_id, document_type, action, granted)
     VALUES ($1::uuid, $2, $3, $4, $5)
     ON CONFLICT ${conflictTarget}
     DO UPDATE SET granted = EXCLUDED.granted, updated_at = now()
     RETURNING *`,
    [userId, roleId, documentType, action, granted]
  );
  const row = result.rows[0];

  if (action === 'create_draft') {
    await client.query(
      `DELETE FROM docutracker_permissions
       WHERE action = 'create'
         AND document_type = $1
         AND (($2::uuid IS NOT NULL AND user_id = $2::uuid)
           OR ($2::uuid IS NULL AND user_id IS NULL AND role_id = $3))`,
      [documentType, userId, roleId]
    );
  }
  return row;
}

/** Re-inserts the default role rows for a scope after a role reset. */
async function restoreRoleDefaults(client, { roleId, documentType, actions }) {
  const restored = [];
  for (const row of defaultRolePermissions(roleId, documentType, actions)) {
    const result = await client.query(
      `INSERT INTO docutracker_permissions
         (user_id, role_id, document_type, action, granted)
       VALUES (NULL, $1, $2, $3, $4)
       ON CONFLICT (role_id, document_type, action) WHERE role_id IS NOT NULL
       DO UPDATE SET granted = EXCLUDED.granted, updated_at = now()
       RETURNING *`,
      [roleId, documentType, row.action, row.granted]
    );
    if (result.rows?.[0]) restored.push(result.rows[0]);
  }
  return restored;
}

/**
 * Audits a reset: removed rows pair with the default restored for the same
 * action (or null when the reset leaves no rule), and defaults restored where
 * no rule existed are recorded too.
 */
async function auditReset(client, { actorId, documentType, target, removed, restored }) {
  const restoredByAction = new Map(
    restored.map((row) => [normalizePermissionAction(row.action), row])
  );
  const paired = new Set();
  for (const row of removed) {
    const action = normalizePermissionAction(row.action);
    const after = paired.has(action) ? null : restoredByAction.get(action) || null;
    if (after) paired.add(action);
    await writeGovernanceAudit(client, {
      actorId,
      eventType: 'permission_reset',
      entityType: 'permission',
      entityId: after?.id || row.id,
      documentType,
      targetUserId: target.userId,
      targetRoleId: target.roleId,
      beforeState: rowSnapshot(row),
      afterState: after ? rowSnapshot(after) : null,
    });
  }
  for (const row of restored) {
    if (paired.has(normalizePermissionAction(row.action))) continue;
    await writeGovernanceAudit(client, {
      actorId,
      eventType: 'permission_reset',
      entityType: 'permission',
      entityId: row.id,
      documentType,
      targetUserId: target.userId,
      targetRoleId: target.roleId,
      beforeState: null,
      afterState: rowSnapshot(row),
    });
  }
}

async function applyPermissionChange(client, actorId, change) {
  const documentType = await validateDocumentType(client, change.documentType);
  const action = validatePermissionAction(change.action);
  if (change.granted !== null && typeof change.granted !== 'boolean') {
    throw new PermissionAdminError('Permission value must be true, false, or inherit.');
  }
  const target = await validateTarget(client, {
    userId: change.userId ?? change.user_id,
    roleId: change.roleId ?? change.role_id,
  });

  const beforeRows = await readMatchingRules(client, {
    ...target,
    documentType,
    action,
    lock: true,
  });
  const beforeSnapshots = beforeRows.map(rowSnapshot);
  const beforeState = beforeSnapshots.length <= 1
    ? (beforeSnapshots[0] || null)
    : { rules: beforeSnapshots };

  if (change.granted === null) {
    const variants = permissionActionVariants(action);
    const removed = await client.query(
      `DELETE FROM docutracker_permissions
       WHERE document_type = $1
         AND action = ANY($2::text[])
         AND (($3::uuid IS NOT NULL AND user_id = $3::uuid)
           OR ($3::uuid IS NULL AND user_id IS NULL AND role_id = $4))
       RETURNING *`,
      [documentType, variants, target.userId, target.roleId]
    );
    const restored = target.roleId
      ? await restoreRoleDefaults(client, {
          roleId: target.roleId,
          documentType,
          actions: variants,
        })
      : [];
    await auditReset(client, {
      actorId,
      documentType,
      target,
      removed: removed.rows || [],
      restored,
    });
    const result = { action, granted: null, deleted: removed.rowCount || 0 };
    if (restored.length > 0) {
      result.restored_default = restored[0].granted === true;
    }
    return result;
  }

  const row = await upsertPermissionRule(client, {
    ...target,
    documentType,
    action,
    granted: change.granted,
  });
  await writeGovernanceAudit(client, {
    actorId,
    eventType: 'permission_saved',
    entityType: 'permission',
    entityId: row.id,
    documentType,
    targetUserId: target.userId,
    targetRoleId: target.roleId,
    beforeState,
    afterState: rowSnapshot(row),
  });
  return rowSnapshot(row);
}

async function withTransaction(pool, operation) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await operation(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function savePermissionChanges(pool, { actorId, documentType, changes }) {
  if (!Array.isArray(changes) || changes.length === 0) {
    throw new PermissionAdminError('At least one permission change is required.');
  }
  if (changes.length > 100) {
    throw new PermissionAdminError('A maximum of 100 permission changes can be saved at once.');
  }
  const actor = validateUuid(actorId, 'Administrator ID');
  for (const change of changes) {
    validatePermissionAction(change?.action);
    validateScope({
      userId: change?.userId ?? change?.user_id,
      roleId: change?.roleId ?? change?.role_id,
    });
    if (change?.granted !== null && typeof change?.granted !== 'boolean') {
      throw new PermissionAdminError(
        'Permission value must be true, false, or inherit.'
      );
    }
  }
  return withTransaction(pool, async (client) => {
    const normalizedDocumentType = await validateDocumentType(client, documentType);
    const results = [];
    for (const change of changes) {
      results.push(
        await applyPermissionChange(client, actor, {
          ...change,
          documentType: normalizedDocumentType,
        })
      );
    }
    const timestamp = await client.query('SELECT now() AS updated_at');
    return {
      document_type: normalizedDocumentType,
      updated: results.length,
      changes: results,
      updated_at:
        timestamp.rows?.[0]?.updated_at || new Date().toISOString(),
    };
  });
}

async function saveSinglePermission(pool, { actorId, body }) {
  if (typeof body?.granted !== 'boolean') {
    throw new PermissionAdminError('Permission value must be true or false.');
  }
  const saved = await savePermissionChanges(pool, {
    actorId,
    documentType: body.document_type,
    changes: [
      {
        userId: body.user_id,
        roleId: body.role_id,
        action: body.action,
        granted: body.granted,
      },
    ],
  });
  return saved.changes[0];
}

async function resetPermissionRules(pool, { actorId, body }) {
  const actor = validateUuid(actorId, 'Administrator ID');
  return withTransaction(pool, async (client) => {
    const documentType = await validateDocumentType(client, body?.document_type);
    const target = await validateTarget(client, {
      userId: body?.user_id,
      roleId: body?.role_id,
    });
    const action = body?.action == null ? null : validatePermissionAction(body.action);
    const beforeRows = await readMatchingRules(client, {
      ...target,
      documentType,
      action,
      lock: true,
    });
    const removed = beforeRows.length === 0
      ? { rows: [], rowCount: 0 }
      : await client.query(
          `DELETE FROM docutracker_permissions WHERE id = ANY($1::uuid[]) RETURNING *`,
          [beforeRows.map((row) => row.id)]
        );
    const restored = target.roleId
      ? await restoreRoleDefaults(client, {
          roleId: target.roleId,
          documentType,
          actions: action ? permissionActionVariants(action) : null,
        })
      : [];
    await auditReset(client, {
      actorId: actor,
      documentType,
      target,
      removed: removed.rows || [],
      restored,
    });
    return { deleted: removed.rowCount || 0, restored: restored.length };
  });
}

function permissionForScope(rows, { roleId = null, userId = null, documentType, action }) {
  const candidates = rows
    .filter((row) => normalizePermissionAction(row.action) === action)
    .filter((row) =>
      userId
        ? String(row.user_id || '') === String(userId)
        : normalizeRoleId(row.role_id) === roleId && row.user_id == null
    );
  const specific = candidates.find((row) => row.document_type === documentType);
  if (specific) return { granted: specific.granted === true, source: 'this_document_type' };
  const wildcard = candidates.find((row) => row.document_type === '*');
  if (wildcard) return { granted: wildcard.granted === true, source: 'all_document_types' };
  return { granted: false, source: 'not_configured' };
}

async function getPermissionPolicy(pool, { documentType, userId = null }) {
  const normalizedDocumentType = await validateDocumentType(pool, documentType);
  const selectedUser = userId ? await loadActiveUser(pool, userId) : null;
  const userClause = selectedUser ? 'OR user_id = $4::uuid' : '';
  const params = [
    [...SYSTEM_PERMISSION_ACTIONS, 'create'],
    normalizedDocumentType,
    [...CANONICAL_ROLES, 'hr_staff', 'dept_head'],
    ...(selectedUser ? [selectedUser.id] : []),
  ];
  const rowsResult = await pool.query(
    `SELECT * FROM docutracker_permissions
     WHERE action = ANY($1::text[])
       AND (document_type = $2 OR document_type = '*')
       AND (role_id = ANY($3::text[]) ${userClause})
     ORDER BY updated_at DESC NULLS LAST, created_at DESC, id DESC`,
    params
  );
  const rows = rowsResult.rows || [];
  const roleDefaults = [...CANONICAL_ROLES].map((roleId) => ({
    role_id: roleId,
    permissions: Object.fromEntries(
      SYSTEM_PERMISSION_ACTIONS.map((action) => {
        if (roleId === 'admin' && action !== RELEASE_ACTION) {
          return [action, { granted: true, source: 'administrator' }];
        }
        return [
          action,
          permissionForScope(rows, {
            roleId,
            documentType: normalizedDocumentType,
            action,
          }),
        ];
      })
    ),
  }));

  let userOverrides = null;
  let inheritedUserOverrides = null;
  let effective = null;
  if (selectedUser) {
    userOverrides = Object.fromEntries(
      SYSTEM_PERMISSION_ACTIONS.map((action) => {
        const row = rows.find(
          (item) =>
            String(item.user_id || '') === selectedUser.id &&
            item.document_type === normalizedDocumentType &&
            normalizePermissionAction(item.action) === action
        );
        return [action, row ? row.granted === true : null];
      })
    );
    inheritedUserOverrides = Object.fromEntries(
      SYSTEM_PERMISSION_ACTIONS.map((action) => {
        if (normalizedDocumentType === '*') return [action, null];
        const row = rows.find(
          (item) =>
            String(item.user_id || '') === selectedUser.id &&
            item.document_type === '*' &&
            normalizePermissionAction(item.action) === action
        );
        return [action, row ? row.granted === true : null];
      })
    );
    effective = {};
    for (const action of SYSTEM_PERMISSION_ACTIONS) {
      const explanation = await getEffectivePermissionExplanation(pool, {
        user: { id: selectedUser.id, role: selectedUser.role },
        action,
        documentType: normalizedDocumentType,
      });
      const winner = explanation.explicit_matches?.[0] || null;
      effective[action] = {
        granted: explanation.final_decision === true,
        source: explanation.reason || 'fallback_rule',
        matched_document_type: winner?.document_type || null,
        matched_scope: winner ? (winner.user_id ? 'user' : 'role') : null,
        matched_role_id: winner && !winner.user_id ? winner.role_id || null : null,
      };
    }
  }

  const updatedAt = rows.reduce((latest, row) => {
    const value = row.updated_at || row.created_at;
    if (!value) return latest;
    const timestamp = new Date(value).getTime();
    return Number.isFinite(timestamp) && timestamp > latest ? timestamp : latest;
  }, 0);

  return {
    document_type: normalizedDocumentType,
    actions: SYSTEM_PERMISSION_ACTIONS,
    role_defaults: roleDefaults,
    selected_user: selectedUser,
    user_overrides: userOverrides,
    inherited_user_overrides: inheritedUserOverrides,
    effective,
    updated_at: updatedAt > 0 ? new Date(updatedAt).toISOString() : null,
  };
}

async function listPermissionRecords(pool, filters = {}) {
  if (filters.roleId && filters.userId) {
    throw new PermissionAdminError(
      'Filter by either employee or role, not both.'
    );
  }
  const params = [];
  const where = [];
  let index = 1;
  if (filters.roleId) {
    where.push(`role_id = $${index++}`);
    params.push(validateRoleId(filters.roleId));
  }
  if (filters.userId) {
    const user = await loadActiveUser(pool, filters.userId);
    where.push(`user_id = $${index++}::uuid`);
    params.push(user.id);
  }
  if (filters.documentType != null && filters.documentType !== '') {
    const documentType = await validateDocumentType(pool, filters.documentType);
    where.push(`document_type = $${index++}`);
    params.push(documentType);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const result = await pool.query(
    `SELECT * FROM docutracker_permissions ${whereSql} ORDER BY document_type, action`,
    params
  );
  return result.rows || [];
}

const VIEW_RELATIONSHIPS = Object.freeze([
  'The person created the document.',
  'The person holds the document or is assigned to its current step.',
  'The person was assigned to a step the document has already reached, or has already acted on it.',
  'The person is an assigned signer.',
  'The person is an eligible reviewer of the originating department.',
  'The person may release this type while the document is in the release stage.',
  'The person belongs to the department that received a released copy.',
]);

function rankAccessRows(rows, { userId, role, documentType, action }) {
  const wanted = normalizePermissionAction(action);
  const roleIds = getRoleVariants(role);
  return rows
    .filter((row) => normalizePermissionAction(row.action) === wanted)
    .map((row) => ({
      row,
      score: permissionPriority(row, { userId, roleIds, documentType }),
    }))
    .filter((entry) => entry.score >= 0)
    .sort((a, b) => b.score - a.score);
}

function describeWinner(entry) {
  if (!entry) {
    return {
      source_kind: 'none',
      matched_document_type: null,
      matched_role_id: null,
      precedence_score: null,
      type_rule: 'none',
      precedence:
        'No employee exception or role rule matches. A general action is denied unless a document relationship still applies.',
      stored_rule_applied: false,
    };
  }
  const row = entry.row;
  const employee = Boolean(row.user_id);
  const specific = row.document_type !== '*';
  let precedence;
  if (employee && specific) {
    precedence =
      'This employee exception for this document type outranks an all-types exception and every role rule.';
  } else if (employee) {
    precedence =
      'This employee exception for all document types applies because this type has no employee exception.';
  } else if (specific) {
    precedence =
      'This role rule for this document type applies because this employee has no exception.';
  } else {
    precedence =
      'This role rule for all document types applies because nothing more specific matches.';
  }
  return {
    source_kind: employee ? 'employee' : 'role',
    matched_document_type: row.document_type,
    matched_role_id: employee ? null : row.role_id || null,
    precedence_score: entry.score,
    type_rule: row.granted === true ? 'granted' : 'denied',
    precedence,
    stored_rule_applied: true,
  };
}

function actionPreview(action, fields) {
  return { action, ...fields };
}

function previewOneAction({ action, user, documentType, rows }) {
  const ranked = rankAccessRows(rows, {
    userId: user.id,
    role: user.role,
    documentType,
    action,
  });
  const winner = describeWinner(ranked[0]);
  const isAdmin = user.role === 'admin';
  const granted = ranked[0] ? ranked[0].row.granted === true : false;

  if (action === 'view') {
    const userSpecific = resolveUserSpecificPermissionFromRows(rows, {
      userId: user.id,
      documentType,
    });
    if (isAdmin) {
      return actionPreview(action, {
        outcome: 'allowed',
        type_rule: 'administrator',
        source_kind: 'administrator',
        matched_document_type: null,
        matched_role_id: 'admin',
        precedence_score: null,
        precedence:
          'Administrator status allows opening documents of this type. A stored view row is not applied to that check.',
        summary:
          'This administrator can open documents of this type without a personal relationship to each document. That does not grant Approve, Forward, Return, or Reject.',
        conditions: [],
        stored_rule_applied: false,
        ignored_rule: ranked[0]
          ? {
              source_kind: winner.source_kind,
              matched_document_type: winner.matched_document_type,
              type_rule: winner.type_rule,
            }
          : null,
      });
    }
    if (userSpecific === false) {
      return actionPreview(action, {
        ...winner,
        outcome: 'blocked',
        summary:
          'This employee is denied view. That denial blocks a document of this type even when they created it, hold it, or were assigned to it.',
        conditions: [],
      });
    }
    return actionPreview(action, {
      ...winner,
      outcome: 'conditional',
      summary:
        'View is not a decision for every document. A grant does not open documents this person is not connected to. A role-level denial does not remove a relationship that already allows opening.',
      conditions: VIEW_RELATIONSHIPS,
    });
  }

  if (action === 'release') {
    const userView = resolveUserSpecificPermissionFromRows(rows, {
      userId: user.id,
      documentType,
    });
    if (userView === false) {
      const viewWinner = describeWinner(
        rankAccessRows(rows, {
          userId: user.id,
          role: user.role,
          documentType,
          action: 'view',
        })[0]
      );
      return actionPreview(action, {
        ...viewWinner,
        outcome: 'blocked',
        summary:
          'An employee view denial blocks release, including for an administrator. Release is not approval, and a release grant does not overcome this denial.',
        conditions: [],
      });
    }
    if (!granted) {
      return actionPreview(action, {
        ...winner,
        outcome: 'blocked',
        summary: isAdmin
          ? 'Release is not granted. Administrator status does not add it.'
          : 'Release is not granted for this type.',
        conditions: [],
      });
    }
    return actionPreview(action, {
      ...winner,
      outcome: 'conditional',
      summary:
        'Release is granted for this type, but only for a particular document that meets every condition below. Release distributes an approved document. It does not approve it.',
      conditions: [
        'The document is a native DocuTracker document and its type requires release.',
        'The document status is approved and it has not been released yet.',
        'This person is not blocked by an employee view denial.',
      ],
    });
  }

  if (action === 'download') {
    if (isAdmin) {
      return actionPreview(action, {
        outcome: 'allowed',
        type_rule: 'administrator',
        source_kind: 'administrator',
        matched_document_type: null,
        matched_role_id: 'admin',
        precedence_score: null,
        precedence:
          'Administrator status allows attachment download. A stored download row is not required.',
        summary:
          'This administrator can download attachments. That does not grant workflow approval.',
        conditions: [],
        stored_rule_applied: false,
      });
    }
    if (granted) {
      return actionPreview(action, {
        ...winner,
        outcome: 'allowed',
        summary:
          'This grant allows downloading attachments from submitted documents of this type, including documents that were not routed to this person. That is broader than view.',
        conditions: [
          'Attachments on a document this person can already open stay downloadable even without this grant.',
        ],
      });
    }
    return actionPreview(action, {
      ...winner,
      outcome: 'conditional',
      summary:
        'There is no broad download grant, so this person cannot download attachments from documents of this type that they cannot open.',
      conditions: [
        'Attachments on a document this person can open are still downloadable.',
      ],
    });
  }

  if (action === 'submit') {
    if (isAdmin) {
      return actionPreview(action, {
        outcome: 'allowed',
        type_rule: 'administrator',
        source_kind: 'administrator',
        matched_document_type: null,
        matched_role_id: 'admin',
        precedence_score: null,
        precedence:
          'Administrator status allows submit. The creator and draft limits applied to other people are not applied.',
        summary:
          'This administrator can submit. Submit still only sends a document into the workflow. It is not approval.',
        conditions: [],
        stored_rule_applied: false,
      });
    }
    if (!granted) {
      return actionPreview(action, {
        ...winner,
        outcome: 'blocked',
        summary:
          'Submit is blocked for this type. Create, when it is allowed, only starts a draft.',
        conditions: [],
      });
    }
    return actionPreview(action, {
      ...winner,
      outcome: 'conditional',
      summary:
        'Submit is granted for this type, but only for an unassigned draft this person created. It does not submit someone else\'s document and it does not approve.',
      conditions: [
        'The person must be the document creator.',
        'The document must still be an unassigned draft.',
      ],
    });
  }

  if (isAdmin) {
    return actionPreview(action, {
      outcome: 'allowed',
      type_rule: 'administrator',
      source_kind: 'administrator',
      matched_document_type: null,
      matched_role_id: 'admin',
      precedence_score: null,
      precedence:
        'Administrator status allows creating a draft. A stored create row is not required.',
      summary:
        'This administrator can start a draft of this type. Create does not submit it and does not approve it.',
      conditions: [],
      stored_rule_applied: false,
    });
  }
  return actionPreview(action, {
    ...winner,
    outcome: granted ? 'allowed' : 'blocked',
    summary: granted
      ? 'This person can start a draft of this type. Create does not submit the draft.'
      : 'This person cannot start a draft of this type.',
    conditions: [],
  });
}

/**
 * Read-only effective access for one employee and document type.
 * Uses the same precedence and special cases as enforcement. It does not
 * decide access to one document, and it does not write.
 */
async function previewEffectiveAccess(pool, { userId, documentType }) {
  const normalizedDocumentType = await validateDocumentType(pool, documentType);
  const selectedUser = await loadActiveUser(pool, userId);
  const roleIds = getRoleVariants(selectedUser.role);
  const rowsResult = await pool.query(
    `SELECT user_id::text AS user_id, role_id, document_type, action, granted
     FROM docutracker_permissions
     WHERE action = ANY($1::text[])
       AND (document_type = $2 OR document_type = '*')
       AND (
         user_id = $3::uuid
         OR (user_id IS NULL AND role_id = ANY($4::text[]))
       )`,
    [
      [...SYSTEM_PERMISSION_ACTIONS, 'create'],
      normalizedDocumentType,
      selectedUser.id,
      roleIds,
    ]
  );
  return {
    basis: 'saved_policy',
    read_only: true,
    document_type: normalizedDocumentType,
    user: {
      id: selectedUser.id,
      full_name: selectedUser.full_name,
      role: selectedUser.role,
    },
    actions: SYSTEM_PERMISSION_ACTIONS.map((action) =>
      previewOneAction({
        action,
        user: selectedUser,
        documentType: normalizedDocumentType,
        rows: rowsResult.rows || [],
      })
    ),
  };
}

module.exports = {
  PermissionAdminError,
  SYSTEM_PERMISSION_ACTIONS,
  getPermissionPolicy,
  previewEffectiveAccess,
  listPermissionRecords,
  normalizePermissionAction,
  resetPermissionRules,
  savePermissionChanges,
  saveSinglePermission,
  validateDocumentType,
  validatePermissionAction,
};
