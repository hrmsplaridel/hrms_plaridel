const test = require('node:test');
const assert = require('node:assert/strict');
const { createRouter: createBackendRouter } = require('../src/routes/dtrCorrections');
const createRouter = options => createBackendRouter({
  notifications: { submitted: async () => {}, reviewed: async () => {} },
  reviewers: async () => [{ id: reviewer }],
  featureAccess: async () => ({ corrections_allowed: true, approvals_allowed: true }), ...options,
});
const employee = '11111111-1111-4111-8111-111111111111';
const reviewer = '22222222-2222-4222-8222-222222222222';
const id = '33333333-3333-4333-8333-333333333333';

async function invoke(router, method, path, req) {
  req.headers ??= {};
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
  const notices = [];
  const row = { id, employee_id: own ? reviewer : employee, attendance_date: '2026-09-30', status, original_record: null };
  const client = { release() {}, async query(sql, args) {
    queries.push({ sql, args });
    if (sql.includes('FROM dtr_corrections WHERE id=')) return { rows: [row] };
    if (sql.includes('FROM dtr_daily_summary')) return { rows: stale ? [{ id: 'changed' }] : [] };
    return { rows: [], rowCount: 1 };
  } };
  const router = createRouter({ db: { connect: async () => client },
    apply: async () => { applied++; return applyError ? { error: 'Invalid punches' } : {}; },
    enqueue: async () => { queued++; }, broadcast() {},
    notifications: { reviewed: async (_, request, decision) => {
      assert.equal(queries.at(-1).sql, 'COMMIT');
      notices.push({ request, decision });
    } } });
  return { router, queries, notices, counts: () => ({ applied, queued }) };
}
const reviewRequest = (role = 'hr') => ({ user: { id: reviewer, role }, params: { id }, body: { decision: 'approved', notes: 'Verified against supervisor report.' } });

test('submission refuses no eligible reviewer or only the requester', async () => {
  for (const assigned of [[], [{ id: employee }]]) {
    const router = createRouter({
      reviewers: async () => assigned,
      shiftFor: async () => ({ startMinutes: 480, endMinutes: 1020 }),
      db: { connect: async () => { throw new Error('must not insert a request'); } },
    });
    const res = await invoke(router, 'post', '/', {
      user: { id: employee, role: 'employee' },
      body: { attendance_date: '2026-09-30', reason: 'Missing biometric punch.',
        requested_time_in: '2026-09-30T08:00:00+08:00' },
    });
    assert.equal(res.code, 409);
    assert.match(res.body.error, /No other active DTR correction reviewer/);
  }
});

test('reviewer options use the same current corrections access rule', async () => {
  const router = createRouter({ db: { query: async sql => {
    if (sql.includes('FROM users')) {
      assert.match(sql, /u.role = 'hr' OR EXISTS/);
      assert.match(sql, /a.admin_user_id = u.id AND a.corrections_allowed = true/);
      return { rows: [{ id: reviewer, name: 'Eligible reviewer' }] };
    }
    return { rows: [] };
  } } });
  const res = await invoke(router, 'get', '/reviewers', {
    user: { id: reviewer, role: 'admin' }, query: {},
  });
  assert.equal(res.code, 200);
  assert.deepEqual(res.body.eligible, [{ id: reviewer, name: 'Eligible reviewer' }]);
});

test('employees cannot access the review list', async () => {
  const router = createRouter({ db: { query: async () => { throw new Error('must not query'); } } });
  const res = await invoke(router, 'get', '/', { user: { id: employee, role: 'employee' }, query: { review: 'true' } });
  assert.equal(res.code, 403);
});
test('unassigned HR cannot view or decide correction requests', async () => {
  let detailAccess;
  const client = { release() {}, query: async () => ({ rows: [] }) };
  const router = createRouter({ reviewers: async () => [], db: {
    query: async (sql, values) => {
      if (sql.includes('FROM dtr_corrections c')) detailAccess = values;
      return { rows: [] };
    }, connect: async () => client,
  } });
  const list = await invoke(router, 'get', '/', { user: { id: reviewer, role: 'hr' }, query: { review: 'true' } });
  assert.equal(list.code, 403);
  const detail = await invoke(router, 'get', '/:id', { user: { id: reviewer, role: 'hr' }, params: { id } });
  assert.equal(detail.code, 404);
  assert.deepEqual(detailAccess, [id, reviewer, false]);
  const review = await invoke(router, 'post', '/:id/review', reviewRequest());
  assert.equal(review.code, 403);
});
test('only admins can configure two or more eligible reviewers', async () => {
  const queries = [];
  let eligibleCount = 2;
  const client = { release() {}, async query(sql, args) {
    queries.push(sql);
    if (sql.includes('FROM users WHERE id = ANY')) return { rows: args[0].map(id => ({ id })) };
    if (sql.includes('count(*)')) {
      assert.match(sql, /u.role = 'hr' OR EXISTS/);
      assert.match(sql, /a.admin_user_id = u.id AND a.corrections_allowed = true/);
      return { rows: [{ total: eligibleCount }] };
    }
    return { rows: [] };
  } };
  const router = createRouter({ db: { connect: async () => client } });
  const body = { effective_from: '2099-01-01', reviewer_ids: [reviewer, employee] };
  const denied = await invoke(router, 'put', '/reviewers', { user: { id: reviewer, role: 'hr' }, body });
  assert.equal(denied.code, 403);
  const missingBackup = await invoke(router, 'put', '/reviewers', {
    user: { id: reviewer, role: 'admin' }, body: { ...body, reviewer_ids: [reviewer] },
  });
  assert.equal(missingBackup.code, 409);
  eligibleCount = 1;
  const single = await invoke(router, 'put', '/reviewers', {
    user: { id: reviewer, role: 'admin' }, body: { ...body, reviewer_ids: [reviewer] },
  });
  assert.equal(single.code, 200);
  const saved = await invoke(router, 'put', '/reviewers', { user: { id: reviewer, role: 'admin' }, body });
  assert.equal(saved.code, 200);
  assert.ok(queries.some(sql => sql.includes('INSERT INTO dtr_correction_reviewer_configs')));
  assert.equal(queries.at(-1), 'COMMIT');
});
test('an admin without DTR Corrections access cannot be assigned as reviewer', async () => {
  const client = { release() {}, async query(sql, values) {
    if (sql.includes('FROM users WHERE id = ANY')) return { rows: values[0].map(id => ({ id })) };
    if (sql.includes('LEFT JOIN dtr_admin_access')) return { rows: [{ id: reviewer }] };
    return { rows: [] };
  } };
  const router = createRouter({ db: { connect: async () => client } });
  const result = await invoke(router, 'put', '/reviewers', {
    user: { id: reviewer, role: 'admin' },
    body: { effective_from: '2099-01-01', reviewer_ids: [reviewer, employee] },
  });
  assert.equal(result.code, 409);
  assert.match(result.body.error, /Enable DTR Corrections access/);
});
test('employee history is scoped to authenticated employee', async () => {
  let args;
  const router = createRouter({ db: { query: async (_, values) => { args = values; return { rows: [] }; } } });
  await invoke(router, 'get', '/', { user: { id: employee, role: 'employee' }, query: { employee_id: reviewer } });
  assert.deepEqual(args, [false, employee, 0]);
});

test('review queue filters status and employee search at the database', async () => {
  let sql;
  let args;
  const router = createRouter({ db: { query: async (query, values) => {
    sql = query; args = values; return { rows: [] };
  } } });
  const result = await invoke(router, 'get', '/', { user: { id: reviewer, role: 'hr' },
    query: { review: 'true', status: 'approved', search: 'Earl_%', offset: '50' } });
  assert.equal(result.code, 200);
  assert.match(sql, /c.status = \$4/);
  assert.match(sql, /u.full_name ILIKE \$5/);
  assert.deepEqual(args, [true, reviewer, 50, 'approved', '%Earl\\_\\%%']);
});

test('review queue rejects invalid status filters', async () => {
  const router = createRouter({ db: { query: async () => { throw new Error('must not query'); } } });
  const result = await invoke(router, 'get', '/', { user: { id: reviewer, role: 'hr' },
    query: { review: 'true', status: 'other' } });
  assert.equal(result.code, 400);
});

test('original attendance preview only reads the authenticated employee', async () => {
  let args;
  let shiftArgs;
  const router = createRouter({
    db: { query: async (_, values) => { args = values; return { rows: [] }; } },
    shiftFor: async (...values) => { shiftArgs = values; return { punchMode: 'single_session', startMinutes: 1320, endMinutes: 420 }; },
  });
  const result = await invoke(router, 'get', '/original/:date', {
    user: { id: employee, role: 'admin' }, params: { date: '2026-10-02' }, query: { employee_id: reviewer },
  });
  assert.equal(result.code, 200);
  assert.deepEqual(result.body, { shift_punch_mode: 'single_session', shift_crosses_midnight: true });
  assert.deepEqual(args, [employee, '2026-10-02']);
  assert.deepEqual(shiftArgs, [employee, '2026-10-02']);
});

test('original attendance preview resolves split shifts and missing assignments', async () => {
  const db = { query: async () => ({ rows: [{ time_in: '2026-10-02T00:00:00Z' }] }) };
  const request = { user: { id: employee }, params: { date: '2026-10-02' } };
  const split = createRouter({ db, shiftFor: async () => ({ punchMode: 'full_day', startMinutes: 480, endMinutes: 1020 }) });
  const absent = createRouter({ db, shiftFor: async () => null });
  assert.equal((await invoke(split, 'get', '/original/:date', request)).body.shift_punch_mode, 'full_day');
  assert.equal((await invoke(split, 'get', '/original/:date', request)).body.shift_crosses_midnight, false);
  assert.equal((await invoke(absent, 'get', '/original/:date', request)).body.shift_punch_mode, null);
  assert.equal((await invoke(absent, 'get', '/original/:date', request)).body.shift_crosses_midnight, false);
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
    assert.equal(f.notices.length, 0);
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
  assert.equal(f.notices[0].decision, 'approved');
  assert.ok(f.queries.some(q => q.sql.includes('applied_record=$5')));
  assert.equal(f.queries.at(-1).sql, 'COMMIT');
});
test('rejection retains original attendance', async () => {
  const f = fixture();
  const req = reviewRequest(); req.body.decision = 'rejected';
  assert.equal((await invoke(f.router, 'post', '/:id/review', req)).code, 200);
  assert.deepEqual(f.counts(), { applied: 0, queued: 0 });
  assert.equal(f.notices[0].decision, 'rejected');
});
test('submission ignores a supplied employee ID and preserves original data', async () => {
  let insert;
  let released = false;
  let notified = false;
  const client = { release() { released = true; }, query: async (sql, args) => {
    if (sql.includes('INSERT INTO dtr_corrections')) { insert = args; return { rows: [{ id }] }; }
    return { rows: [] };
  } };
  const router = createRouter({ db: { connect: async () => client },
    notifications: { submitted: async (_, row) => {
      assert.equal(released, true);
      assert.equal(row.employee_id, employee);
      assert.equal(row.attendance_date, '2020-09-30');
      notified = true;
    } },
    shiftFor: async () => ({ startMinutes: 1320, endMinutes: 420, punchMode: 'single_session', captureWindowMinutes: 120 }) });
  const req = { user: { id: employee }, body: { employee_id: reviewer, attendance_date: '2020-09-30',
    reason: 'Biometric device was unavailable.', requested_time_in: '2020-09-30T22:00:00+08:00', requested_time_out: '2020-10-01T07:00:00+08:00' } };
  assert.equal((await invoke(router, 'post', '/', req)).code, 201);
  assert.equal(insert[0], employee);
  assert.equal(insert[7], 'null');
  assert.equal(notified, true);
});

test('notification detail endpoint scopes employee access and denies missing requests', async () => {
  let args;
  const router = createRouter({ db: { query: async (_, values) => { args = values; return { rows: [] }; } } });
  const result = await invoke(router, 'get', '/:id', { user: { id: employee, role: 'employee' }, params: { id } });
  assert.equal(result.code, 404);
  assert.deepEqual(args, [id, employee, false]);
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

test('attachment download is scoped to owner or HR and refuses unauthorized access', async () => {
  let args;
  const router = createRouter({ db: { query: async (sql, values) => {
    assert.match(sql, /c.employee_id=\$2 OR \$3::boolean/);
    args = values; return { rows: [] };
  } } });
  const result = await invoke(router, 'get', '/:id/attachment', { user: { id: employee, role: 'employee' }, params: { id } });
  assert.equal(result.code, 404);
  assert.deepEqual(args, [id, employee, false]);
});

test('evidence is saved in the request transaction before commit', async () => {
  const queries = [];
  const client = { release() {}, query: async (sql, args) => {
    queries.push({ sql, args });
    return { rows: sql.includes('INSERT INTO dtr_corrections') ? [{ id }] : [] };
  } };
  const router = createRouter({ db: { connect: async () => client }, shiftFor: async () => ({ startMinutes: 480, endMinutes: 1020 }) });
  const res = await invoke(router, 'post', '/', { user: { id: employee },
    file: { originalname: 'proof.pdf', buffer: Buffer.from('%PDF-1.4\n') },
    body: { attendance_date: '2020-09-30', reason: 'Device was unavailable today.', requested_time_in: '2020-09-30T08:00:00+08:00' } });
  assert.equal(res.code, 201);
  const evidence = queries.findIndex(q => q.sql.includes('INSERT INTO dtr_correction_attachments'));
  assert.ok(evidence > 0);
  assert.equal(queries[evidence].args[0], id);
  assert.equal(queries[evidence + 1].sql, 'COMMIT');
});
