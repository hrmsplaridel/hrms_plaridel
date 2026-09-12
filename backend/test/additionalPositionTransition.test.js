const test = require('node:test');
const assert = require('node:assert/strict');
const {
  AdditionalPositionTransitionError,
  createAdditionalPositionTransition,
  updateAdditionalPositionTransition,
} = require('../src/services/additionalPositionTransition');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const IDS = Object.freeze({
  employee: '11111111-1111-4111-8111-111111111111',
  department: '22222222-2222-4222-8222-222222222222',
  otherDepartment: '33333333-3333-4333-8333-333333333333',
  position: '44444444-4444-4444-8444-444444444444',
  otherPosition: '55555555-5555-4555-8555-555555555555',
  designation: '66666666-6666-4666-8666-666666666666',
  actor: '77777777-7777-4777-8777-777777777777',
});

function activeSelection(overrides = {}) {
  return {
    employee_exists: true,
    employee_is_active: true,
    employee_status: 'active',
    department_exists: true,
    department_is_active: true,
    position_exists: true,
    position_is_active: true,
    position_department_id: IDS.department,
    ...overrides,
  };
}

function createDb({ selection = activeSelection(), overlap = false } = {}) {
  const calls = [];
  return {
    calls,
    async query(sql, params = []) {
      const normalized = String(sql).trim();
      calls.push({ sql: normalized, params });
      if (normalized.startsWith('SELECT pg_advisory_xact_lock')) {
        return { rowCount: 1, rows: [{}] };
      }
      if (normalized.includes('(u.id IS NOT NULL) AS employee_exists')) {
        return { rowCount: 1, rows: [selection] };
      }
      if (normalized.startsWith('SELECT id') && normalized.includes('employee_other_positions')) {
        return overlap
          ? { rowCount: 1, rows: [{ id: IDS.designation }] }
          : { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('INSERT INTO employee_other_positions')) {
        return {
          rowCount: 1,
          rows: [{
            id: IDS.designation,
            employee_id: IDS.employee,
            department_id: params[1],
            position_id: params[2],
            effective_from: params[3],
            effective_to: params[4],
            is_active: params[5],
            remarks: params[6],
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${normalized}`);
    },
  };
}

test('additional position rejects a position from another department', async () => {
  const db = createDb({
    selection: activeSelection({ position_department_id: IDS.otherDepartment }),
  });

  await assert.rejects(
    createAdditionalPositionTransition(db, {
      employeeId: IDS.employee,
      departmentId: IDS.department,
      positionId: IDS.position,
      effectiveFrom: '2026-08-01',
      isActive: true,
    }),
    (error) => {
      assert.ok(error instanceof AdditionalPositionTransitionError);
      assert.equal(error.statusCode, 400);
      assert.match(error.message, /does not belong/i);
      return true;
    }
  );
  assert.equal(
    db.calls.some((call) => call.sql.startsWith('INSERT INTO employee_other_positions')),
    false
  );
});

test('active additional position rejects an inactive organizational reference', async () => {
  const db = createDb({ selection: activeSelection({ position_is_active: false }) });

  await assert.rejects(
    createAdditionalPositionTransition(db, {
      employeeId: IDS.employee,
      departmentId: IDS.department,
      positionId: IDS.position,
      effectiveFrom: '2026-08-01',
      isActive: true,
    }),
    (error) => {
      assert.equal(error.statusCode, 409);
      assert.match(error.message, /position is inactive/i);
      return true;
    }
  );
});

test('additional position rejects duplicate overlapping active coverage', async () => {
  const db = createDb({ overlap: true });

  await assert.rejects(
    createAdditionalPositionTransition(db, {
      employeeId: IDS.employee,
      departmentId: IDS.department,
      positionId: IDS.position,
      effectiveFrom: '2026-08-15',
      effectiveTo: '2026-09-15',
      isActive: true,
    }),
    (error) => {
      assert.equal(error.statusCode, 409);
      assert.match(error.message, /overlapping period/i);
      return true;
    }
  );
});

test('valid additional position is inserted after authoritative validation', async () => {
  const db = createDb();

  const result = await createAdditionalPositionTransition(db, {
    employeeId: IDS.employee,
    departmentId: IDS.department,
    positionId: IDS.otherPosition,
    effectiveFrom: '2026-09-01',
    effectiveTo: null,
    isActive: true,
    remarks: 'OIC designation',
    createdBy: IDS.actor,
  });

  assert.equal(result.id, IDS.designation);
  const overlapCall = db.calls.find(
    (call) => call.sql.startsWith('SELECT id') && call.sql.includes('employee_other_positions')
  );
  assert.equal(overlapCall.params[2], IDS.otherPosition);
  assert.equal(result.position_id, IDS.otherPosition);
});

test('additional position update excludes itself while checking overlaps', async () => {
  const calls = [];
  const db = {
    async query(sql, params = []) {
      const normalized = String(sql).trim();
      calls.push({ sql: normalized, params });
      if (normalized.includes('FROM employee_other_positions') && normalized.includes('FOR UPDATE')) {
        return {
          rowCount: 1,
          rows: [{
            id: IDS.designation,
            employee_id: IDS.employee,
            department_id: IDS.department,
            position_id: IDS.position,
            effective_from: '2026-08-01',
            effective_to: '2026-08-31',
            is_active: true,
            remarks: null,
          }],
        };
      }
      if (normalized.startsWith('SELECT pg_advisory_xact_lock')) {
        return { rowCount: 1, rows: [{}] };
      }
      if (normalized.includes('(u.id IS NOT NULL) AS employee_exists')) {
        return { rowCount: 1, rows: [activeSelection()] };
      }
      if (normalized.startsWith('SELECT id') && normalized.includes('employee_other_positions')) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('UPDATE employee_other_positions')) {
        return {
          rowCount: 1,
          rows: [{
            id: IDS.designation,
            employee_id: IDS.employee,
            department_id: IDS.department,
            position_id: IDS.position,
            effective_from: '2026-08-01',
            effective_to: '2026-09-30',
            is_active: true,
            remarks: null,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${normalized}`);
    },
  };

  const result = await updateAdditionalPositionTransition(db, {
    id: IDS.designation,
    changes: { effectiveTo: '2026-09-30' },
  });

  const overlapCall = calls.find(
    (call) => call.sql.startsWith('SELECT id') && !call.sql.includes('FOR UPDATE')
  );
  assert.equal(overlapCall.params[5], IDS.designation);
  assert.equal(result.after.effective_to, '2026-09-30');
});

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

async function runCreateRouteFailure({ selection, overlap = false }) {
  const transactionCalls = [];
  let released = false;
  const client = {
    async query(sql) {
      const normalized = String(sql).trim();
      transactionCalls.push(normalized);
      if (['BEGIN', 'ROLLBACK'].includes(normalized)) {
        return { rowCount: 0, rows: [] };
      }
      if (normalized.startsWith('SELECT pg_advisory_xact_lock')) {
        return { rowCount: 1, rows: [{}] };
      }
      if (normalized.includes('(u.id IS NOT NULL) AS employee_exists')) {
        return { rowCount: 1, rows: [selection] };
      }
      if (normalized.startsWith('SELECT id') && normalized.includes('employee_other_positions')) {
        return overlap
          ? { rowCount: 1, rows: [{ id: IDS.designation }] }
          : { rowCount: 0, rows: [] };
      }
      throw new Error(`Unexpected SQL: ${normalized}`);
    },
    release() {
      released = true;
    },
  };
  const pool = {
    async query() {
      return { rowCount: 0, rows: [] };
    },
    async connect() {
      return client;
    },
  };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = '../src/routes/employeeOtherPositions';
  clearModule(routePath);
  try {
    const router = require(routePath);
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/' && entry.route.methods.post
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const req = {
      user: { id: IDS.actor, role: 'admin' },
      body: {
        employee_id: IDS.employee,
        department_id: IDS.department,
        position_id: IDS.position,
        effective_from: '2026-08-15',
        effective_to: '2026-09-15',
        is_active: true,
      },
    };
    const res = responseRecorder();
    await handler(req, res);
    return { res, transactionCalls, released };
  } finally {
    clearModule(routePath);
    restoreDb();
  }
}

test('additional-position API returns 400 for a department-position mismatch', async () => {
  const result = await runCreateRouteFailure({
    selection: activeSelection({ position_department_id: IDS.otherDepartment }),
  });

  assert.equal(result.res.statusCode, 400);
  assert.match(result.res.body.error, /does not belong/i);
  assert.equal(result.transactionCalls[0], 'BEGIN');
  assert.equal(result.transactionCalls.at(-1), 'ROLLBACK');
  assert.equal(result.released, true);
});

test('additional-position API returns 409 for duplicate overlapping coverage', async () => {
  const result = await runCreateRouteFailure({
    selection: activeSelection(),
    overlap: true,
  });

  assert.equal(result.res.statusCode, 409);
  assert.match(result.res.body.error, /overlapping period/i);
  assert.equal(result.transactionCalls.at(-1), 'ROLLBACK');
  assert.equal(result.released, true);
});
