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
