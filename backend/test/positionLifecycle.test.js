'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule } = require('./helpers/moduleMocks');

const {
  PositionLifecycleError,
  deleteMistakenPosition,
  ensurePositionDepartmentChangeAllowed,
  positionDependencyCountsSql,
} = require('../src/services/positionLifecycle');

const IDS = {
  actor: '11111111-1111-4111-8111-111111111111',
  position: '22222222-2222-4222-8222-222222222222',
  oldDepartment: '33333333-3333-4333-8333-333333333333',
  newDepartment: '44444444-4444-4444-8444-444444444444',
};

function positionRow() {
  return {
    id: IDS.position,
    position_number: 12,
    name: 'HR Officer',
    description: null,
    department_id: IDS.oldDepartment,
    is_department_head: false,
    is_active: true,
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

test('used position cannot be moved to another department', async () => {
  const calls = [];
  const db = {
    async query(sql) {
      const text = String(sql).trim();
      calls.push(text);
      if (text.includes('FROM positions') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [positionRow()] };
      }
      if (text.includes('AS dependency_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [{
            dependency_primary_assignments: 2,
            dependency_additional_positions: 1,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  await assert.rejects(
    ensurePositionDepartmentChangeAllowed(db, {
      positionId: IDS.position,
      nextDepartmentId: IDS.newDepartment,
    }),
    (error) => {
      assert.ok(error instanceof PositionLifecycleError);
      assert.equal(error.statusCode, 409);
      assert.deepEqual(error.details.dependencies, {
        primary_assignments: 2,
        additional_positions: 1,
      });
      return true;
    }
  );
  assert.equal(calls.length, 2);
});

test('unused position can be moved to another department', async () => {
  const db = {
    async query(sql) {
      const text = String(sql).trim();
      if (text.includes('FROM positions') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [positionRow()] };
      }
      if (text.includes('AS dependency_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [{
            dependency_primary_assignments: 0,
            dependency_additional_positions: 0,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const result = await ensurePositionDepartmentChangeAllowed(db, {
    positionId: IDS.position,
    nextDepartmentId: IDS.newDepartment,
  });

  assert.equal(result.id, IDS.position);
});

test('unchanged department does not require a dependency scan', async () => {
  let queryCount = 0;
  const db = {
    async query(sql) {
      queryCount += 1;
      const text = String(sql).trim();
      if (text.includes('FROM positions') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [positionRow()] };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  await ensurePositionDepartmentChangeAllowed(db, {
    positionId: IDS.position,
    nextDepartmentId: IDS.oldDepartment,
  });

  assert.equal(queryCount, 1);
});

test('position route rolls back and returns 409 when assignment history blocks movement', async () => {
  const clientCalls = [];
  let released = false;
  const client = {
    async query(sql) {
      const text = String(sql).trim();
      clientCalls.push(text);
      if (text === 'BEGIN' || text === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (text.includes('FROM positions') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [positionRow()] };
      }
      if (text.includes('AS dependency_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [{
            dependency_primary_assignments: 1,
            dependency_additional_positions: 0,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
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
      throw new Error('pool.query must not be used inside the update transaction');
    },
  };

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = require.resolve('../src/routes/positions');
  delete require.cache[routePath];
  const originalConsoleError = console.error;
  console.error = () => {};
  try {
    const router = require('../src/routes/positions');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.put
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      params: { id: IDS.position },
      user: { id: IDS.actor, role: 'admin' },
      body: { department_id: IDS.newDepartment },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 409);
    assert.match(res.body.error, /assignment history/i);
    assert.deepEqual(res.body.dependencies, {
      primary_assignments: 1,
      additional_positions: 0,
    });
    assert.equal(clientCalls[0], 'BEGIN');
    assert.equal(clientCalls.at(-1), 'ROLLBACK');
    assert.equal(clientCalls.some((sql) => sql.startsWith('UPDATE positions')), false);
    assert.equal(released, true);
  } finally {
    console.error = originalConsoleError;
    delete require.cache[routePath];
    restoreDb();
  }
});

test('position route commits a department correction for an unused position', async () => {
  const clientCalls = [];
  let released = false;
  const updated = { ...positionRow(), department_id: IDS.newDepartment };
  const client = {
    async query(sql) {
      const text = String(sql).trim();
      clientCalls.push(text);
      if (text === 'BEGIN' || text === 'COMMIT') {
        return { rowCount: 0, rows: [] };
      }
      if (text.includes('FROM positions') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [positionRow()] };
      }
      if (text.includes('AS dependency_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [{
            dependency_primary_assignments: 0,
            dependency_additional_positions: 0,
          }],
        };
      }
      if (text.startsWith('UPDATE positions')) {
        return { rowCount: 1, rows: [updated] };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
    release() {
      released = true;
    },
  };
  const pool = {
    async connect() {
      return client;
    },
  };

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = require.resolve('../src/routes/positions');
  delete require.cache[routePath];
  try {
    const router = require('../src/routes/positions');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.put
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      params: { id: IDS.position },
      user: { id: IDS.actor, role: 'admin' },
      body: { department_id: IDS.newDepartment },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.department_id, IDS.newDepartment);
    assert.equal(clientCalls[0], 'BEGIN');
    assert.equal(clientCalls.at(-1), 'COMMIT');
    assert.equal(clientCalls.some((sql) => sql === 'ROLLBACK'), false);
    assert.equal(released, true);
  } finally {
    delete require.cache[routePath];
    restoreDb();
  }
});

test('position dependency projection covers primary and additional assignments', () => {
  const sql = positionDependencyCountsSql('p');
  assert.match(sql, /FROM assignments WHERE position_id = p\.id/);
  assert.match(sql, /FROM employee_other_positions WHERE position_id = p\.id/);
});

test('unused mistaken position deletion preserves an audit snapshot', async () => {
  const calls = [];
  const db = {
    async query(sql, params = []) {
      const text = String(sql).trim();
      calls.push({ text, params });
      if (text.includes('FROM positions') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [positionRow()] };
      }
      if (text.includes('AS dependency_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [{
            dependency_primary_assignments: 0,
            dependency_additional_positions: 0,
          }],
        };
      }
      if (text.startsWith('DELETE FROM positions')) {
        return { rowCount: 1, rows: [] };
      }
      if (text.startsWith('INSERT INTO audit_logs')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const result = await deleteMistakenPosition(db, {
    actorId: IDS.actor,
    positionId: IDS.position,
    reason: 'Created under the wrong title',
  });

  assert.equal(result.position.id, IDS.position);
  const audit = calls.find(({ text }) => text.startsWith('INSERT INTO audit_logs'));
  assert.ok(audit);
  assert.deepEqual(audit.params.slice(0, 3), [
    IDS.actor,
    'position_mistake_deleted',
    IDS.position,
  ]);
  assert.deepEqual(JSON.parse(audit.params[3]), {
    reason: 'Created under the wrong title',
    before: positionRow(),
    after: null,
  });
});

test('used position deletion is rejected with named blockers', async () => {
  const calls = [];
  const db = {
    async query(sql) {
      const text = String(sql).trim();
      calls.push(text);
      if (text.includes('FROM positions') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [positionRow()] };
      }
      if (text.includes('AS dependency_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [{
            dependency_primary_assignments: 3,
            dependency_additional_positions: 1,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  await assert.rejects(
    deleteMistakenPosition(db, {
      actorId: IDS.actor,
      positionId: IDS.position,
      reason: 'Testing cleanup',
    }),
    (error) => {
      assert.ok(error instanceof PositionLifecycleError);
      assert.equal(error.statusCode, 409);
      assert.deepEqual(error.details.blockers, [
        { key: 'primary_assignments', label: 'primary assignments', count: 3 },
        { key: 'additional_positions', label: 'additional positions', count: 1 },
      ]);
      return true;
    }
  );
  assert.equal(calls.some((sql) => sql.startsWith('DELETE FROM positions')), false);
  assert.equal(calls.some((sql) => sql.startsWith('INSERT INTO audit_logs')), false);
});

test('position delete route rolls back and returns blockers for a used position', async () => {
  const clientCalls = [];
  let released = false;
  const client = {
    async query(sql) {
      const text = String(sql).trim();
      clientCalls.push(text);
      if (text === 'BEGIN' || text === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (text.includes('FROM positions') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [positionRow()] };
      }
      if (text.includes('AS dependency_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [{
            dependency_primary_assignments: 1,
            dependency_additional_positions: 0,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
    release() {
      released = true;
    },
  };
  const pool = {
    async connect() {
      return client;
    },
  };

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = require.resolve('../src/routes/positions');
  delete require.cache[routePath];
  const originalConsoleError = console.error;
  console.error = () => {};
  try {
    const router = require('../src/routes/positions');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.delete
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      params: { id: IDS.position },
      user: { id: IDS.actor, role: 'admin' },
      body: { reason: 'Testing cleanup' },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 409);
    assert.match(res.body.error, /cannot be permanently deleted/i);
    assert.deepEqual(res.body.blockers, [
      { key: 'primary_assignments', label: 'primary assignments', count: 1 },
    ]);
    assert.equal(clientCalls[0], 'BEGIN');
    assert.equal(clientCalls.at(-1), 'ROLLBACK');
    assert.equal(clientCalls.some((sql) => sql.startsWith('DELETE FROM positions')), false);
    assert.equal(released, true);
  } finally {
    console.error = originalConsoleError;
    delete require.cache[routePath];
    restoreDb();
  }
});
