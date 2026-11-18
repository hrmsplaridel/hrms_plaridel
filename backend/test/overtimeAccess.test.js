const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const actor = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const requestId = '33333333-3333-4333-8333-333333333333';

async function invoke({ method = 'get', role = 'employee', query = {}, owner = other, status = 'pending', missing = false, decision = 'approved' } = {}) {
  const calls = [], notified = [];
  const rows = [actor, other].map(employee_id => ({
    id: requestId, employee_id, employee_name: employee_id,
    status, total_hours: '2', reason: 'Private reason', review_notes: 'Private review notes',
  }));
  let stored = missing ? null : { ...rows.find(row => row.employee_id === owner) };
  const restores = [
    withMockedModule('../src/config/db', { pool: {
      async query(sql, params = []) {
        calls.push({ sql, params });
        if (sql.includes('FROM overtime_requests o')) {
          const employeeFilter = sql.match(/o\.employee_id\s*=\s*\$(\d+)/);
          return { rows: employeeFilter ? rows.filter(row => row.employee_id === params[Number(employeeFilter[1]) - 1]) : rows };
        }
        if (sql.includes('UPDATE overtime_requests')) {
          const ownerExclusion = sql.match(/employee_id\s*(?:<>|!=)\s*\$(\d+)/);
          if (!stored || stored.status !== 'pending' ||
              (ownerExclusion && stored.employee_id === params[Number(ownerExclusion[1]) - 1])) {
            return { rows: [], rowCount: 0 };
          }
          stored = { ...stored, status: params[0], approved_by: params[1] };
          return { rows: [stored], rowCount: 1 };
        }
        throw new Error(`Unexpected query: ${sql}`);
      },
    } }),
    withMockedModule('../src/services/overtimeNotifications', {
      notifyOvertimeReviewed: async (_db, data) => { notified.push(data); },
    }),
  ];
  clearModule('../src/routes/overtime');
  try {
    const path = method === 'get' ? '/' : '/:id/review';
    const route = require('../src/routes/overtime').stack.find(l => l.route?.path === path && l.route.methods[method]).route;
    const req = { user: { id: actor, role }, query, params: { id: requestId }, body: { status: decision } };
    const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
    async function dispatch(index) {
      if (index >= route.stack.length) return;
      let next;
      await route.stack[index].handle(req, res, () => { next = dispatch(index + 1); return next; });
      if (next) await next;
    }
    await dispatch(1); // Exercise the role guard and handler with an authenticated user.
    return { res, calls, notified, stored };
  } finally {
    clearModule('../src/routes/overtime');
    restores.reverse().forEach(restore => restore());
  }
}

for (const query of [{}, { status: 'pending' }, { employee_id: actor }]) {
  test(`employee overtime list is scoped to the authenticated employee: ${JSON.stringify(query)}`, async () => {
    const { res } = await invoke({ query });
    assert.equal(res.code, 200);
    assert.deepEqual(res.body.map(row => row.employee_id), [actor]);
  });
}

test('employee cannot select another employee overtime records', async () => {
  const { res, calls } = await invoke({ query: { employee_id: other } });
  assert.equal(res.code, 403);
  assert.deepEqual(calls, []);
});

test('malformed overtime employee filters cannot bypass ownership', async () => {
  for (const employee_id of [[actor, other], { id: other }]) {
    const { res, calls } = await invoke({ query: { employee_id } });
    assert.equal(res.code, 400);
    assert.deepEqual(calls, []);
  }
});

for (const role of ['admin', 'hr', 'supervisor']) {
  test(`${role} retains overtime management list and employee filter`, async () => {
    const all = await invoke({ role });
    assert.equal(all.res.code, 200);
    assert.equal(all.res.body.length, 2);
    const filtered = await invoke({ role, query: { employee_id: other } });
    assert.equal(filtered.res.code, 200);
    assert.deepEqual(filtered.res.body.map(row => row.employee_id), [other]);
  });

  for (const decision of ['approved', 'rejected']) {
    const action = decision === 'approved' ? 'approve' : 'reject';
    test(`${role} cannot ${action} their own overtime or notify an outcome`, async () => {
      const { res, stored, notified } = await invoke({ method: 'patch', role, owner: actor, decision });
      assert.equal(res.code, 404);
      assert.equal(stored.status, 'pending');
      assert.deepEqual(notified, []);
    });

    test(`${role} can ${action} another employee overtime`, async () => {
      const { res, stored, notified } = await invoke({ method: 'patch', role, decision });
      assert.equal(res.code, 200);
      assert.equal(stored.status, decision);
      assert.equal(stored.approved_by, actor);
      assert.equal(notified.length, 1);
      assert.equal(notified[0].employeeUserId, other);
    });
  }
}

test('ordinary employees cannot review another employee overtime', async () => {
  const { res, calls } = await invoke({ method: 'patch' });
  assert.equal(res.code, 403);
  assert.deepEqual(calls, []);
});

test('missing or previously reviewed overtime cannot be reviewed again', async () => {
  for (const scenario of [{ missing: true }, { status: 'approved' }, { status: 'rejected' }]) {
    const { res, notified } = await invoke({ method: 'patch', role: 'admin', ...scenario });
    assert.equal(res.code, 404);
    assert.deepEqual(notified, []);
  }
});
