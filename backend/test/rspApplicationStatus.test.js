const test = require('node:test');
const assert = require('node:assert/strict');

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

function statusHandler(pool) {
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const restoreIssued = withMockedModule('../src/services/rspIssuedForm', {
    assertIssuedFormSchema: async () => {},
    shouldEnableIssuedFormGate: (previous) =>
      previous === 'submitted' || previous === 'document_declined',
    assessmentBlocked: () => false,
    sendIssuedFormError: (res, err) => {
      res.status(err.status || 500).json({ error: err.message });
    },
  });
  const restorePre = withMockedModule('../src/services/rspPreDeliberation', {
    assertPreDeliberationSchema: async () => {},
    missingPrerequisites: () => [],
    sendPreDeliberationError: (res, err) => {
      res.status(err.status || 500).json({ error: err.message });
    },
  });
  const restoreFinal = withMockedModule('../src/services/rspFinalHiring', {
    assertFinalHiringSchema: async () => {},
    sendFinalHiringError: (res, err) => {
      res.status(err.status || 500).json({ error: err.message });
    },
  });
  const restoreNotices = withMockedModule('../src/services/rspApplicantNotices', {
    safeNotify: async (work) => work(),
    notifyDocumentDecision: async () => ({ sent: false }),
    notifyScheduleNotice: async () => ({ sent: false }),
    notifyActionRequired: async () => ({ sent: false }),
    notifyFinalRequirementReturned: async () => ({ sent: false }),
  });
  const routePath = require.resolve('../src/routes/rspApplications');
  delete require.cache[routePath];
  try {
    const router = require('../src/routes/rspApplications');
    const layer = router.stack.find(
      (entry) =>
        entry?.route?.path === '/:applicationId/status' && entry.route.methods?.put
    );
    assert.ok(layer, 'PUT /:applicationId/status not found');
    return layer.route.stack[layer.route.stack.length - 1].handle;
  } finally {
    delete require.cache[routePath];
    restoreNotices();
    restoreFinal();
    restorePre();
    restoreIssued();
    restoreDb();
  }
}

function response() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

const applicationId = '11111111-1111-4111-8111-111111111111';

test('RSP status route rejects statuses owned by other modules', async () => {
  const updates = [];
  const queries = [];
  const pool = {
    async connect() {
      return {
        query: (...args) => pool.query(...args),
        release() {},
      };
    },
    async query(sql, params) {
      const text = String(sql);
      queries.push(text);
      if (text.includes('UPDATE public.recruitment_applications') && /SET status\s*=/.test(text)) {
        updates.push(params);
        return { rowCount: 1, rows: [] };
      }
      if (text.includes('FOR UPDATE')) {
        return {
          rowCount: 1,
          rows: [{
            status: 'submitted',
            email: null,
            full_name: 'Ana Cruz',
            applicant_number: 'PLR-TEST',
            position_applied_for: 'Clerk',
          }],
        };
      }
      return { rowCount: 0, rows: [] };
    },
  };
  const handler = statusHandler(pool);

  for (const status of ['endorsed', 'rejected', 'approved']) {
    const res = response();
    await handler({ params: { applicationId }, body: { status } }, res);
    assert.equal(res.statusCode, 400, status);
  }
  assert.deepEqual(updates, []);
  assert.deepEqual(queries, [], 'Invalid status requests must not trigger schema changes or account backfills');

  const res = response();
  await handler({ params: { applicationId }, body: { status: 'document_approved' } }, res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(updates, [[
    'document_approved',
    applicationId,
    true,
  ]]);
});
