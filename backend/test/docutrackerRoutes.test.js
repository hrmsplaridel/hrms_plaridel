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
    params: { id: 'doc-99' },
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
