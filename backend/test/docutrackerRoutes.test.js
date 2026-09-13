const test = require('node:test');
const assert = require('node:assert/strict');

function createMockResponse() {
  return {
    statusCode: 200,
    payload: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.payload = body;
      return this;
    },
  };
}

function withMockedModule(modulePath, exportsValue) {
  const resolved = require.resolve(modulePath);
  const previous = require.cache[resolved];
  require.cache[resolved] = {
    id: resolved,
    filename: resolved,
    loaded: true,
    exports: exportsValue,
  };
  return () => {
    if (previous) {
      require.cache[resolved] = previous;
    } else {
      delete require.cache[resolved];
    }
  };
}

function getRouteHandler(router, method, path) {
  const layer = router.stack.find(
    (entry) => entry?.route?.path === path && entry.route.methods?.[method]
  );
  assert.ok(layer, `Route ${method.toUpperCase()} ${path} not found`);
  return layer.route.stack[layer.route.stack.length - 1].handle;
}

function workflowServiceMock(overrides = {}) {
  return {
    DOC_ACTIONS: new Set(['view', 'approve', 'submit']),
    hasPermission: async () => null,
    canUserPerformTypeAction: async () => false,
    canUserPerformDocumentAction: async () => true,
    listDocuments: async () => [],
    getDocumentBundle: async () => null,
    createDocument: async () => ({}),
    transitionDocument: async () => ({}),
    updateDocumentMetadata: async () => ({}),
    recoverDocumentAssignment: async () => ({}),
    addDocumentRemark: async () => true,
    getEffectivePermissionExplanation: async () => ({}),
    ...overrides,
  };
}

test('GET /permission-explain returns explanation payload', async () => {
  const workflowService = {
    DOC_ACTIONS: new Set(['view', 'approve', 'submit']),
    hasPermission: async () => null,
    canUserPerformTypeAction: async () => false,
    canUserPerformDocumentAction: async () => true,
    listDocuments: async () => [],
    getDocumentBundle: async () => null,
    createDocument: async () => ({}),
    transitionDocument: async () => ({}),
    updateDocumentMetadata: async () => ({}),
    addDocumentRemark: async () => true,
    getEffectivePermissionExplanation: async () => ({
      scope: 'type',
      action: 'view',
      document_type: 'memo',
      explicit_matches: [],
      explicit_decision: null,
      fallback_decision: false,
      final_decision: false,
      reason: 'fallback_rule',
    }),
  };
  const restoreWorkflow = withMockedModule(
    '../src/services/docutrackerWorkflowService',
    workflowService
  );
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query: async () => ({ rowCount: 0, rows: [] }) },
  });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next?.(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next?.(),
  });

  const routePath = require.resolve('../src/routes/docutracker');
  delete require.cache[routePath];
  const router = require('../src/routes/docutracker');
  const handler = getRouteHandler(router, 'get', '/permission-explain');

  const req = {
    query: { document_type: 'memo', action: 'view' },
    user: { id: 'user-1', role: 'employee' },
    headers: {},
  };
  const res = createMockResponse();
  await handler(req, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.payload?.scope, 'type');
  assert.equal(res.payload?.final_decision, false);

  restoreWorkflow();
  restoreDb();
  restoreAuth();
  restoreRbac();
  delete require.cache[routePath];
});

test('POST /documents/:id/transition forwards idempotency key in body', async () => {
  let capturedPayload = null;
  const workflowService = {
    DOC_ACTIONS: new Set(['view', 'approve', 'submit']),
    hasPermission: async () => null,
    canUserPerformTypeAction: async () => true,
    canUserPerformDocumentAction: async () => true,
    listDocuments: async () => [],
    getDocumentBundle: async () => null,
    createDocument: async () => ({}),
    transitionDocument: async (_pool, _user, _id, _action, payload) => {
      capturedPayload = payload;
      return { ok: true };
    },
    updateDocumentMetadata: async () => ({}),
    addDocumentRemark: async () => true,
    getEffectivePermissionExplanation: async () => ({}),
  };
  const restoreWorkflow = withMockedModule(
    '../src/services/docutrackerWorkflowService',
    workflowService
  );
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query: async () => ({ rowCount: 0, rows: [] }) },
  });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next?.(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next?.(),
  });

  const routePath = require.resolve('../src/routes/docutracker');
  delete require.cache[routePath];
  const router = require('../src/routes/docutracker');
  const handler = getRouteHandler(router, 'post', '/documents/:id/transition');

  const req = {
    params: { id: '00000000-0000-4000-8000-000000000099' },
    body: { action: 'approve', remarks: 'ok', idempotency_key: 'idem-99' },
    headers: {},
    user: { id: 'user-2', role: 'admin' },
  };
  const res = createMockResponse();
  await handler(req, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.payload?.ok, true);
  assert.equal(capturedPayload?.idempotency_key, 'idem-99');
  assert.equal(capturedPayload?.remarks, 'ok');

  restoreWorkflow();
  restoreDb();
  restoreAuth();
  restoreRbac();
  delete require.cache[routePath];
});

test('POST /permissions normalizes create to create_draft', async () => {
  const queries = [];
  const restoreWorkflow = withMockedModule('../src/services/docutrackerWorkflowService', {
    DOC_ACTIONS: new Set(['view', 'approve', 'submit']),
    hasPermission: async () => null,
    canUserPerformTypeAction: async () => true,
    canUserPerformDocumentAction: async () => true,
    listDocuments: async () => [],
    getDocumentBundle: async () => null,
    createDocument: async () => ({}),
    transitionDocument: async () => ({}),
    updateDocumentMetadata: async () => ({}),
    addDocumentRemark: async () => true,
    getEffectivePermissionExplanation: async () => ({}),
  });
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      query: async (sql, params = []) => {
        queries.push({ sql, params });
        if (sql.includes('SELECT id FROM docutracker_permissions')) {
          return { rowCount: 0, rows: [] };
        }
        if (sql.includes('INSERT INTO docutracker_permissions')) {
          return {
            rowCount: 1,
            rows: [
              {
                id: 'perm-1',
                user_id: 'user-1',
                role_id: null,
                document_type: 'memo',
                action: 'create_draft',
                granted: true,
              },
            ],
          };
        }
        return { rowCount: 0, rows: [] };
      },
    },
  });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next?.(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next?.(),
  });

  const routePath = require.resolve('../src/routes/docutracker');
  delete require.cache[routePath];
  const router = require('../src/routes/docutracker');
  const handler = getRouteHandler(router, 'post', '/permissions');

  const req = {
    body: {
      user_id: 'user-1',
      document_type: 'memo',
      action: 'create',
      granted: true,
    },
    headers: {},
    user: { id: 'admin-1', role: 'admin' },
  };
  const res = createMockResponse();
  await handler(req, res);

  assert.equal(res.statusCode, 201);
  assert.equal(res.payload?.action, 'create_draft');
  const insertCall = queries.find((q) => q.sql.includes('INSERT INTO docutracker_permissions'));
  assert.ok(insertCall);
  assert.equal(insertCall.params[3], 'create_draft');

  restoreWorkflow();
  restoreDb();
  restoreAuth();
  restoreRbac();
  delete require.cache[routePath];
});

test('PUT /workflow-steps/:stepId/assignees accepts an empty replacement set', async () => {
  const queries = [];
  let auditedAfterState = null;
  const client = {
    async query(sql, params = []) {
      queries.push({ sql, params });
      if (sql.includes('SELECT id, department_id')) {
        return {
          rowCount: 1,
          rows: [{ id: 'step-1', department_id: null }],
        };
      }
      return { rowCount: 0, rows: [] };
    },
    release() {},
  };
  const restoreWorkflow = withMockedModule('../src/services/docutrackerWorkflowService', {
    DOC_ACTIONS: new Set(['view', 'approve', 'submit']),
  });
  const restoreAudit = withMockedModule('../src/services/docutrackerGovernanceAudit', {
    writeGovernanceAudit: async (_client, entry) => {
      auditedAfterState = entry.afterState;
    },
  });
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      connect: async () => client,
      query: async () => ({ rowCount: 0, rows: [] }),
    },
  });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next?.(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next?.(),
  });

  const routePath = require.resolve('../src/routes/docutracker');
  delete require.cache[routePath];
  const router = require('../src/routes/docutracker');
  const handler = getRouteHandler(router, 'put', '/workflow-steps/:stepId/assignees');

  const req = {
    params: { stepId: 'step-1' },
    body: { assignees: [] },
    headers: {},
    user: { id: 'admin-1', role: 'admin' },
  };
  const res = createMockResponse();
  await handler(req, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.payload?.updated, 0);
  assert.deepEqual(auditedAfterState, { assignees: [] });
  assert.ok(
    queries.some((q) => q.sql.includes('DELETE FROM docutracker_workflow_step_assignees'))
  );
  assert.equal(
    queries.some((q) => q.sql.includes('INSERT INTO docutracker_workflow_step_assignees')),
    false
  );
  assert.ok(queries.some((q) => q.sql === 'COMMIT'));

  restoreWorkflow();
  restoreAudit();
  restoreDb();
  restoreAuth();
  restoreRbac();
  delete require.cache[routePath];
});

test('POST /documents/:id/history rejects client-authored audit entries', async () => {
  const restoreWorkflow = withMockedModule(
    '../src/services/docutrackerWorkflowService', workflowServiceMock()
  );
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query: async () => { throw new Error('history route must not query'); } },
  });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next?.(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next?.(),
  });
  const routePath = require.resolve('../src/routes/docutracker');
  delete require.cache[routePath];
  const router = require('../src/routes/docutracker');
  const handler = getRouteHandler(router, 'post', '/documents/:id/history');
  const res = createMockResponse();

  await handler({ params: { id: 'doc-1' }, body: { action: 'approved' } }, res);

  assert.equal(res.statusCode, 405);
  assert.match(res.payload?.error, /server-side workflow operations/i);
  restoreWorkflow(); restoreDb(); restoreAuth(); restoreRbac();
  delete require.cache[routePath];
});

test('PUT /documents/:id sends metadata through the transactional service', async () => {
  let captured = null;
  const restoreWorkflow = withMockedModule(
    '../src/services/docutrackerWorkflowService',
    workflowServiceMock({
      updateDocumentMetadata: async (_pool, user, id, payload) => {
        captured = { user, id, payload };
        return { id, title: payload.title };
      },
    })
  );
  const restoreDb = withMockedModule('../src/config/db', { pool: {} });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next?.(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next?.(),
  });
  const routePath = require.resolve('../src/routes/docutracker');
  delete require.cache[routePath];
  const router = require('../src/routes/docutracker');
  const handler = getRouteHandler(router, 'put', '/documents/:id');
  const req = {
    params: { id: 'doc-2' }, body: { title: 'Revised memo' },
    user: { id: 'creator-1', role: 'employee' },
  };
  const res = createMockResponse();

  await handler(req, res);

  assert.equal(res.statusCode, 200);
  assert.equal(captured?.id, 'doc-2');
  assert.deepEqual(captured?.payload, { title: 'Revised memo' });
  restoreWorkflow(); restoreDb(); restoreAuth(); restoreRbac();
  delete require.cache[routePath];
});

test('PUT /documents/:id rejects workflow fields even for administrators', async () => {
  let called = false;
  const restoreWorkflow = withMockedModule(
    '../src/services/docutrackerWorkflowService',
    workflowServiceMock({ updateDocumentMetadata: async () => { called = true; } })
  );
  const restoreDb = withMockedModule('../src/config/db', { pool: {} });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next?.(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next?.(),
  });
  const routePath = require.resolve('../src/routes/docutracker');
  delete require.cache[routePath];
  const router = require('../src/routes/docutracker');
  const handler = getRouteHandler(router, 'put', '/documents/:id');
  const res = createMockResponse();

  await handler({
    params: { id: 'doc-3' }, body: { status: 'approved' },
    user: { id: 'admin-1', role: 'admin' },
  }, res);

  assert.equal(res.statusCode, 400);
  assert.equal(called, false);
  restoreWorkflow(); restoreDb(); restoreAuth(); restoreRbac();
  delete require.cache[routePath];
});

test('PATCH /documents/:id only forwards recovery reassignment fields', async () => {
  let captured = null;
  const restoreWorkflow = withMockedModule(
    '../src/services/docutrackerWorkflowService',
    workflowServiceMock({
      recoverDocumentAssignment: async (_pool, user, id, payload) => {
        captured = { user, id, payload };
        return { id, current_holder_id: payload.current_holder_id, status: 'returned' };
      },
    })
  );
  const restoreDb = withMockedModule('../src/config/db', { pool: {} });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next?.(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next?.(),
  });
  const routePath = require.resolve('../src/routes/docutracker');
  delete require.cache[routePath];
  const router = require('../src/routes/docutracker');
  const handler = getRouteHandler(router, 'patch', '/documents/:id');
  const req = {
    params: { id: 'doc-4' },
    body: { current_holder_id: 'backup-1', remarks: 'Primary unavailable' },
    user: { id: 'admin-1', role: 'admin' },
  };
  const res = createMockResponse();

  await handler(req, res);

  assert.equal(res.statusCode, 200);
  assert.equal(captured?.id, 'doc-4');
  assert.deepEqual(captured?.payload, req.body);
  const rejected = createMockResponse();
  await handler({ ...req, body: { ...req.body, current_step: 2 } }, rejected);
  assert.equal(rejected.statusCode, 400);
  restoreWorkflow(); restoreDb(); restoreAuth(); restoreRbac();
  delete require.cache[routePath];
});

test('POST /routing-configs rejects duplicate primary and backup IDs before saving', async () => {
  let connected = false;
  const restoreWorkflow = withMockedModule(
    '../src/services/docutrackerWorkflowService', workflowServiceMock()
  );
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { connect: async () => { connected = true; throw new Error('must not connect'); } },
  });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next?.(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next?.(),
  });
  const routePath = require.resolve('../src/routes/docutracker');
  delete require.cache[routePath];
  const router = require('../src/routes/docutracker');
  const handler = getRouteHandler(router, 'post', '/routing-configs');
  const res = createMockResponse();

  await handler({
    body: {
      document_type: 'memo',
      steps: [{
        step_order: 1, assignee_type: 'user', assignee_source: 'specific_users',
        user_ids: ['same-user', 'same-user'], allowed_actions: ['approve'],
      }],
    },
    user: { id: 'admin-1', role: 'admin' },
  }, res);

  assert.equal(res.statusCode, 400);
  assert.match(res.payload?.error, /same user as both primary and backup/i);
  assert.equal(connected, false);
  restoreWorkflow(); restoreDb(); restoreAuth(); restoreRbac();
  delete require.cache[routePath];
});
