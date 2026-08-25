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
    if (previous) require.cache[resolved] = previous;
    else delete require.cache[resolved];
  };
}

function responseRecorder() {
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

test('failed assignment insert rolls back on the same checked-out client', async () => {
  const clientCalls = [];
  let released = false;
  let poolQueryCount = 0;
  const client = {
    async query(sql) {
      const normalized = String(sql).trim();
      clientCalls.push(normalized);
      if (normalized === 'BEGIN' || normalized === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('SELECT id, effective_from')) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('INSERT INTO assignments')) {
        const error = new Error('simulated insert failure');
        error.code = 'XX001';
        throw error;
      }
      throw new Error(`Unexpected SQL: ${normalized}`);
    },
    release() {
      released = true;
    },
  };
  const pool = {
    async connect() {
      return client;
    },
    async query() {
      poolQueryCount += 1;
      throw new Error('pool.query must not be used inside this transaction');
    },
  };

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = require.resolve('../src/routes/assignments');
  delete require.cache[routePath];
  const originalConsoleError = console.error;
  console.error = () => {};
  try {
    const router = require('../src/routes/assignments');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/' && entry.route.methods.post
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      body: {
        employee_id: '11111111-1111-4111-8111-111111111111',
        department_id: '22222222-2222-4222-8222-222222222222',
        position_id: '33333333-3333-4333-8333-333333333333',
        shift_id: '44444444-4444-4444-8444-444444444444',
        effective_from: '2026-09-01',
        is_active: true,
      },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 500);
    assert.equal(res.body.error, 'Failed to create assignment');
    assert.equal(poolQueryCount, 0);
    assert.equal(clientCalls[0], 'BEGIN');
    assert.equal(clientCalls.at(-1), 'ROLLBACK');
    assert.equal(released, true);
  } finally {
    console.error = originalConsoleError;
    delete require.cache[routePath];
    restoreDb();
  }
});
