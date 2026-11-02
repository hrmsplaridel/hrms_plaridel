const test = require('node:test');
const assert = require('node:assert/strict');
const createControllers = require('../src/modules/leave/controllers/administration.controller');
const { applyYearEndForcedLeaveDeductions } = require('../src/services/leaveYearEndForcedLeave');

const A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const C = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const ids = count => Array.from({ length: count }, (_, i) =>
  `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`);

function controllerFixture() {
  const calls = [];
  const controllers = createControllers({
    pool: {},
    yearEndManilaYearNow: () => 2026,
    applyYearEndForcedLeaveDeductions: async (_pool, options) => {
      calls.push({ type: 'apply', options });
      return { summary: { applied: 1 } };
    },
    broadcastAppEvent: (...args) => calls.push({ type: 'broadcast', args }),
  });
  return {
    calls,
    async invoke(body, query = {}) {
      const response = {
        code: 200,
        status(code) { this.code = code; return this; },
        json(body) { this.body = body; return this; },
      };
      await controllers.applyYearEndForcedLeave({
        body: { year: 2025, ...body }, query, user: { id: 'admin' },
      }, response);
      return response;
    },
  };
}

const invalidSelections = [
  A, null, undefined, '', true, 1, {}, { 0: A }, [], [''], ['   '],
  ['not-a-uuid'], [null], [1], [{}], [[A]], [A, ''], [A, null], [A, 'invalid'],
  new Array(1), ids(101),
];

for (const dryRun of [true, false]) {
  for (const field of ['employee_ids', 'employeeIds']) {
    for (const [index, value] of invalidSelections.entries()) {
      test(`year-end ${dryRun ? 'preview' : 'apply'} rejects ${field} case ${index}`, async () => {
        const f = controllerFixture();
        const result = await f.invoke({ dry_run: dryRun, [field]: value });
        assert.equal(result.code, 400);
        assert.match(result.body.error, /employee_ids/i);
        assert.deepEqual(f.calls, [], 'Invalid selection must not reach apply or broadcast');
      });
    }
  }

  for (const body of [
    { employee_ids: [A], employeeIds: [B] },
    { employee_ids: null, employeeIds: [A] },
    { employee_ids: [A], employeeIds: null },
    { employee_ids: [A], employeeIds: 'invalid' },
  ]) {
    test(`year-end ${dryRun ? 'preview' : 'apply'} rejects invalid/conflicting aliases ${JSON.stringify(body)}`, async () => {
      const f = controllerFixture();
      const result = await f.invoke({ dry_run: dryRun, ...body });
      assert.equal(result.code, 400);
      assert.match(result.body.error, /employee_ids/i);
      assert.deepEqual(f.calls, []);
    });
  }

  for (const [body, expected] of [
    [{}, null], // Existing Flutter Apply All deliberately omits the employee list.
    [{ employee_ids: [A] }, [A]],
    [{ employeeIds: [B] }, [B]],
    [{ employee_ids: [` ${A.toUpperCase()} `, A, B] }, [A, B]],
    [{ employee_ids: [A, B], employeeIds: [B, A, A] }, [A, B]],
    [{ employee_ids: ids(100) }, ids(100)],
  ]) {
    test(`year-end ${dryRun ? 'preview' : 'apply'} preserves valid selection ${JSON.stringify(body)}`, async () => {
      const f = controllerFixture();
      const result = await f.invoke({ dry_run: dryRun, ...body });
      assert.equal(result.code, dryRun ? 200 : 201);
      assert.deepEqual(f.calls.find(c => c.type === 'apply').options.employeeIds, expected);
      assert.equal(f.calls.find(c => c.type === 'apply').options.dryRun, dryRun);
      assert.equal(f.calls.filter(c => c.type === 'broadcast').length, dryRun ? 0 : 1);
    });
  }
}

for (const field of ['employee_ids', 'employeeIds']) {
  test(`query-only ${field} is rejected instead of being silently treated as all employees`, async () => {
    const f = controllerFixture();
    const result = await f.invoke({ dry_run: false }, { [field]: A });
    assert.equal(result.code, 400);
    assert.match(result.body.error, /employee_ids.*body/i);
    assert.deepEqual(f.calls, []);
  });
}

for (const dryRun of [true, false]) {
  for (const [index, value] of invalidSelections.entries()) {
    if (value == null) continue; // Internal null/omission intentionally means all.
    test(`year-end service rejects malformed selection ${index} before SQL, dryRun=${dryRun}`, async () => {
      const calls = [];
      const pool = {
        query: async (...args) => { calls.push(args); return { rows: [] }; },
        connect: async () => { calls.push('connect'); throw Error('Unexpected connection'); },
      };
      await assert.rejects(
        applyYearEndForcedLeaveDeductions(pool, { year: 2025, dryRun, employeeIds: value }),
        err => err.statusCode === 400 && /employee_ids/i.test(err.message),
      );
      assert.deepEqual(calls, []);
    });
  }
}

function employee(user_id, extra = {}) {
  return { user_id, vl_accumulated: 30, vl_available: 30, qualifying_requests: [], ...extra };
}

test('service previews only selected UUIDs and excludes other eligible/skipped employees', async () => {
  const pool = { query: async () => ({ rows: [employee(A), employee(B), employee(C, { deduction_ledger_id: 'ledger' })] }) };
  const result = await applyYearEndForcedLeaveDeductions(pool, {
    year: 2025, dryRun: true, employeeIds: [` ${A.toUpperCase()} `, A],
  });
  assert.deepEqual(result.results.map(r => r.user_id), [A]);
  assert.equal(result.summary.would_apply, 1);
  assert.equal(result.summary.already_deducted, 0);
});

for (const options of [{}, { employeeIds: null }]) {
  test(`service preserves intentional all-employee processing ${JSON.stringify(options)}`, async () => {
    const pool = { query: async () => ({ rows: [employee(A), employee(B)] }) };
    const result = await applyYearEndForcedLeaveDeductions(pool, { year: 2025, dryRun: true, ...options });
    assert.deepEqual(result.results.map(r => r.user_id), [A, B]);
    assert.equal(result.summary.would_apply, 2);
  });
}

test('live service writes deductions only for the selected employee', async () => {
  const queries = [];
  const client = {
    release() {},
    async query(sql, params) {
      queries.push({ sql, params });
      if (sql.includes('FROM users u')) return { rows: [employee(A)] };
      if (sql.includes('SELECT earned_days, used_days')) {
        return { rows: [{ earned_days: 30, used_days: 0, pending_days: 0, adjusted_days: 0 }] };
      }
      return { rows: [] };
    },
  };
  const pool = {
    query: async () => ({ rows: [employee(A), employee(B)] }),
    connect: async () => client,
  };
  const result = await applyYearEndForcedLeaveDeductions(pool, {
    year: 2025, dryRun: false, employeeIds: [A], actorUserId: C,
  });
  assert.equal(result.summary.applied, 1);
  assert.deepEqual(result.results.map(r => r.user_id), [A]);
  const balanceWrites = queries.filter(q => q.sql.includes('INSERT INTO leave_balances'));
  assert.equal(balanceWrites.length, 1);
  assert.equal(balanceWrites[0].params[0], A);
  assert.equal(queries.some(q => q.sql === 'COMMIT'), true);
});
