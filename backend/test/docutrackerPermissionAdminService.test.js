const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getPermissionPolicy,
  PermissionAdminError,
  resetPermissionRules,
  savePermissionChanges,
  saveSinglePermission,
} = require('../src/services/docutrackerPermissionAdminService');

const ADMIN_ID = '00000000-0000-4000-8000-000000000001';
const USER_ID = '00000000-0000-4000-8000-000000000002';
const PERMISSION_ID = '00000000-0000-4000-8000-000000000003';

function activeUser() {
  return {
    id: USER_ID,
    full_name: 'Sample Employee',
    role: 'employee',
    is_active: true,
  };
}

function createPool(handler) {
  const queries = [];
  const client = {
    async query(sql, params = []) {
      queries.push({ sql, params });
      return handler(sql, params, queries);
    },
    release() {
      queries.push({ sql: 'RELEASE', params: [] });
    },
  };
  return {
    queries,
    pool: {
      async connect() {
        return client;
      },
    },
  };
}

test('single permission rejects ambiguous employee and role scope', async () => {
  await assert.rejects(
    saveSinglePermission(
      { connect: async () => assert.fail('must not start a transaction') },
      {
        actorId: ADMIN_ID,
        body: {
          user_id: USER_ID,
          role_id: 'employee',
          document_type: 'memo',
          action: 'view',
          granted: true,
        },
      }
    ),
    (error) =>
      error instanceof PermissionAdminError &&
      error.message.includes('exactly one permission target')
  );
});

test('single permission requires a real boolean value', async () => {
  await assert.rejects(
    saveSinglePermission(
      { connect: async () => assert.fail('must not start a transaction') },
      {
        actorId: ADMIN_ID,
        body: {
          user_id: USER_ID,
          document_type: 'memo',
          action: 'view',
          granted: 'false',
        },
      }
    ),
    (error) =>
      error instanceof PermissionAdminError &&
      error.message === 'Permission value must be true or false.'
  );
});

test('bulk save rolls back every permission when audit insertion fails', async () => {
  const { pool, queries } = createPool(async (sql) => {
    if (sql === 'BEGIN' || sql === 'ROLLBACK') return { rows: [], rowCount: 0 };
    if (sql.includes('FROM users')) return { rows: [activeUser()], rowCount: 1 };
    if (sql.includes('SELECT * FROM docutracker_permissions')) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('INSERT INTO docutracker_permissions')) {
      return {
        rows: [
          {
            id: PERMISSION_ID,
            user_id: USER_ID,
            role_id: null,
            document_type: 'memo',
            action: 'view',
            granted: true,
            updated_at: new Date().toISOString(),
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('DELETE FROM docutracker_permissions')) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('INSERT INTO docutracker_governance_audit')) {
      throw new Error('audit unavailable');
    }
    return { rows: [], rowCount: 0 };
  });

  await assert.rejects(
    savePermissionChanges(pool, {
      actorId: ADMIN_ID,
      documentType: 'memo',
      changes: [
        { userId: USER_ID, action: 'view', granted: true },
      ],
    }),
    /audit unavailable/
  );

  assert.equal(queries.some((query) => query.sql === 'ROLLBACK'), true);
  assert.equal(queries.some((query) => query.sql === 'COMMIT'), false);
});

test('bulk save normalizes create and commits permission plus audit', async () => {
  let auditParams = null;
  const { pool, queries } = createPool(async (sql, params) => {
    if (['BEGIN', 'COMMIT'].includes(sql)) return { rows: [], rowCount: 0 };
    if (sql.includes('FROM users')) return { rows: [activeUser()], rowCount: 1 };
    if (sql.includes('SELECT * FROM docutracker_permissions')) {
      return {
        rows: [
          {
            id: PERMISSION_ID,
            user_id: USER_ID,
            role_id: null,
            document_type: 'memo',
            action: 'create',
            granted: false,
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('INSERT INTO docutracker_permissions')) {
      return {
        rows: [
          {
            id: PERMISSION_ID,
            user_id: USER_ID,
            role_id: null,
            document_type: 'memo',
            action: 'create_draft',
            granted: true,
            updated_at: '2026-09-14T13:00:00.000Z',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('DELETE FROM docutracker_permissions')) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('INSERT INTO docutracker_governance_audit')) {
      auditParams = params;
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const result = await savePermissionChanges(pool, {
    actorId: ADMIN_ID,
    documentType: 'memo',
    changes: [{ userId: USER_ID, action: 'create', granted: true }],
  });

  assert.equal(result.updated, 1);
  assert.equal(result.changes[0].action, 'create_draft');
  assert.equal(queries.some((query) => query.sql === 'COMMIT'), true);
  assert.ok(auditParams);
  assert.match(auditParams[8], /"granted":false/);
  assert.match(auditParams[9], /"granted":true/);
});

test('reset deletes rules and records their previous values in the audit', async () => {
  let audited = false;
  const row = {
    id: PERMISSION_ID,
    user_id: USER_ID,
    role_id: null,
    document_type: 'memo',
    action: 'download',
    granted: false,
  };
  const { pool, queries } = createPool(async (sql, params) => {
    if (['BEGIN', 'COMMIT'].includes(sql)) return { rows: [], rowCount: 0 };
    if (sql.includes('FROM users')) return { rows: [activeUser()], rowCount: 1 };
    if (sql.includes('SELECT * FROM docutracker_permissions')) {
      return { rows: [row], rowCount: 1 };
    }
    if (sql.includes('DELETE FROM docutracker_permissions')) {
      return { rows: [row], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO docutracker_governance_audit')) {
      audited = true;
      assert.equal(params[1], 'permission_reset');
      assert.match(params[8], /"action":"download"/);
      assert.equal(params[9], null);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const result = await resetPermissionRules(pool, {
    actorId: ADMIN_ID,
    body: {
      user_id: USER_ID,
      document_type: 'memo',
      action: 'download',
    },
  });

  assert.equal(result.deleted, 1);
  assert.equal(audited, true);
  assert.equal(queries.some((query) => query.sql === 'COMMIT'), true);
});

test('inactive employees cannot receive permission exceptions', async () => {
  const { pool, queries } = createPool(async (sql) => {
    if (sql === 'BEGIN' || sql === 'ROLLBACK') return { rows: [], rowCount: 0 };
    if (sql.includes('FROM users')) {
      return {
        rows: [{ ...activeUser(), is_active: false }],
        rowCount: 1,
      };
    }
    return { rows: [], rowCount: 0 };
  });

  await assert.rejects(
    savePermissionChanges(pool, {
      actorId: ADMIN_ID,
      documentType: 'memo',
      changes: [{ userId: USER_ID, action: 'view', granted: true }],
    }),
    /inactive employee/
  );
  assert.equal(queries.some((query) => query.sql === 'ROLLBACK'), true);
});

test('policy returns role defaults, employee exceptions, and effective access together', async () => {
  const rows = [
    {
      id: PERMISSION_ID,
      user_id: null,
      role_id: 'hr',
      document_type: '*',
      action: 'view',
      granted: true,
      updated_at: '2026-09-14T13:00:00.000Z',
    },
    {
      id: '00000000-0000-4000-8000-000000000004',
      user_id: USER_ID,
      role_id: null,
      document_type: 'memo',
      action: 'view',
      granted: false,
      updated_at: '2026-09-14T13:05:00.000Z',
    },
  ];
  const queries = [];
  const pool = {
    async query(sql, params = []) {
      queries.push({ sql, params });
      if (sql.includes('FROM users')) {
        return {
          rows: [{ ...activeUser(), role: 'hr' }],
          rowCount: 1,
        };
      }
      if (sql.includes('SELECT * FROM docutracker_permissions')) {
        return { rows, rowCount: rows.length };
      }
      if (sql.includes('SELECT user_id::text AS user_id')) {
        const action = params[0];
        return action.includes('view')
          ? { rows, rowCount: rows.length }
          : { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    },
  };

  const policy = await getPermissionPolicy(pool, {
    documentType: 'memo',
    userId: USER_ID,
  });

  const hr = policy.role_defaults.find((role) => role.role_id === 'hr');
  assert.equal(hr.permissions.view.granted, true);
  assert.equal(hr.permissions.view.source, 'all_document_types');
  assert.equal(policy.user_overrides.view, false);
  assert.equal(policy.effective.view.granted, false);
  const policyQuery = queries.find((query) =>
    query.sql.includes('SELECT * FROM docutracker_permissions')
  );
  assert.equal(policyQuery.params[1], 'memo');
  assert.equal(policyQuery.params[3], USER_ID);
});

test('an invalid batch is rejected before its transaction begins', async () => {
  const { pool, queries } = createPool(async (sql) => {
    if (['BEGIN', 'ROLLBACK'].includes(sql)) return { rows: [], rowCount: 0 };
    if (sql.includes('FROM users')) return { rows: [activeUser()], rowCount: 1 };
    if (sql.includes('SELECT * FROM docutracker_permissions')) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('INSERT INTO docutracker_permissions')) {
      return {
        rows: [
          {
            id: PERMISSION_ID,
            user_id: USER_ID,
            role_id: null,
            document_type: 'memo',
            action: 'view',
            granted: true,
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('INSERT INTO docutracker_governance_audit')) {
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  await assert.rejects(
    savePermissionChanges(pool, {
      actorId: ADMIN_ID,
      documentType: 'memo',
      changes: [
        { userId: USER_ID, action: 'view', granted: true },
        { userId: USER_ID, action: 'approve', granted: true },
      ],
    }),
    /Invalid permission action/
  );
  assert.equal(queries.some((query) => query.sql === 'BEGIN'), false);
  assert.equal(queries.some((query) => query.sql === 'COMMIT'), false);
});
