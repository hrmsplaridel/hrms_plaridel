'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const {
  DEPARTMENT_DEACTIVATION_DEPENDENCIES,
  DEPARTMENT_DEPENDENCIES,
  DepartmentLifecycleError,
  deleteMistakenDepartment,
  departmentAuditAction,
  departmentDeactivationCountsSql,
  departmentDependencyCountsSql,
  ensureDepartmentCanDeactivate,
  previewDepartmentDeactivation,
  writeDepartmentAudit,
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

function emptyDeactivationRow(overrides = {}) {
  return {
    ...Object.fromEntries(
      DEPARTMENT_DEACTIVATION_DEPENDENCIES.map(({ key }) => [
        `deactivation_${key}`,
        0,
      ])
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

test('department audit stores actor and before/after snapshots', async () => {
  let recorded;
  const db = {
    async query(sql, params) {
      recorded = { sql: String(sql), params };
      return { rowCount: 1, rows: [] };
    },
  };
  const before = departmentRow();
  const after = { ...before, name: 'Administrative Services' };

  await writeDepartmentAudit(db, {
    actorId: IDS.actor,
    action: 'department_updated',
    departmentId: IDS.department,
    before,
    after,
  });

  assert.match(recorded.sql, /INSERT INTO audit_logs/);
  assert.deepEqual(recorded.params.slice(0, 3), [
    IDS.actor,
    'department_updated',
    IDS.department,
  ]);
  assert.deepEqual(JSON.parse(recorded.params[3]), {
    reason: null,
    before,
    after,
  });
});

test('department audit distinguishes updates and status transitions', () => {
  assert.equal(
    departmentAuditAction({ is_active: true }, { is_active: true }),
    'department_updated'
  );
  assert.equal(
    departmentAuditAction({ is_active: true }, { is_active: false }),
    'department_deactivated'
  );
  assert.equal(
    departmentAuditAction({ is_active: false }, { is_active: true }),
    'department_reactivated'
  );
});

test('dependency projection covers every department foreign-key owner', () => {
  const sql = departmentDependencyCountsSql('d');
  for (const dependency of DEPARTMENT_DEPENDENCIES) {
    assert.match(sql, new RegExp(`FROM ${dependency.table}`));
    assert.match(sql, new RegExp(`${dependency.column} = d\\.id`));
  }
});

test('deactivation projection checks only operational department dependencies', () => {
  const sql = departmentDeactivationCountsSql('$1', '$2');
  assert.match(sql, /FROM assignments a/);
  assert.match(sql, /a\.effective_to IS NULL OR a\.effective_to >= \$2::date/);
  assert.doesNotMatch(sql, /a\.effective_from <= \$2::date/);
  assert.match(sql, /FROM positions p/);
  assert.match(sql, /FROM policy_assignments pa/);
  assert.match(sql, /pending_department_head/);
  assert.match(sql, /returned_for_correction/);
  assert.match(sql, /FROM docutracker_workflow_steps ws/);
  assert.match(sql, /FROM docutracker_escalation_configs dec/);
});

test('deactivation is rejected with current and future dependency blockers', async () => {
  const calls = [];
  const db = {
    async query(sql, params = []) {
      const text = String(sql).trim();
      calls.push({ text, params });
      if (text.includes('FROM departments') && text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [departmentRow()] };
      }
      if (text.includes('AS deactivation_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [
            emptyDeactivationRow({
              deactivation_primary_assignments: 3,
              deactivation_pending_leave_requests: 2,
            }),
          ],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  await assert.rejects(
    ensureDepartmentCanDeactivate(db, {
      departmentId: IDS.department,
      officialDate: '2026-08-30',
    }),
    (error) => {
      assert.ok(error instanceof DepartmentLifecycleError);
      assert.equal(error.statusCode, 409);
      assert.deepEqual(error.blockers, [
        {
          key: 'primary_assignments',
          label: 'current or future primary assignments',
          count: 3,
        },
        {
          key: 'pending_leave_requests',
          label: 'unresolved leave requests',
          count: 2,
        },
      ]);
      return true;
    }
  );
  assert.deepEqual(calls[1].params, [IDS.department, '2026-08-30']);
});

test('deactivation preview returns actionable blocker counts', async () => {
  const db = {
    async query(sql) {
      const text = String(sql).trim();
      if (text.includes('FROM departments') && !text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [departmentRow()] };
      }
      if (text.includes('AS deactivation_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [
            emptyDeactivationRow({
              deactivation_additional_positions: 1,
              deactivation_workflow_steps: 2,
            }),
          ],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const preview = await previewDepartmentDeactivation(db, {
    departmentId: IDS.department,
    officialDate: '2026-08-30',
  });

  assert.equal(preview.canDeactivate, false);
  assert.deepEqual(preview.blockers, [
    {
      key: 'additional_positions',
      label: 'current or future additional positions',
      count: 1,
    },
    {
      key: 'workflow_steps',
      label: 'enabled DocuTracker workflow steps',
      count: 2,
    },
  ]);
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
  assert.equal(audit.params[1], 'department_mistake_deleted');
  assert.equal(audit.params[2], IDS.department);
  assert.deepEqual(JSON.parse(audit.params[3]), {
    reason: 'Created with the wrong office name',
    before: departmentRow(),
    after: null,
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

test('department update route rolls back blocked deactivation', async () => {
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
      if (text.includes('AS deactivation_primary_assignments')) {
        return {
          rowCount: 1,
          rows: [
            emptyDeactivationRow({ deactivation_active_positions: 1 }),
          ],
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
        throw new Error('pool.query must not be used inside update transaction');
      },
    },
  });
  const routePath = '../src/routes/departments';
  clearModule(routePath);
  try {
    const router = require(routePath);
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.put
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      params: { id: IDS.department },
      body: { is_active: false },
      user: { id: IDS.actor, role: 'admin' },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 409);
    assert.deepEqual(res.body.blockers, [
      { key: 'active_positions', label: 'active positions', count: 1 },
    ]);
    assert.equal(calls[0], 'BEGIN');
    assert.equal(calls.at(-1), 'ROLLBACK');
    assert.equal(calls.some((text) => text.startsWith('UPDATE departments')), false);
    assert.equal(released, true);
  } finally {
    clearModule(routePath);
    restoreDb();
  }
});

test('department creation commits its audit event in the same transaction', async () => {
  const calls = [];
  let released = false;
  const client = {
    async query(sql, params = []) {
      const text = String(sql).trim();
      calls.push({ text, params });
      if (text === 'BEGIN' || text === 'COMMIT') {
        return { rowCount: 0, rows: [] };
      }
      if (text.startsWith('INSERT INTO departments')) {
        return { rowCount: 1, rows: [departmentRow()] };
      }
      if (text.startsWith('INSERT INTO audit_logs')) {
        return { rowCount: 1, rows: [] };
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
    },
  });
  const routePath = '../src/routes/departments';
  clearModule(routePath);
  try {
    const router = require(routePath);
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/' && entry.route.methods.post
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      body: { name: 'Administrative Services', description: 'Operations' },
      user: { id: IDS.actor, role: 'admin' },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 201);
    assert.equal(calls[0].text, 'BEGIN');
    assert.equal(calls.at(-1).text, 'COMMIT');
    const audit = calls.find(({ text }) => text.startsWith('INSERT INTO audit_logs'));
    assert.ok(audit);
    assert.deepEqual(audit.params.slice(0, 3), [
      IDS.actor,
      'department_created',
      IDS.department,
    ]);
    assert.equal(JSON.parse(audit.params[3]).before, null);
    assert.equal(released, true);
  } finally {
    clearModule(routePath);
    restoreDb();
  }
});

test('department creation rolls back when its audit event fails', async () => {
  const calls = [];
  let released = false;
  const client = {
    async query(sql) {
      const text = String(sql).trim();
      calls.push(text);
      if (text === 'BEGIN' || text === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (text.startsWith('INSERT INTO departments')) {
        return { rowCount: 1, rows: [departmentRow()] };
      }
      if (text.startsWith('INSERT INTO audit_logs')) {
        throw new Error('audit unavailable');
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
    },
  });
  const routePath = '../src/routes/departments';
  clearModule(routePath);
  const originalError = console.error;
  console.error = () => {};
  try {
    const router = require(routePath);
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/' && entry.route.methods.post
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      body: { name: 'Administrative Services' },
      user: { id: IDS.actor, role: 'admin' },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 500);
    assert.equal(calls.at(-1), 'ROLLBACK');
    assert.equal(calls.includes('COMMIT'), false);
    assert.equal(released, true);
  } finally {
    console.error = originalError;
    clearModule(routePath);
    restoreDb();
  }
});
