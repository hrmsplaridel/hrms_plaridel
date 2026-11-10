const test = require('node:test');
const assert = require('node:assert/strict');
const { rebuildCoverageAttendance } = require('../src/services/coverageAttendanceRebuild');

test('coverage removal rebuilds only affected employees from retained raw punches', async () => {
  const calls = [];
  const result = await rebuildCoverageAttendance({ employeeId: 'employee', dateFrom: '2026-09-01', dateTo: '2026-09-02' }, {
    pool: { query: async (sql, args) => {
      assert.match(sql, /biometric_attendance_logs/);
      assert.equal(args[0], 'employee');
      return { rows: [{ user_id: 'employee', punch_date: '2026-09-01' }] };
    } }, process: async (...args) => { calls.push(args); return { inserted: 1, updated: 0 }; },
  });
  assert.deepEqual(calls, [[['employee'], '2026-09-01', '2026-09-02']]);
  assert.equal(result.rebuilt, 1);
});

test('recurring holiday removal rebuilds actual affected years rather than only template year', async () => {
  const calls = [];
  await rebuildCoverageAttendance({ dateFrom: '2020-12-31', dateTo: '2021-01-01', recurring: true }, {
    pool: { query: async (sql) => {
      assert.match(sql, /MM-DD/);
      return { rows: [{ user_id: 'employee', punch_date: '2025-12-31' }, { user_id: 'employee', punch_date: '2026-01-01' }] };
    } }, process: async (...args) => calls.push(args),
  });
  assert.deepEqual(calls.map((c) => c.slice(1)), [['2025-12-31', '2025-12-31'], ['2026-01-01', '2026-01-01']]);
});

test('coverage rebuild with no raw punches performs no processing', async () => {
  const result = await rebuildCoverageAttendance({ dateFrom: '2026-09-01', dateTo: '2026-09-01' }, {
    pool: { query: async () => ({ rows: [] }) }, process: async () => assert.fail('No punches'),
  });
  assert.equal(result.rebuilt, 0);
});

test('invalid rebuild scope fails before accessing the database', async () => {
  await assert.rejects(() => rebuildCoverageAttendance({ dateFrom: 'invalid', dateTo: '2026-09-01' }, {
    pool: { query: async () => assert.fail('Invalid range must not query') },
  }), /date/i);
});

test('paper leave revocation restores retained punches only after releasing its committed transaction', async () => {
  const { withMockedModule } = require('./helpers/moduleMocks');
  const row = { id: 'leave', paper_approval_record: { source: 'approved_paper' } };
  const scope = { employeeId: 'employee', dateFrom: '2026-09-01', dateTo: '2026-09-02' };
  const restore = withMockedModule('../src/modules/leave/use-cases/revokePaperApproval', async () => scope);
  let committed = false, released = false, rebuilt = false;
  const client = { query: async (sql) => {
    if (sql === 'COMMIT') committed = true;
    return { rows: [row] };
  }, release() { released = true; } };
  try {
    const controller = require('../src/modules/leave/controllers/revoke.controller')({
      pool: { connect: async () => client, query: async () => ({ rows: [row] }) },
      rebuildCoverageAttendance: async (actual) => {
        assert.ok(committed); assert.ok(released); assert.deepEqual(actual, scope); rebuilt = true;
      }, mapLeaveRowToApi: (value) => value, notifySafe: () => {},
      broadcastDtrLeaveRefresh: () => {}, broadcastLeaveUpdated: () => {},
    }).revokeLeave;
    const res = { status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
    await controller({ user: { id: 'hr' }, params: { id: 'leave' }, body: {} }, res);
    assert.equal(rebuilt, true);
    assert.equal(res.body.id, 'leave');
  } finally { restore(); }
});
