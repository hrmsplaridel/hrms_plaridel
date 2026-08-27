const test = require('node:test');
const assert = require('node:assert/strict');

const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

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
    send(body) {
      this.body = body;
      return this;
    },
  };
}

test('direct employee deactivation revokes sessions and audits on one client', async () => {
  const actorId = '11111111-1111-4111-8111-111111111111';
  const employeeId = '22222222-2222-4222-8222-222222222222';
  const calls = [];
  let released = false;
  const client = {
    async query(sql) {
      const normalized = String(sql).replace(/\s+/g, ' ').trim();
      calls.push(normalized);
      if (
        normalized === 'BEGIN' ||
        normalized === 'COMMIT' ||
        normalized.startsWith('SELECT pg_advisory_xact_lock')
      ) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.includes('FROM users') && normalized.includes('FOR UPDATE')) {
        return {
          rowCount: 1,
          rows: [
            {
              id: employeeId,
              full_name: 'Employee User',
              email: 'employee@example.test',
              role: 'employee',
              is_active: true,
              employment_status: 'active',
            },
          ],
        };
      }
      if (normalized.startsWith('UPDATE users SET is_active = false')) {
        return { rowCount: 1, rows: [] };
      }
      if (normalized.startsWith('UPDATE auth_refresh_tokens')) {
        return { rowCount: 2, rows: [] };
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
    connect: async () => client,
    query: async () => {
      throw new Error('pool.query must not be used by direct deactivation');
    },
  };

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next(),
  });
  clearModule('../src/routes/employees');
  try {
    const router = require('../src/routes/employees');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.delete
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = { params: { id: employeeId }, user: { id: actorId, role: 'admin' } };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 204);
    assert.equal(calls[0], 'BEGIN');
    assert.equal(calls.at(-1), 'COMMIT');
    assert.ok(calls.some((sql) => sql.startsWith('UPDATE auth_refresh_tokens')));
    assert.ok(calls.some((sql) => sql.startsWith('INSERT INTO audit_logs')));
    assert.equal(released, true);
  } finally {
    clearModule('../src/routes/employees');
    restoreRbac();
    restoreAuth();
    restoreDb();
  }
});

test('bulk account status returns partial per-employee results', async () => {
  const actorId = '11111111-1111-4111-8111-111111111111';
  const activeEmployeeId = '33333333-3333-4333-8333-333333333333';
  const resignedEmployeeId = '44444444-4444-4444-8444-444444444444';
  const calls = [];
  const client = {
    async query(sql) {
      const normalized = String(sql).replace(/\s+/g, ' ').trim();
      calls.push(normalized);
      if (
        normalized === 'BEGIN' ||
        normalized === 'COMMIT' ||
        normalized.startsWith('SELECT pg_advisory_xact_lock')
      ) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.includes('FROM users') && normalized.includes('FOR UPDATE')) {
        return {
          rowCount: 2,
          rows: [
            {
              id: activeEmployeeId,
              full_name: 'Active Employee',
              email: 'active@example.test',
              role: 'employee',
              is_active: false,
              employment_status: 'active',
            },
            {
              id: resignedEmployeeId,
              full_name: 'Resigned Employee',
              email: 'resigned@example.test',
              role: 'employee',
              is_active: false,
              employment_status: 'resigned',
            },
          ],
        };
      }
      if (normalized.startsWith('UPDATE users SET is_active = $2')) {
        return { rowCount: 1, rows: [{ id: activeEmployeeId }] };
      }
      if (normalized.startsWith('INSERT INTO audit_logs')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected SQL: ${normalized}`);
    },
    release() {},
  };
  const pool = { connect: async () => client };

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware: (_req, _res, next) => next(),
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin: (_req, _res, next) => next(),
  });
  clearModule('../src/routes/employees');
  try {
    const router = require('../src/routes/employees');
    const layer = router.stack.find(
      (entry) =>
        entry.route?.path === '/bulk-status' && entry.route.methods.post
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      body: {
        employee_ids: [activeEmployeeId, resignedEmployeeId],
        is_active: true,
      },
      user: { id: actorId, role: 'admin' },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.requested, 2);
    assert.equal(res.body.updated, 1);
    assert.equal(res.body.rejected, 1);
    assert.equal(res.body.results[1].code, 'EMPLOYMENT_STATUS_NOT_ACTIVE');
    assert.ok(calls.includes('COMMIT'));
    assert.ok(calls.some((sql) => sql.startsWith('INSERT INTO audit_logs')));
  } finally {
    clearModule('../src/routes/employees');
    restoreRbac();
    restoreAuth();
    restoreDb();
  }
});
