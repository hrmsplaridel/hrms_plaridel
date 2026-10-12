const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  DEFAULT_ROLE_PERMISSIONS,
  defaultRolePermissions,
} = require('../src/services/docutrackerPermissionDefaults');
const {
  resetPermissionRules,
  savePermissionChanges,
} = require('../src/services/docutrackerPermissionAdminService');
const { hasReleasePermission } = require('../src/services/docutrackerWorkflowService');

const ADMIN_ID = '00000000-0000-4000-8000-000000000001';
const HR_USER = { id: '00000000-0000-4000-8000-0000000000a1', role: 'hr' };
const EMPLOYEE_USER = { id: '00000000-0000-4000-8000-0000000000a2', role: 'employee' };
const SCRIPTS = path.join(__dirname, '..', 'scripts');

function key(row) {
  return `${row.role_id}|${row.document_type}|${row.action}|${row.granted}`;
}

/**
 * Role rows seeded by a fresh install: the baseline block plus the release
 * default inserted after the DocuTracker rollup.
 */
function initSchemaBaseline() {
  const sql = fs.readFileSync(path.join(SCRIPTS, 'init-schema.sql'), 'utf8');
  const block = sql.match(
    /WITH baseline\(role_id, document_type, action, granted\) AS \(\s*VALUES([\s\S]*?)\)\s*INSERT INTO docutracker_permissions/
  );
  assert.ok(block, 'init-schema baseline seed block not found');
  const rollupAt = sql.indexOf('\\ir migrations/docutracker/docutracker-install-all-in-order.sql');
  assert.ok(rollupAt > 0, 'DocuTracker rollup include not found');
  const releaseSeeds = [
    ...sql.slice(rollupAt).matchAll(
      /INSERT INTO docutracker_permissions \(role_id, user_id, document_type, action, granted\)\s*VALUES ([^;]*?)\s*ON CONFLICT/g
    ),
  ].map((match) => match[1]);
  assert.equal(releaseSeeds.length, 1, 'expected one post-rollup permission seed');
  const tuple = /\('(\w+)',\s*(?:NULL::uuid,\s*)?'([\w*]+)',\s*'(\w+)',\s*(true|false)\)/g;
  return [block[1], ...releaseSeeds].flatMap((values) =>
    [...values.matchAll(tuple)].map(([, role_id, document_type, action, granted]) => ({
      role_id,
      document_type,
      action,
      granted: granted === 'true',
    }))
  );
}

test('fresh install seeds release only after the rollup widens the action check', () => {
  const sql = fs.readFileSync(path.join(SCRIPTS, 'init-schema.sql'), 'utf8');
  const rollupAt = sql.indexOf('\\ir migrations/docutracker/docutracker-install-all-in-order.sql');
  const beforeRollup = sql.slice(0, rollupAt);
  assert.doesNotMatch(beforeRollup, /'release',\s*true\)/);
});

/** In-memory docutracker_permissions table behind the admin service SQL. */
function createPermissionStore(seedRows) {
  let nextId = 1;
  const rows = seedRows.map((row) => ({
    id: `perm-${nextId++}`,
    user_id: null,
    ...row,
  }));
  const audits = [];

  const sameTarget = (row, userId, roleId) =>
    userId ? row.user_id === userId : row.user_id == null && row.role_id === roleId;

  function remove(predicate) {
    const removed = rows.filter(predicate);
    for (const row of removed) rows.splice(rows.indexOf(row), 1);
    return { rows: removed, rowCount: removed.length };
  }

  function upsert({ userId, roleId, documentType, action, granted }) {
    const existing = rows.find(
      (row) =>
        sameTarget(row, userId, roleId) &&
        row.document_type === documentType &&
        row.action === action
    );
    if (existing) {
      existing.granted = granted;
      return { rows: [existing], rowCount: 1 };
    }
    const row = {
      id: `perm-${nextId++}`,
      user_id: userId,
      role_id: roleId,
      document_type: documentType,
      action,
      granted,
    };
    rows.push(row);
    return { rows: [row], rowCount: 1 };
  }

  async function query(sql, params = []) {
    if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)) return { rows: [] };
    if (sql.includes('SELECT now()')) return { rows: [{ updated_at: 'now' }] };
    if (sql.includes('INSERT INTO docutracker_governance_audit')) {
      audits.push(params);
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('SELECT * FROM docutracker_permissions')) {
      const [documentType, target, actions] = params;
      const byUser = sql.includes('user_id = $2::uuid');
      return {
        rows: rows.filter(
          (row) =>
            row.document_type === documentType &&
            sameTarget(row, byUser ? target : null, byUser ? null : target) &&
            (actions == null || actions.includes(row.action))
        ),
      };
    }
    if (sql.includes('SELECT user_id::text AS user_id')) {
      const [actions, documentType, userId, roleIds] = params;
      return {
        rows: rows.filter(
          (row) =>
            actions.includes(row.action) &&
            (row.document_type === documentType || row.document_type === '*') &&
            (row.user_id === userId || (row.user_id == null && roleIds.includes(row.role_id)))
        ),
      };
    }
    if (sql.includes('DELETE FROM docutracker_permissions WHERE id = ANY')) {
      return remove((row) => params[0].includes(row.id));
    }
    if (sql.includes('DELETE FROM docutracker_permissions')) {
      if (sql.includes("action = 'create'")) {
        const [documentType, userId, roleId] = params;
        return remove(
          (row) =>
            row.action === 'create' &&
            row.document_type === documentType &&
            sameTarget(row, userId, roleId)
        );
      }
      const [documentType, actions, userId, roleId] = params;
      return remove(
        (row) =>
          row.document_type === documentType &&
          actions.includes(row.action) &&
          sameTarget(row, userId, roleId)
      );
    }
    if (sql.includes('VALUES (NULL, $1, $2, $3, $4)')) {
      const [roleId, documentType, action, granted] = params;
      return upsert({ userId: null, roleId, documentType, action, granted });
    }
    if (sql.includes('INSERT INTO docutracker_permissions')) {
      const [userId, roleId, documentType, action, granted] = params;
      return upsert({ userId, roleId, documentType, action, granted });
    }
    throw new Error(`Unexpected SQL in permission store: ${sql.slice(0, 80)}`);
  }

  const client = { query, release() {} };
  return {
    rows,
    audits,
    pool: { query, connect: async () => client },
    find: (roleId, documentType, action) =>
      rows.find(
        (row) =>
          row.user_id == null &&
          row.role_id === roleId &&
          row.document_type === documentType &&
          row.action === action
      ),
  };
}

function snapshot(rows) {
  return rows.map(key).sort();
}

test('backend default policy matches the fresh-install seed exactly', () => {
  assert.deepEqual(snapshot(DEFAULT_ROLE_PERMISSIONS), snapshot(initSchemaBaseline()));
});

test('fresh defaults grant HR memo release and no other release', async () => {
  const releaseDefaults = DEFAULT_ROLE_PERMISSIONS.filter((row) => row.action === 'release');
  assert.deepEqual(releaseDefaults.map(key), ['hr|memo|release|true']);

  const migration = fs.readFileSync(
    path.join(SCRIPTS, 'migrations', 'docutracker', 'migrate-docutracker-document-release-v1.sql'),
    'utf8'
  );
  assert.match(migration, /VALUES \('hr', NULL::uuid, 'memo', 'release', true\)/);

  const store = createPermissionStore(DEFAULT_ROLE_PERMISSIONS);
  assert.equal(await hasReleasePermission(store.pool, { user: HR_USER, documentType: 'memo' }), true);
  assert.equal(
    await hasReleasePermission(store.pool, { user: HR_USER, documentType: 'purchaseRequest' }),
    false
  );
  assert.equal(
    await hasReleasePermission(store.pool, { user: EMPLOYEE_USER, documentType: 'memo' }),
    false
  );
});

test('removing custom role settings for memo restores the complete memo defaults', async () => {
  const store = createPermissionStore(DEFAULT_ROLE_PERMISSIONS);
  // Customize HR memo: revoke release, allow drafting, add a memo view rule.
  await savePermissionChanges(store.pool, {
    actorId: ADMIN_ID,
    documentType: 'memo',
    changes: [
      { roleId: 'hr', action: 'release', granted: false },
      { roleId: 'hr', action: 'create_draft', granted: true },
      { roleId: 'hr', action: 'view', granted: false },
    ],
  });
  assert.equal(store.find('hr', 'memo', 'release').granted, false);

  const wildcardBefore = snapshot(store.rows.filter((row) => row.document_type === '*'));
  const result = await savePermissionChanges(store.pool, {
    actorId: ADMIN_ID,
    documentType: 'memo',
    changes: ['hr', 'supervisor', 'employee'].flatMap((roleId) =>
      ['view', 'create_draft', 'download', 'submit', 'release'].map((action) => ({
        roleId,
        action,
        granted: null,
      }))
    ),
  });
  assert.equal(result.updated, 15);

  const memoRows = store.rows.filter((row) => row.document_type === 'memo');
  assert.deepEqual(
    snapshot(memoRows),
    snapshot(DEFAULT_ROLE_PERMISSIONS.filter((row) => row.document_type === 'memo'))
  );
  assert.equal(store.find('hr', 'memo', 'view'), undefined);
  assert.equal(await hasReleasePermission(store.pool, { user: HR_USER, documentType: 'memo' }), true);
  assert.deepEqual(snapshot(store.rows.filter((row) => row.document_type === '*')), wildcardBefore);

  const releaseAudit = store.audits.find(
    (params) =>
      params[1] === 'permission_reset' &&
      String(params[8]).includes('"action":"release"')
  );
  assert.ok(releaseAudit, 'reset of the revoked release rule is audited');
  assert.match(String(releaseAudit[9]), /"granted":true/);
});

test('DELETE reset of HR memo restores release and keeps other defaults unchanged', async () => {
  const store = createPermissionStore(
    DEFAULT_ROLE_PERMISSIONS.filter((row) => !(row.role_id === 'hr' && row.action === 'release'))
  );
  await savePermissionChanges(store.pool, {
    actorId: ADMIN_ID,
    documentType: 'memo',
    changes: [{ roleId: 'hr', action: 'submit', granted: true }],
  });

  const result = await resetPermissionRules(store.pool, {
    actorId: ADMIN_ID,
    body: { role_id: 'hr', document_type: 'memo' },
  });
  assert.equal(result.deleted, 2);
  assert.equal(result.restored, 3);
  assert.deepEqual(
    snapshot(store.rows.filter((row) => row.role_id === 'hr' && row.document_type === 'memo')),
    ['hr|memo|create_draft|false', 'hr|memo|release|true', 'hr|memo|submit|false']
  );
  assert.deepEqual(
    snapshot(store.rows.filter((row) => !(row.role_id === 'hr' && row.document_type === 'memo'))),
    snapshot(
      DEFAULT_ROLE_PERMISSIONS.filter(
        (row) => !(row.role_id === 'hr' && row.document_type === 'memo')
      )
    )
  );

  const single = await resetPermissionRules(store.pool, {
    actorId: ADMIN_ID,
    body: { role_id: 'hr', document_type: 'memo', action: 'release' },
  });
  assert.equal(single.restored, 1);
  assert.equal(store.find('hr', 'memo', 'release').granted, true);
});

test('reset of the all-types scope restores wildcard defaults only', async () => {
  const store = createPermissionStore(DEFAULT_ROLE_PERMISSIONS);
  await savePermissionChanges(store.pool, {
    actorId: ADMIN_ID,
    documentType: '*',
    changes: [
      { roleId: 'employee', action: 'download', granted: false },
      { roleId: 'employee', action: 'release', granted: true },
    ],
  });
  await savePermissionChanges(store.pool, {
    actorId: ADMIN_ID,
    documentType: '*',
    changes: ['view', 'create_draft', 'download', 'submit', 'release'].map((action) => ({
      roleId: 'employee',
      action,
      granted: null,
    })),
  });

  assert.deepEqual(snapshot(store.rows), snapshot(DEFAULT_ROLE_PERMISSIONS));
  assert.equal(
    await hasReleasePermission(store.pool, { user: EMPLOYEE_USER, documentType: 'memo' }),
    false
  );
});

test('types without a default release permission do not gain one on reset', async () => {
  const store = createPermissionStore(DEFAULT_ROLE_PERMISSIONS);
  await savePermissionChanges(store.pool, {
    actorId: ADMIN_ID,
    documentType: 'purchaseRequest',
    changes: [{ roleId: 'hr', action: 'release', granted: true }],
  });
  assert.equal(
    await hasReleasePermission(store.pool, { user: HR_USER, documentType: 'purchaseRequest' }),
    true
  );

  const result = await resetPermissionRules(store.pool, {
    actorId: ADMIN_ID,
    body: { role_id: 'hr', document_type: 'purchaseRequest' },
  });
  assert.equal(store.find('hr', 'purchaseRequest', 'release'), undefined);
  assert.equal(
    await hasReleasePermission(store.pool, { user: HR_USER, documentType: 'purchaseRequest' }),
    false
  );
  assert.deepEqual(
    snapshot(store.rows.filter((row) => row.document_type === 'purchaseRequest')),
    snapshot(DEFAULT_ROLE_PERMISSIONS.filter((row) => row.document_type === 'purchaseRequest'))
  );
  assert.equal(result.restored, 2);
  assert.deepEqual(defaultRolePermissions('hr', 'purchaseRequest', ['release']), []);
});

test('employee exception reset removes the exception without inventing defaults', async () => {
  const store = createPermissionStore(DEFAULT_ROLE_PERMISSIONS);
  store.rows.push({
    id: 'perm-user',
    user_id: HR_USER.id,
    role_id: null,
    document_type: 'memo',
    action: 'release',
    granted: false,
  });
  const before = store.rows.length;
  // Employee resets look up the employee first.
  const originalQuery = store.pool.query;
  const userAware = async (sql, params) =>
    sql.includes('FROM users')
      ? { rows: [{ id: HR_USER.id, full_name: 'HR User', role: 'hr', is_active: true }] }
      : originalQuery(sql, params);
  const pool = { query: userAware, connect: async () => ({ query: userAware, release() {} }) };

  const result = await resetPermissionRules(pool, {
    actorId: ADMIN_ID,
    body: { user_id: HR_USER.id, document_type: 'memo' },
  });
  assert.equal(result.deleted, 1);
  assert.equal(result.restored, 0);
  assert.equal(store.rows.length, before - 1);
  assert.equal(await hasReleasePermission(store.pool, { user: HR_USER, documentType: 'memo' }), true);
});
