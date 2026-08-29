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
      if (normalized.includes('AS employee_exists')) {
        return {
          rowCount: 1,
          rows: [{
            employee_exists: true,
            employee_is_active: true,
            employee_status: 'active',
            department_exists: true,
            department_is_active: true,
            position_exists: true,
            position_is_active: true,
            position_department_id: '22222222-2222-4222-8222-222222222222',
            shift_exists: true,
            shift_is_active: true,
          }],
        };
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

test('failed policy insert rolls back the primary assignment on the same client', async () => {
  const clientCalls = [];
  let released = false;
  let poolQueryCount = 0;
  const client = {
    async query(sql) {
      const normalized = String(sql).trim();
      clientCalls.push(normalized);
      if (['BEGIN', 'ROLLBACK'].includes(normalized)) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.includes('AS employee_exists')) {
        return {
          rowCount: 1,
          rows: [{
            employee_exists: true,
            employee_is_active: true,
            employee_status: 'active',
            department_exists: true,
            department_is_active: true,
            position_exists: true,
            position_is_active: true,
            position_department_id: '22222222-2222-4222-8222-222222222222',
            shift_exists: true,
            shift_is_active: true,
          }],
        };
      }
      if (normalized.startsWith('SELECT id, effective_from')) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('INSERT INTO assignments')) {
        return {
          rowCount: 1,
          rows: [{
            id: '55555555-5555-4555-8555-555555555555',
            employee_id: '11111111-1111-4111-8111-111111111111',
            department_id: '22222222-2222-4222-8222-222222222222',
            position_id: '33333333-3333-4333-8333-333333333333',
            shift_id: '44444444-4444-4444-8444-444444444444',
            effective_from: '2026-09-01',
            effective_to: null,
            is_active: true,
            remarks: null,
          }],
        };
      }
      if (normalized.startsWith('SELECT pg_advisory_xact_lock')) {
        return { rowCount: 1, rows: [{}] };
      }
      if (normalized.startsWith('SELECT id, attendance_policy_id')) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('UPDATE policy_assignments')) {
        return { rowCount: 1, rows: [] };
      }
      if (normalized.startsWith('INSERT INTO policy_assignments')) {
        throw new Error('simulated policy insert failure');
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
        attendance_policy_id: '66666666-6666-4666-8666-666666666666',
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
    assert.equal(clientCalls.includes('COMMIT'), false);
    assert.ok(clientCalls.some((sql) => sql.startsWith('INSERT INTO assignments')));
    assert.ok(clientCalls.some((sql) => sql.startsWith('INSERT INTO policy_assignments')));
    assert.equal(released, true);
  } finally {
    console.error = originalConsoleError;
    delete require.cache[routePath];
    restoreDb();
  }
});

test('standalone policy upsert rolls back through one checked-out client', async () => {
  const clientCalls = [];
  let released = false;
  let poolQueryCount = 0;
  const client = {
    async query(sql) {
      const normalized = String(sql).trim();
      clientCalls.push(normalized);
      if (['BEGIN', 'ROLLBACK'].includes(normalized)) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('SELECT pg_advisory_xact_lock')) {
        return { rowCount: 1, rows: [{}] };
      }
      if (normalized.startsWith('SELECT id, attendance_policy_id')) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('UPDATE policy_assignments')) {
        return { rowCount: 1, rows: [] };
      }
      if (normalized.startsWith('INSERT INTO policy_assignments')) {
        throw new Error('simulated standalone policy insert failure');
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
  const routePath = require.resolve('../src/routes/policyAssignments');
  delete require.cache[routePath];
  const originalConsoleError = console.error;
  console.error = () => {};
  try {
    const router = require('../src/routes/policyAssignments');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/employee-upsert' && entry.route.methods.post
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      body: {
        employee_id: '11111111-1111-4111-8111-111111111111',
        attendance_policy_id: '66666666-6666-4666-8666-666666666666',
        effective_from: '2026-09-01',
        effective_to: null,
        is_active: true,
      },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 500);
    assert.equal(res.body.error, 'Failed to upsert employee policy assignment');
    assert.equal(poolQueryCount, 0);
    assert.deepEqual(
      clientCalls.filter((sql) => ['BEGIN', 'ROLLBACK'].includes(sql)),
      ['BEGIN', 'ROLLBACK']
    );
    assert.equal(clientCalls.includes('COMMIT'), false);
    assert.ok(clientCalls.some((sql) => sql.startsWith('INSERT INTO policy_assignments')));
    assert.equal(released, true);
  } finally {
    console.error = originalConsoleError;
    delete require.cache[routePath];
    restoreDb();
  }
});

test('moving a future transfer later restores its predecessor in the update transaction', async () => {
  const previous = {
    id: '55555555-5555-4555-8555-555555555555',
    employee_id: '11111111-1111-4111-8111-111111111111',
    department_id: '22222222-2222-4222-8222-222222222222',
    position_id: '33333333-3333-4333-8333-333333333333',
    shift_id: '44444444-4444-4444-8444-444444444444',
    effective_from: '2026-09-01',
    effective_to: null,
    is_active: true,
    remarks: null,
  };
  const replacement = { ...previous, effective_from: '2026-10-01' };
  const predecessor = {
    id: '77777777-7777-4777-8777-777777777777',
    employee_id: previous.employee_id,
    effective_from: '2026-01-01',
    effective_to: '2026-08-31',
    is_active: true,
  };
  const restored = { ...predecessor, effective_to: '2026-09-30' };
  const calls = [];
  let released = false;
  const client = {
    async query(sql, params = []) {
      const normalized = String(sql).trim();
      calls.push({ normalized, params });
      if (['BEGIN', 'COMMIT'].includes(normalized)) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('SELECT id, employee_id')) {
        return { rowCount: 1, rows: [previous] };
      }
      if (normalized.includes('AS employee_exists')) {
        return {
          rowCount: 1,
          rows: [{
            employee_exists: true,
            employee_is_active: true,
            employee_status: 'active',
            employee_date_hired: '2020-01-01',
            employee_separation_date: null,
            department_exists: true,
            department_is_active: true,
            position_exists: true,
            position_is_active: true,
            position_department_id: previous.department_id,
            shift_exists: true,
            shift_is_active: true,
          }],
        };
      }
      if (normalized.startsWith('SELECT id, effective_from')) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('UPDATE assignments') &&
          normalized.includes('SET department_id')) {
        return { rowCount: 1, rows: [replacement] };
      }
      if (normalized.includes('AS is_future')) {
        return { rowCount: 1, rows: [{ is_future: true }] };
      }
      if (normalized.startsWith('SELECT *') &&
          normalized.includes('effective_to = ($3::date')) {
        return { rowCount: 1, rows: [predecessor] };
      }
      if (normalized.startsWith('UPDATE assignments') &&
          normalized.includes('SET effective_to')) {
        assert.equal(params[1], '2026-09-30');
        return { rowCount: 1, rows: [restored] };
      }
      if (normalized.startsWith('INSERT INTO audit_logs')) {
        return { rowCount: 1, rows: [] };
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
      throw new Error('pool.query must not be used inside this transaction');
    },
  };

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = require.resolve('../src/routes/assignments');
  delete require.cache[routePath];
  try {
    const router = require('../src/routes/assignments');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.put
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      params: { id: previous.id },
      body: { effective_from: '2026-10-01' },
      user: { id: '88888888-8888-4888-8888-888888888888' },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.effective_from, '2026-10-01');
    assert.deepEqual(res.body.predecessor_restored, restored);
    assert.equal(calls.at(-1).normalized, 'COMMIT');
    assert.equal(
      calls.some(({ normalized }) => normalized === 'ROLLBACK'),
      false
    );
    assert.equal(released, true);
  } finally {
    delete require.cache[routePath];
    restoreDb();
  }
});
