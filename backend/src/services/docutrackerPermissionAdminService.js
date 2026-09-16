const { writeGovernanceAudit } = require('./docutrackerGovernanceAudit');
const {
  getEffectivePermissionExplanation,
} = require('./docutrackerWorkflowService');

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const BUILT_IN_DOCUMENT_TYPES = new Set(['memo', 'purchaseRequest']);
const CANONICAL_ROLES = new Set(['admin', 'hr', 'supervisor', 'employee']);
const SYSTEM_PERMISSION_ACTIONS = Object.freeze([
  'view',
  'create_draft',
  'download',
  'submit',
]);

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
    for (const row of removed.rows || []) {
      await writeGovernanceAudit(client, {
        actorId,
        eventType: 'permission_reset',
        entityType: 'permission',
        entityId: row.id,
        documentType,
        targetUserId: target.userId,
        targetRoleId: target.roleId,
        beforeState: rowSnapshot(row),
        afterState: null,
      });
    }
    return { action, granted: null, deleted: removed.rowCount || 0 };
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
    if (beforeRows.length === 0) return { deleted: 0 };

    const ids = beforeRows.map((row) => row.id);
    const removed = await client.query(
      `DELETE FROM docutracker_permissions WHERE id = ANY($1::uuid[]) RETURNING *`,
      [ids]
    );
    for (const row of removed.rows || []) {
      await writeGovernanceAudit(client, {
        actorId: actor,
        eventType: 'permission_reset',
        entityType: 'permission',
        entityId: row.id,
        documentType,
        targetUserId: target.userId,
        targetRoleId: target.roleId,
        beforeState: rowSnapshot(row),
        afterState: null,
      });
    }
    return { deleted: removed.rowCount || 0 };
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
        if (roleId === 'admin') {
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
      effective[action] = {
        granted: explanation.final_decision === true,
        source: explanation.reason || 'fallback_rule',
        matched_document_type: explanation.explicit_matches?.[0]?.document_type || null,
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

module.exports = {
  PermissionAdminError,
  SYSTEM_PERMISSION_ACTIONS,
  getPermissionPolicy,
  listPermissionRecords,
  normalizePermissionAction,
  resetPermissionRules,
  savePermissionChanges,
  saveSinglePermission,
  validateDocumentType,
  validatePermissionAction,
};
