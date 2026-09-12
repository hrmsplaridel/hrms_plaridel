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

async function exerciseMutation(method, body, {
  before = shiftRow(), dependencies = {}, auditFails = false,
} = {}) {
  const queries = [];
  let released = false;
  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ sql: text, params });
      if (/FROM shifts[\s\S]*FOR UPDATE/i.test(text)) return { rows: [before], rowCount: 1 };
      if (/dependency_assignments|deactivation_assignments/i.test(text)) {
        return { rows: [dependencies], rowCount: 1 };
      }
      if (/INSERT INTO audit_logs/i.test(text) && auditFails) throw new Error('Simulated audit failure');
      if (/INSERT INTO shifts|UPDATE shifts SET/i.test(text)) {
        return { rows: [{ ...before, ...body }], rowCount: 1 };
      }
      return { rows: [], rowCount: 1 };
    },
    release() { released = true; },
  };
  const response = responseRecorder();
  await withShiftRoute({ connect: async () => client }, async (router) => {
    await routeHandler(router, method, method === 'post' ? '/' : '/:id')({
      user: { id: ACTOR_ID, role: 'admin' }, params: { id: SHIFT_ID }, body,
    }, response);
  });
  return { queries, response, released };
}

for (const method of ['post', 'put', 'delete']) {
  test(`${method} rolls back and releases its client if the audit insert fails`, async () => {
    const { queries, response, released } = await exerciseMutation(method, shiftRow(), { auditFails: true });
    assert.equal(response.statusCode, 500);
    assert.ok(auditQuery(queries));
    assert.ok(queries.some(({ sql }) => sql === 'ROLLBACK'));
    assert.ok(!queries.some(({ sql }) => sql === 'COMMIT'));
    assert.equal(released, true);
  });
}

for (const [label, changes] of [
  ['malformed time', { start_time: '8am' }],
  ['overnight range', { start_time: '22:00', end_time: '06:00' }],
  ['missing full-day PM Start', { break_end: null }],
  ['incompatible PM-only mode', { punch_mode: 'pm_only', break_end: null }],
  ['duplicate weekdays', { working_days: [1, 1] }],
  ['string weekdays', { working_days: ['1'] }],
  ['fractional grace', { grace_period_minutes: 1.5 }],
  ['excessive grace', { grace_period_minutes: 241 }],
  ['string active flag', { is_active: 'false' }],
]) {
  for (const method of ['post', 'put']) {
    test(`${method} rejects ${label} without mutating shifts`, async () => {
      const { queries, response } = await exerciseMutation(method, { ...shiftRow(), ...changes });
      assert.equal(response.statusCode, 400);
      assert.ok(!queries.some(({ sql }) => /INSERT INTO shifts|UPDATE shifts SET|INSERT INTO audit_logs/.test(sql)));
      assert.ok(!queries.some(({ sql }) => sql === 'COMMIT'));
    });
  }
}

for (const [label, body, dependencies] of [
  ['historical schedule edit', { start_time: '09:00' }, { dependency_assignments: 1 }],
  ['DTR-only schedule edit', { start_time: '09:00' }, { dependency_dtr_records: 1 }],
  ['policy-only schedule edit', { grace_period_minutes: 20 }, { dependency_policy_periods: 1 }],
  ['current assignment deactivation', { is_active: false }, { deactivation_assignments: 1 }],
]) {
  test(`PUT blocks ${label} before writing`, async () => {
    const { queries, response, released } = await exerciseMutation('put', body, { dependencies });
    assert.equal(response.statusCode, 409);
    assert.ok(queries.some(({ sql }) => sql === 'ROLLBACK'));
    assert.ok(!queries.some(({ sql }) => /UPDATE shifts SET|INSERT INTO audit_logs/.test(sql)));
    assert.equal(released, true);
  });
}

test('DELETE rejects a shift with DTR history even without assignments', async () => {
  const { queries, response, released } = await exerciseMutation('delete', {}, {
    dependencies: { dependency_dtr_records: 1 },
  });
  assert.equal(response.statusCode, 409);
  assert.ok(queries.some(({ sql }) => sql === 'ROLLBACK'));
  assert.ok(!queries.some(({ sql }) => /DELETE FROM shifts|INSERT INTO audit_logs/.test(sql)));
  assert.equal(released, true);
});

for (const active of [true, false]) {
  test(`PUT audits ${active ? 'reactivation' : 'deactivation'} and preserves schedule`, async () => {
    const { queries, response, released } = await exerciseMutation('put', { is_active: active }, {
      before: shiftRow({ is_active: !active }),
    });
    assert.equal(response.statusCode, 200);
    assertAuditBeforeCommit(queries);
    const audit = auditQuery(queries);
    assert.equal(audit.params[1], active ? 'shift_reactivated' : 'shift_deactivated');
    const { before, after } = JSON.parse(audit.params[3]);
    assert.equal(before.is_active, !active);
    assert.equal(after.is_active, active);
    assert.equal(after.start_time, before.start_time);
    assert.equal(released, true);
  });
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
