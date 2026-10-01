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
  const handler = statusHandler({
    async query(sql, params) {
      if (sql.includes('UPDATE public.recruitment_applications')) {
        updates.push(params);
        return { rowCount: 1, rows: [] };
      }
      return { rowCount: 0, rows: [] };
    },
  });

  for (const status of ['endorsed', 'rejected', 'approved']) {
    const res = response();
    await handler({ params: { applicationId }, body: { status } }, res);
    assert.equal(res.statusCode, 400, status);
  }
  assert.deepEqual(updates, []);

  const res = response();
  await handler({ params: { applicationId }, body: { status: 'document_approved' } }, res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(updates, [['document_approved', applicationId]]);
});
