const test = require('node:test');
const assert = require('node:assert/strict');
const { createRouter } = require('../src/routes/dtrCorrections');
const employee = '11111111-1111-4111-8111-111111111111';
const reviewer = '22222222-2222-4222-8222-222222222222';
const id = '33333333-3333-4333-8333-333333333333';

async function invoke(router, method, path, req) {
  const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; } };
  const stack = router.stack.find(l => l.route?.path === path && l.route.methods[method]).route.stack;
  for (const layer of stack) {
    let next = false;
    await layer.handle(req, res, () => { next = true; });
    if (!next) break;
  }
  return res;
}
function fixture({ own = false, status = 'pending', stale = false, applyError = false } = {}) {
  const queries = [];
  let applied = 0;
  let queued = 0;
  const row = { id, employee_id: own ? reviewer : employee, attendance_date: '2026-09-30', status, original_record: null };
  const client = { release() {}, async query(sql, args) {
    queries.push({ sql, args });
    if (sql.includes('FROM dtr_corrections WHERE id=')) return { rows: [row] };
    if (sql.includes('FROM dtr_daily_summary')) return { rows: stale ? [{ id: 'changed' }] : [] };
    return { rows: [], rowCount: 1 };
  } };
  const router = createRouter({ db: { connect: async () => client },
    apply: async () => { applied++; return applyError ? { error: 'Invalid punches' } : {}; },
    enqueue: async () => { queued++; }, broadcast() {} });
  return { router, queries, counts: () => ({ applied, queued }) };
}
const reviewRequest = (role = 'hr') => ({ user: { id: reviewer, role }, params: { id }, body: { decision: 'approved', notes: 'Verified against supervisor report.' } });

test('employees cannot access the review list', async () => {
  const router = createRouter({ db: { query: async () => { throw new Error('must not query'); } } });
  const res = await invoke(router, 'get', '/', { user: { id: employee, role: 'employee' }, query: { review: 'true' } });
  assert.equal(res.code, 403);
});
test('employee history is scoped to authenticated employee', async () => {
  let args;
  const router = createRouter({ db: { query: async (_, values) => { args = values; return { rows: [] }; } } });
  await invoke(router, 'get', '/', { user: { id: employee, role: 'employee' }, query: { employee_id: reviewer } });
  assert.deepEqual(args, [false, employee, 0]);
});
for (const [name, options, code] of [
  ['self approval', { own: true }, 403], ['already reviewed', { status: 'approved' }, 409],
  ['stale attendance', { stale: true }, 409], ['failed validation', { applyError: true }, 400],
]) {
  test(`rejects ${name} and rolls back`, async () => {
    const f = fixture(options);
    const res = await invoke(f.router, 'post', '/:id/review', reviewRequest());
    assert.equal(res.code, code);
    assert.ok(f.queries.some(q => q.sql === 'ROLLBACK'));
    assert.ok(!f.queries.some(q => q.sql === 'COMMIT'));
    assert.equal(f.counts().queued, 0);
  });
}
test('employee role cannot approve requests', async () => {
  const f = fixture();
  assert.equal((await invoke(f.router, 'post', '/:id/review', reviewRequest('employee'))).code, 403);
  assert.equal(f.queries.length, 0);
});
test('approval commits audit and reconciliation together', async () => {
  const f = fixture();
  const res = await invoke(f.router, 'post', '/:id/review', reviewRequest());
  assert.equal(res.code, 200);
  assert.deepEqual(f.counts(), { applied: 1, queued: 1 });
  assert.ok(f.queries.some(q => q.sql.includes('applied_record=$5')));
  assert.equal(f.queries.at(-1).sql, 'COMMIT');
});
test('rejection retains original attendance', async () => {
  const f = fixture();
  const req = reviewRequest(); req.body.decision = 'rejected';
  assert.equal((await invoke(f.router, 'post', '/:id/review', req)).code, 200);
  assert.deepEqual(f.counts(), { applied: 0, queued: 0 });
});
test('submission ignores a supplied employee ID and preserves original data', async () => {
  let insert;
  const client = { release() {}, query: async (sql, args) => {
    if (sql.includes('INSERT INTO dtr_corrections')) { insert = args; return { rows: [{ id }] }; }
    return { rows: [] };
  } };
  const router = createRouter({ db: { connect: async () => client },
    shiftFor: async () => ({ startMinutes: 1320, endMinutes: 420, punchMode: 'single_session', captureWindowMinutes: 120 }) });
  const req = { user: { id: employee }, body: { employee_id: reviewer, attendance_date: '2020-09-30',
    reason: 'Biometric device was unavailable.', requested_time_in: '2020-09-30T22:00:00+08:00', requested_time_out: '2020-10-01T07:00:00+08:00' } };
  assert.equal((await invoke(router, 'post', '/', req)).code, 201);
  assert.equal(insert[0], employee);
  assert.equal(insert[7], 'null');
});
test('duplicate pending requests are blocked under a transaction lock', async () => {
  const sqls = [];
  const router = createRouter({ shiftFor: async () => ({}), db: { connect: async () => ({
    release() {}, query: async sql => { sqls.push(sql); return { rows: sql.includes('FROM dtr_corrections') ? [{ id }] : [] }; },
  }) } });
  const res = await invoke(router, 'post', '/', { user: { id: employee }, body: { attendance_date: '2020-09-30',
    requested_time_in: '2020-09-30T08:00:00+08:00', reason: 'Missing biometric time in.' } });
  assert.equal(res.code, 409);
  assert.ok(sqls.some(sql => sql.includes('pg_advisory_xact_lock')));
});
