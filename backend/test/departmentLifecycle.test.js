'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const {
  DEPARTMENT_DEPENDENCIES,
  DepartmentLifecycleError,
  deleteMistakenDepartment,
  departmentDependencyCountsSql,
} = require('../src/services/departmentLifecycle');

const IDS = {
  actor: '11111111-1111-4111-8111-111111111111',
  department: '22222222-2222-4222-8222-222222222222',
};

function departmentRow() {
  return {
    id: IDS.department,
    department_number: 12,
    name: 'Mistaken Department',
    description: null,
    is_active: true,
    created_at: '2026-08-30T00:00:00.000Z',
    updated_at: '2026-08-30T00:00:00.000Z',
  };
}

function emptyDependencyRow(overrides = {}) {
  return {
    ...Object.fromEntries(
      DEPARTMENT_DEPENDENCIES.map(({ key }) => [`dependency_${key}`, 0])
    ),
    ...overrides,
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

test('dependency projection covers every department foreign-key owner', () => {
  const sql = departmentDependencyCountsSql('d');
  for (const dependency of DEPARTMENT_DEPENDENCIES) {
    assert.match(sql, new RegExp(`FROM ${dependency.table}`));
    assert.match(sql, new RegExp(`${dependency.column} = d\\.id`));
  }
});

test('unused mistaken department is deleted and audited', async () => {
  const calls = [];
  const db = {
    async query(sql, params = []) {
      const text = String(sql).trim();
      calls.push({ text, params });
      if (text.includes('FROM departments') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [departmentRow()] };
      }
      if (text.startsWith('SELECT (SELECT COUNT')) {
        return { rowCount: 1, rows: [emptyDependencyRow()] };
      }
      if (text.startsWith('DELETE FROM departments')) {
        return { rowCount: 1, rows: [] };
      }
      if (text.startsWith('INSERT INTO audit_logs')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const result = await deleteMistakenDepartment(db, {
    actorId: IDS.actor,
    departmentId: IDS.department,
    reason: 'Created with the wrong office name',
  });

  assert.equal(result.department.id, IDS.department);
  assert.equal(
    calls.some(({ text }) => text.startsWith('DELETE FROM departments')),
    true
  );
  const audit = calls.find(({ text }) => text.startsWith('INSERT INTO audit_logs'));
  assert.ok(audit);
  assert.equal(audit.params[0], IDS.actor);
  assert.equal(audit.params[1], IDS.department);
  assert.deepEqual(JSON.parse(audit.params[2]), {
    reason: 'Created with the wrong office name',
    before: departmentRow(),
  });
});

test('used department is rejected with named dependency blockers', async () => {
  const calls = [];
  const db = {
    async query(sql) {
      const text = String(sql).trim();
      calls.push(text);
      if (text.includes('FROM departments') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [departmentRow()] };
      }
      if (text.startsWith('SELECT (SELECT COUNT')) {
        return {
          rowCount: 1,
          rows: [emptyDependencyRow({
            dependency_positions: 2,
            dependency_assignments: 4,
          })],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  await assert.rejects(
    deleteMistakenDepartment(db, {
      actorId: IDS.actor,
      departmentId: IDS.department,
      reason: 'Mistaken department',
    }),
    (error) => {
      assert.ok(error instanceof DepartmentLifecycleError);
      assert.equal(error.statusCode, 409);
      assert.deepEqual(error.blockers, [
        { key: 'positions', label: 'positions', count: 2 },
        { key: 'assignments', label: 'employee assignments', count: 4 },
      ]);
      assert.match(error.message, /2 positions/);
      assert.match(error.message, /4 employee assignments/);
      return true;
    }
  );
  assert.equal(calls.some((text) => text.startsWith('DELETE FROM departments')), false);
});

test('department delete route rolls back and returns blockers for a used department', async () => {
  const calls = [];
  let released = false;
  const client = {
    async query(sql) {
      const text = String(sql).trim();
      calls.push(text);
      if (text === 'BEGIN' || text === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (text.includes('FROM departments') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [departmentRow()] };
      }
      if (text.startsWith('SELECT (SELECT COUNT')) {
        return {
          rowCount: 1,
          rows: [emptyDependencyRow({ dependency_leave_requests: 1 })],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
    release() {
      released = true;
    },
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async connect() {
        return client;
      },
      async query() {
        throw new Error('pool.query must not be used inside delete transaction');
      },
    },
  });
  const routePath = '../src/routes/departments';
  clearModule(routePath);
  try {
    const router = require(routePath);
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.delete
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      params: { id: IDS.department },
      body: { reason: 'Mistaken department' },
      user: { id: IDS.actor, role: 'admin' },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 409);
    assert.deepEqual(res.body.blockers, [
      { key: 'leave_requests', label: 'leave requests', count: 1 },
    ]);
    assert.deepEqual(calls.slice(0, 2), ['BEGIN', calls[1]]);
    assert.equal(calls.at(-1), 'ROLLBACK');
    assert.equal(calls.includes('COMMIT'), false);
    assert.equal(released, true);
  } finally {
    clearModule(routePath);
    restoreDb();
  }
});
