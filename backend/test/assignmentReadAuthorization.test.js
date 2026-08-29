const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

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

function getHandler(router) {
  const layer = router.stack.find(
    (entry) => entry.route?.path === '/' && entry.route.methods.get
  );
  return layer.route.stack[layer.route.stack.length - 1].handle;
}

async function runDeniedEmployeeRead(routePath, query) {
  let queryCount = 0;
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query() {
        queryCount += 1;
        throw new Error('The database must not be queried for a denied request');
      },
    },
  });
  clearModule(routePath);
  try {
    const handler = getHandler(require(routePath));
    const req = {
      user: { id: '11111111-1111-4111-8111-111111111111', role: 'employee' },
      query,
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 403);
    assert.equal(queryCount, 0);
  } finally {
    clearModule(routePath);
    restoreDb();
  }
}

test('employee cannot read another employee policy assignments', async () => {
  await runDeniedEmployeeRead('../src/routes/policyAssignments', {
    employee_id: '22222222-2222-4222-8222-222222222222',
  });
});

test('employee cannot read another employee additional positions', async () => {
  await runDeniedEmployeeRead('../src/routes/employeeOtherPositions', {
    employee_id: '22222222-2222-4222-8222-222222222222',
  });
});

test('employee cannot search the additional-position employee directory', async () => {
  await runDeniedEmployeeRead('../src/routes/employeeOtherPositions', {
    position_title: 'Department Head',
  });
});

test('admin can read an inactive employee historical additional positions', async () => {
  const employeeId = '22222222-2222-4222-8222-222222222222';
  let executedSql = '';
  const pool = {
    async query(sql) {
      executedSql = String(sql);
      return {
        rows: [{
          id: '33333333-3333-4333-8333-333333333333',
          employee_id: employeeId,
          department_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          position_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          effective_from: '2026-01-01',
          effective_to: '2026-06-30',
          is_active: false,
          computed_status: 'Archived',
          employee_name: 'Maria Santos',
          department_name: 'Human Resources',
          position_name: 'Acting Department Head',
          access_department_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        }],
      };
    },
  };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = '../src/routes/employeeOtherPositions';
  clearModule(routePath);
  try {
    const handler = getHandler(require(routePath));
    const req = {
      user: { id: '11111111-1111-4111-8111-111111111111', role: 'admin' },
      query: { employee_id: employeeId, status: 'Archived' },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.length, 1);
    assert.equal(res.body[0].position_name, 'Acting Department Head');
    assert.equal(res.body[0].computed_status, 'Archived');
    assert.match(executedSql, /= 'Archived'/i);
    assert.doesNotMatch(executedSql, /u\.is_active/i);
  } finally {
    clearModule(routePath);
    restoreDb();
  }
});

test('supervisor cannot read a primary assignment outside their department', async () => {
  const targetId = '22222222-2222-4222-8222-222222222222';
  const supervisorId = '11111111-1111-4111-8111-111111111111';
  const pool = {
    async query(sql) {
      const normalized = String(sql);
      if (normalized.includes('LEFT JOIN departments')) {
        return {
          rows: [{
            id: '33333333-3333-4333-8333-333333333333',
            employee_id: targetId,
            department_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            effective_from: '2026-06-01',
            effective_to: null,
            is_active: true,
          }],
        };
      }
      if (normalized.includes('JOIN positions p')) {
        return {
          rows: [{
            employee_id: supervisorId,
            department_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            effective_from: '2026-01-01',
            effective_to: null,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${normalized}`);
    },
  };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = '../src/routes/assignments';
  clearModule(routePath);
  try {
    const handler = getHandler(require(routePath));
    const req = {
      user: { id: supervisorId, role: 'supervisor' },
      query: { employee_id: targetId, status: 'Active' },
    };
    const res = responseRecorder();

    await handler(req, res);

    assert.equal(res.statusCode, 403);
    assert.match(res.body.error, /supervised departments/i);
  } finally {
    clearModule(routePath);
    restoreDb();
  }
});
