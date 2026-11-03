const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const actor = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const valid = { ot_date: '2026-11-01', time_start: '18:00', time_end: '20:00', total_hours: 2 };

async function invoke(body, { role = 'admin', id = actor, dbError, notifyError } = {}) {
  const calls = [], notified = [];
  const restores = [
    withMockedModule('../src/config/db', { pool: { async query(sql, params) {
      calls.push({ sql, params });
      if (dbError) throw new Error('Database unavailable');
      if (sql.includes('INSERT INTO overtime_requests')) {
        return { rowCount: 1, rows: [{ id: 'overtime-id', employee_id: params[0], ot_date: params[1],
          time_start: params[2], time_end: params[3], total_hours: params[4], reason: params[5], status: 'pending' }] };
      }
      if (sql.includes('SELECT full_name')) return { rows: [{ full_name: 'Sample Employee' }] };
      throw new Error(`Unexpected query: ${sql}`);
    } } }),
    withMockedModule('../src/services/overtimeNotifications', {
      notifyOvertimeSubmitted: async (_pool, data) => { notified.push(data); if (notifyError) throw new Error('Notification unavailable'); },
    }),
  ];
  clearModule('../src/routes/overtime');
  try {
    const router = require('../src/routes/overtime');
    const handler = router.stack.find(l => l.route?.path === '/' && l.route.methods.post).route.stack.at(-1).handle;
    const res = { code: 200, status(n) { this.code = n; return this; }, json(data) { this.body = data; return this; } };
    await handler({ body, user: { id, role } }, res);
    return { res, calls, notified };
  } finally {
    clearModule('../src/routes/overtime');
    restores.reverse().forEach(restore => restore());
  }
}

for (const total_hours of ['900junk', '2hours', '', ' ', null, true, false, [], [2], {}, '0x2', '2e0', 'Infinity', Infinity, NaN, -1, 0, 25, 900, 1e308, 0.001]) {
  test(`invalid overtime hours cannot query or notify: ${String(total_hours)}`, async t => {
    t.mock.method(console, 'error', () => {});
    const { res, calls, notified } = await invoke({ ...valid, total_hours });
    assert.equal(res.code, 400);
    assert.match(res.body.error, /hours/i);
    assert.deepEqual(calls, []);
    assert.deepEqual(notified, []);
  });
}

for (const [field, values] of [
  ['ot_date', ['2026-02-30', '2025-02-29', '0000-01-01', '2026-11-01T00:00:00Z', null, {}, ['2026-11-01']]],
  ['time_start', ['24:00', '18:60', '18:00:60', 'junk', '18:00Z', '2026-11-01T18:00:00Z', null, {}, ['18:00']]],
  ['time_end', ['24:00', '-1:00', '20:60', true, null, {}]],
  ['employee_id', ['bad-id', {}, [], 123]],
  ['reason', [false, 123, {}, [], 'bad\0reason']],
]) {
  for (const value of values) {
    test(`invalid overtime ${field}: ${JSON.stringify(value)}`, async t => {
      t.mock.method(console, 'error', () => {});
      const { res, calls, notified } = await invoke({ ...valid, [field]: value });
      assert.equal(res.code, 400);
      assert.match(res.body.error, new RegExp(field === 'employee_id' ? 'employee' : field, 'i'));
      assert.deepEqual(calls, []);
      assert.deepEqual(notified, []);
    });
  }
}

for (const body of [null, [], 'bad', 123, {}]) {
  test(`malformed overtime body cannot write: ${JSON.stringify(body)}`, async t => {
    t.mock.method(console, 'error', () => {});
    const { res, calls, notified } = await invoke(body);
    assert.equal(res.code, 400);
    assert.deepEqual(calls, []);
    assert.deepEqual(notified, []);
  });
}

for (const body of [
  { ...valid, total_hours: 1 },
  { ...valid, total_hours: 3 },
  { ...valid, total_hours: 2.01 },
  { ...valid, total_hours: 900, override: true },
  { ...valid, time_start: '22:00', time_end: '02:00', total_hours: 2 },
  { ...valid, time_start: '18:00', time_end: '18:00', total_hours: 24 },
]) {
  test(`overtime duration must agree with time interval: ${JSON.stringify(body)}`, async () => {
    const { res, calls, notified } = await invoke(body);
    assert.equal(res.code, 400);
    assert.deepEqual(calls, []);
    assert.deepEqual(notified, []);
  });
}

for (const [body, hours] of [
  [valid, 2],
  [{ ...valid, total_hours: ' 2.00 ', reason: '  Inventory  ' }, 2],
  [{ ...valid, time_start: '18:00:00', time_end: '20:30:00', total_hours: 2.5 }, 2.5],
  [{ ...valid, time_start: '22:00', time_end: '02:00', total_hours: '4' }, 4],
  [{ ...valid, time_start: '23:30', time_end: '00:15', total_hours: 0.75 }, 0.75],
  [{ ...valid, time_end: '19:10', total_hours: 1.17 }, 1.17],
  [{ ...valid, time_end: '19:10', total_hours: 70 / 60 }, 1.17],
  [{ ...valid, time_start: '00:00:00', time_end: '00:00:36', total_hours: 0.01 }, 0.01],
  [{ ...valid, time_start: '00:00:00', time_end: '23:59:00', total_hours: 23.98 }, 23.98],
  [{ ...valid, ot_date: '2024-02-29', reason: null }, 2],
  [{ ...valid, reason: '  ' }, 2],
  [{ ...valid, time_start: '18:00:00.250000', time_end: '20:00:00.250000' }, 2],
  [{ ...valid, time_start: '00:00:00', time_end: '23:59:59', total_hours: 24 }, 24],
]) {
  test(`valid overtime preserves normalized duration and notifications: ${JSON.stringify(body)}`, async () => {
    const { res, calls, notified } = await invoke(body);
    assert.equal(res.code, 201);
    assert.equal(calls.length, 2);
    assert.equal(calls[0].params[4], hours);
    assert.equal(res.body.total_hours, hours);
    assert.equal(res.body.status, 'pending');
    assert.equal(res.body.reason, body.reason?.trim() || null);
    assert.match(calls[0].sql, /'pending'/);
    assert.equal(notified.length, 1);
    assert.equal(notified[0].employeeUserId, actor);
  });
}

for (const role of ['admin', 'hr', 'supervisor']) {
  test(`${role} may retain filing on behalf of another employee`, async () => {
    const { res } = await invoke({ ...valid, employee_id: other }, { role });
    assert.equal(res.code, 201);
    assert.equal(res.body.employee_id, other);
  });
}

test('ordinary employee cannot redirect an overtime submission to another employee', async () => {
  const { res, notified } = await invoke({ ...valid, employee_id: other }, { role: 'employee' });
  assert.equal(res.code, 201);
  assert.equal(res.body.employee_id, actor);
  assert.equal(notified[0].employeeUserId, actor);
});

test('notification failure retains the existing successful submission response', async t => {
  t.mock.method(console, 'error', () => {});
  const { res, calls } = await invoke(valid, { notifyError: true });
  assert.equal(res.code, 201);
  assert.equal(calls.length, 2);
});

test('database failure is not misreported as validation or success', async t => {
  t.mock.method(console, 'error', () => {});
  const { res, notified } = await invoke(valid, { dbError: true });
  assert.equal(res.code, 500);
  assert.deepEqual(notified, []);
});

test('valid employee ID and times are trimmed consistently for storage and notification lookup', async () => {
  const { res, calls, notified } = await invoke({ ...valid, employee_id: ` ${other} `, time_start: ' 18:00 ', time_end: ' 20:00 ' });
  assert.equal(res.code, 201);
  assert.deepEqual(calls[0].params.slice(0, 5), [other, valid.ot_date, '18:00', '20:00', 2]);
  assert.deepEqual(calls[1].params, [other]);
  assert.equal(notified[0].employeeUserId, other);
});
