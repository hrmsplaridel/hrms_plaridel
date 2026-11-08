const test = require('node:test');
const assert = require('node:assert/strict');
const { createAttendanceResetService } = require('../src/services/attendanceReset');

const employee = '10000000-0000-4000-8000-000000000001';
const actor = '10000000-0000-4000-8000-000000000002';
const rawId = '10000000-0000-4000-8000-000000000003';
const date = '2026-11-08';
const stamp = (time, day = date) => `${day}T${time}+08:00`;
const input = { employee_id: employee, attendance_date: date };
const shift = { startMinutes: 1140, endMinutes: 1200, punchMode: 'single_session', isWorkingDay: true };

function fixture(overrides = {}) {
  const state = {
    raw: [{ id: rawId, user_id: employee, logged_at: stamp('18:56:53'), biometric_user_id: '17' }],
    summaries: [{ id: rawId, employee_id: employee, attendance_date: date, shift_snapshot: shift,
      time_in: stamp('18:56:53'), total_hours: 0, source: 'system' }],
    blocks: [{ id: rawId, employee_id: employee, attendance_date: date, record_snapshot: { source: 'system' } }],
    coverage: [], processed: [], ...overrides,
  };
  const calls = [], broadcasts = [], audits = [], queue = [];
  let rollbackState;
  const query = async (sql, params = []) => {
    calls.push({ sql, params });
    if (sql.startsWith('BEGIN')) rollbackState = structuredClone(state);
    if (sql === 'ROLLBACK') Object.assign(state, rollbackState);
    if (sql.includes('FROM users')) return { rows: [{ id: employee, full_name: 'Test Employee', role: 'employee', biometric_user_id: '17' }] };
    if (sql.startsWith('SELECT') && sql.includes('FROM biometric_attendance_logs')) return { rows: structuredClone(state.raw) };
    if (sql.includes('FROM assignments a')) return { rows: [{ shift_snapshot: params[1] === date ? shift : null }] };
    if (sql.startsWith('SELECT') && sql.includes('FROM dtr_daily_summary_deletions')) return { rows: structuredClone(state.blocks) };
    if (sql.startsWith('SELECT') && sql.includes('FROM dtr_daily_summary')) return { rows: structuredClone(state.summaries) };
    if (sql.includes('FROM leave_requests') || sql.includes('FROM locator_slips')) return { rows: structuredClone(state.coverage) };
    if (sql.includes('FROM leave_attendance_deductions')) return { rows: structuredClone(state.processed) };
    if (sql.startsWith('DELETE FROM biometric_attendance_logs')) { const removed = state.raw.filter(r => params[1].includes(r.id)); state.raw = state.raw.filter(r => !params[1].includes(r.id)); return { rows: removed, rowCount: removed.length }; }
    if (sql.startsWith('DELETE FROM dtr_daily_summary')) { state.summaries = []; return { rowCount: 1, rows: [] }; }
    if (sql.startsWith('UPDATE dtr_daily_summary_deletions')) { state.blocks = []; return { rowCount: 1, rows: [] }; }
    if (sql.includes('INSERT INTO audit_logs')) { audits.push(JSON.parse(params.at(-1))); if (overrides.auditFailure) throw new Error('audit failed'); }
    return { rows: [], rowCount: 0 };
  };
  const service = createAttendanceResetService({
    db: { connect: async () => ({ query, release() {} }), query },
    now: () => new Date('2026-11-08T13:00:00Z'),
    broadcast: (...args) => broadcasts.push(args),
    enqueue: async (_db, args) => { queue.push(args); return { count: state.processed.length, months: state.processed.map(r => r.service_month) }; },
  });
  return { service, state, calls, broadcasts, audits, queue };
}

test('preview is read-only, employee/date scoped, and describes all affected records', async () => {
  const f = fixture();
  const preview = await f.service.preview(input, actor);
  assert.equal(preview.employee.id, employee);
  assert.equal(preview.attendance_date, date);
  assert.equal(preview.punches.length, 1);
  assert.equal(preview.summary.id, rawId);
  assert.equal(preview.deletion_blocks, 1);
  assert.equal(preview.can_reset, true);
  assert.ok(preview.preview_token);
  assert.equal(f.calls.some(c => /^(DELETE|UPDATE|INSERT)/.test(c.sql)), false);
});

test('apply requires explicit confirmation, a valid target, current preview, and a meaningful reason', async () => {
  for (const body of [input, { ...input, reason: 'x', confirmation: 'RESET' },
    { ...input, reason: 123, confirmation: 'RESET' },
    { ...input, reason: 'test reset', confirmation: true },
    { ...input, attendance_date: '2026-02-30', reason: 'test reset', confirmation: 'RESET' },
    { ...input, attendance_date: '2026-11-09', reason: 'test reset', confirmation: 'RESET' },
    { ...input, employee_id: 'invalid', reason: 'test reset', confirmation: 'RESET' }]) {
    const f = fixture();
    await assert.rejects(f.service.apply(body, actor), e => e.status === 400);
    assert.equal(f.calls.some(c => /^(DELETE|UPDATE|INSERT)/.test(c.sql)), false);
  }
});

test('reset commits attendance cleanup, audit snapshots and reconciliation together, preserving unrelated records', async () => {
  const f = fixture({ processed: [{ service_month: '2026-10-01', deducted_days: 1 }] });
  const preview = await f.service.preview(input, actor);
  const result = await f.service.apply({ ...input, preview_token: preview.preview_token,
    reason: 'Remove demonstration punches', confirmation: 'RESET' }, actor);
  assert.equal(result.punches_deleted, 1);
  assert.equal(f.state.raw.length, 0);
  assert.equal(f.state.summaries.length, 0);
  assert.equal(f.state.blocks.length, 0);
  assert.equal(f.audits.length, 1);
  assert.equal(f.audits[0].before.punches[0].id, rawId);
  assert.equal(f.audits[0].before.summary.id, rawId);
  assert.equal(f.queue[0].employeeId, employee);
  assert.equal(f.queue[0].dateFrom, date);
  assert.equal(f.broadcasts.length, 1);
  assert.equal(f.calls.some(c => c.sql === 'COMMIT'), true);
  assert.equal(f.calls.some(c => /^(DELETE|UPDATE) (assignments|leave_balances|leave_requests|locator_slips)/.test(c.sql)), false);
});

test('a new punch or another actor invalidates the preview before deletion', async () => {
  for (const changedActor of [false, true]) {
    const f = fixture();
    const preview = await f.service.preview(input, actor);
    if (!changedActor) f.state.raw.push({ id: actor, user_id: employee, logged_at: stamp('19:27:10') });
    await assert.rejects(f.service.apply({ ...input, preview_token: preview.preview_token,
      reason: 'Remove demonstration punches', confirmation: 'RESET' }, changedActor ? employee : actor), e => e.status === 409);
    assert.equal(f.calls.some(c => /^(DELETE|UPDATE|INSERT)/.test(c.sql)), false);
  }
});

test('approved coverage blocks cleanup and no-op reset cannot be applied', async () => {
  for (const data of [{ coverage: [{ id: rawId }] }, { raw: [], summaries: [], blocks: [] }]) {
    const f = fixture(data);
    const preview = await f.service.preview(input, actor);
    assert.equal(preview.can_reset, false);
    await assert.rejects(f.service.apply({ ...input, preview_token: preview.preview_token,
      reason: 'Remove demonstration punches', confirmation: 'RESET' }, actor), e => e.status === 409);
  }
});

test('audit failure rolls back all removals and sends no success refresh', async () => {
  const f = fixture({ auditFailure: true });
  const preview = await f.service.preview(input, actor);
  f.calls.length = 0;
  await assert.rejects(f.service.apply({ ...input, preview_token: preview.preview_token,
    reason: 'Remove demonstration punches', confirmation: 'RESET' }, actor));
  assert.equal(f.state.raw.length, 1);
  assert.equal(f.state.summaries.length, 1);
  assert.equal(f.state.blocks.length, 1);
  assert.equal(f.broadcasts.length, 0);
  assert.equal(f.calls.some(c => c.sql === 'COMMIT'), false);
});

test('preview includes next-day overnight punches and preserves the following shift', async () => {
  const night = { ...shift, startMinutes: 1200, endMinutes: 420, captureWindowMinutes: 120 };
  const f = fixture({ summaries: [{ id: rawId, employee_id: employee, attendance_date: date, shift_snapshot: night }], raw: [
    { id: rawId, user_id: employee, logged_at: stamp('20:00:00') },
    { id: actor, user_id: employee, logged_at: stamp('07:00:00', '2026-11-09') },
    { id: employee, user_id: employee, logged_at: stamp('20:00:00', '2026-11-09') },
  ] });
  const preview = await f.service.preview(input, actor);
  assert.deepEqual(preview.punches.map(r => r.id), [rawId, actor]);
  await f.service.apply({ ...input, preview_token: preview.preview_token,
    reason: 'Remove demonstration punches', confirmation: 'RESET' }, actor);
  assert.deepEqual(f.state.raw.map(r => r.id), [employee]);
});
