'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const SHIFT_ID = '22222222-2222-4222-8222-222222222222';
const ACTOR_ID = '11111111-1111-4111-8111-111111111111';

function shiftRow(overrides = {}) {
  return {
    id: SHIFT_ID,
    shift_number: 1,
    name: 'Morning Shift',
    start_time: '08:00:00',
    end_time: '17:00:00',
    break_end: '13:00:00',
    punch_mode: 'full_day',
    grace_period_minutes: 10,
    working_days: [1, 2, 3, 4, 5],
    is_active: true,
    ...overrides,
  };
}

function responseRecorder() {
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

function routeHandler(router, method, path) {
  const layer = router.stack.find(
    (entry) => entry.route?.path === path && entry.route.methods[method],
  );
  assert.ok(layer, `${method.toUpperCase()} ${path} route not found`);
  return layer.route.stack[layer.route.stack.length - 1].handle;
}

async function withShiftRoute(pool, callback) {
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = '../src/routes/shifts';
  clearModule(routePath);
  try {
    await callback(require(routePath));
  } finally {
    clearModule(routePath);
    restoreDb();
  }
}

function auditQuery(queries) {
  return queries.find(({ sql }) => /INSERT INTO audit_logs/i.test(sql));
}

function assertAuditBeforeCommit(queries) {
  const auditIndex = queries.findIndex(({ sql }) => /INSERT INTO audit_logs/i.test(sql));
  const commitIndex = queries.findIndex(({ sql }) => sql.trim() === 'COMMIT');
  assert.ok(auditIndex >= 0, 'audit insert is missing');
  assert.ok(commitIndex > auditIndex, 'audit must be written before commit');
}

test('shift creation and its audit event commit together', async () => {
  const queries = [];
  const created = shiftRow();
  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ sql: text, params });
      if (/INSERT INTO shifts/i.test(text)) {
        return { rowCount: 1, rows: [created] };
      }
      return { rowCount: 1, rows: [] };
    },
    release() {},
  };
  const pool = {
    query: async () => ({ rowCount: 0, rows: [] }),
    connect: async () => client,
  };

  await withShiftRoute(pool, async (router) => {
    const response = responseRecorder();
    await routeHandler(router, 'post', '/')(
      {
        user: { id: ACTOR_ID, role: 'admin' },
        body: {
          name: created.name,
          start_time: created.start_time,
          end_time: created.end_time,
          break_end: created.break_end,
          punch_mode: created.punch_mode,
          grace_period_minutes: created.grace_period_minutes,
          working_days: created.working_days,
          is_active: true,
        },
      },
      response,
    );
    assert.equal(response.statusCode, 201);
  });

  assertAuditBeforeCommit(queries);
  const audit = auditQuery(queries);
  assert.deepEqual(audit.params.slice(0, 3), [ACTOR_ID, 'shift_created', SHIFT_ID]);
  const details = JSON.parse(audit.params[3]);
  assert.equal(details.before, null);
  assert.equal(details.after.name, created.name);
});

test('shift update audits before and after values in its transaction', async () => {
  const queries = [];
  const before = shiftRow();
  const after = shiftRow({ name: 'Renamed Morning Shift' });
  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ sql: text, params });
      if (/FROM shifts[\s\S]*FOR UPDATE/i.test(text)) {
        return { rowCount: 1, rows: [before] };
      }
      if (/UPDATE shifts SET/i.test(text)) {
        return { rowCount: 1, rows: [after] };
      }
      return { rowCount: 1, rows: [] };
    },
    release() {},
  };
  const pool = {
    query: async () => ({ rowCount: 0, rows: [] }),
    connect: async () => client,
  };

  await withShiftRoute(pool, async (router) => {
    const response = responseRecorder();
    await routeHandler(router, 'put', '/:id')(
      {
        user: { id: ACTOR_ID, role: 'admin' },
        params: { id: SHIFT_ID },
        body: { name: after.name },
      },
      response,
    );
    assert.equal(response.statusCode, 200);
  });

  assertAuditBeforeCommit(queries);
  const audit = auditQuery(queries);
  assert.deepEqual(audit.params.slice(0, 3), [ACTOR_ID, 'shift_updated', SHIFT_ID]);
  const details = JSON.parse(audit.params[3]);
  assert.equal(details.before.name, before.name);
  assert.equal(details.after.name, after.name);
});

test('unused shift deletion preserves its final snapshot in the audit event', async () => {
  const queries = [];
  const deleted = shiftRow({ is_active: false });
  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ sql: text, params });
      if (/FROM shifts[\s\S]*FOR UPDATE/i.test(text)) {
        return { rowCount: 1, rows: [deleted] };
      }
      if (/dependency_assignments/i.test(text)) {
        return {
          rowCount: 1,
          rows: [{
            dependency_assignments: 0,
            dependency_dtr_records: 0,
            dependency_policy_periods: 0,
          }],
        };
      }
      return { rowCount: 1, rows: [] };
    },
    release() {},
  };
  const pool = { connect: async () => client };

  await withShiftRoute(pool, async (router) => {
    const response = responseRecorder();
    await routeHandler(router, 'delete', '/:id')(
      {
        user: { id: ACTOR_ID, role: 'admin' },
        params: { id: SHIFT_ID },
      },
      response,
    );
    assert.equal(response.statusCode, 200);
  });

  assertAuditBeforeCommit(queries);
  const audit = auditQuery(queries);
  assert.deepEqual(audit.params.slice(0, 3), [ACTOR_ID, 'shift_deleted', SHIFT_ID]);
  const details = JSON.parse(audit.params[3]);
  assert.equal(details.before.name, deleted.name);
  assert.equal(details.before.is_active, false);
  assert.equal(details.after, null);
});
