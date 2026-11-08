const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const employee = '11111111-1111-4111-8111-111111111111';
const valid = { biometric_user_id: '1001', logged_at: '2026-09-12T08:00:00+08:00', raw_line: '1001\t2026-09-12 08:00:00' };

async function invoke(body, { duplicate = false, gateReason = null, logicalDate = null, unresolved = false, users, processError } = {}) {
  const calls = [], inserts = [], processed = [], resolved = [];
  const restores = [
    withMockedModule('../src/config/db', { pool: { async query(sql, params) {
      calls.push({ sql, params });
      if (sql.includes('FROM users')) return { rows: users ?? [{ id: employee, biometric_user_id: '1001', is_active: true, employment_status: 'active', date_hired: '2025-01-01' }] };
      if (/^\s*SELECT 1/.test(sql)) return { rowCount: 0, rows: [] };
      if (sql.includes('INSERT INTO biometric_attendance_logs')) {
        inserts.push(params);
        return { rowCount: duplicate ? 0 : 1, rows: duplicate ? [] : [{ id: 'log-id' }] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    } } }),
    withMockedModule('../src/services/biometricProcessing', {
      resolveBiometricPunchDate: async (user, stamp) => { resolved.push(stamp); return unresolved ? null : logicalDate || stamp.slice(0, 10); },
      evaluateBiometricDayGate: async () => ({ allowed: !gateReason, reason: gateReason }),
      isPunchAfterShiftEnd: () => false,
      processBiometricLogsToSummary: async (...args) => {
        processed.push(args);
        if (processError) throw processError;
        return { inserted: 1, updated: 2 };
      },
    }),
  ];
  clearModule('../src/routes/biometricAttendanceLogs');
  try {
    const router = require('../src/routes/biometricAttendanceLogs');
    const handler = router.stack.find(l => l.route?.path === '/import' && l.route.methods.post).route.stack.at(-1).handle;
    const res = { code: 200, status(n) { this.code = n; return this; }, json(data) { this.body = data; return this; } };
    await handler({ body }, res);
    return { res, calls, inserts, processed, resolved };
  } finally {
    clearModule('../src/routes/biometricAttendanceLogs');
    restores.reverse().forEach(restore => restore());
  }
}

const malformed = [
  ['row', null], ['row', []], ['row', 'bad row'], ['row', 123], ['row', false],
  ['biometric_user_id', { ...valid, biometric_user_id: {} }],
  ['biometric_user_id', { ...valid, biometric_user_id: 1001 }],
  ['biometric_user_id', { ...valid, biometric_user_id: '  ' }],
  ['raw_line', { ...valid, raw_line: null }],
  ['raw_line', { ...valid, raw_line: ['raw'] }],
  ['raw_line', { ...valid, raw_line: '  ' }],
  ['raw_line', { ...valid, raw_line: 'bad\0line' }],
  ['verify_code', { ...valid, verify_code: 1 }],
  ['punch_code', { ...valid, punch_code: [] }],
  ['work_code', { ...valid, work_code: {} }],
  ['user_id', { ...valid, user_id: {} }],
  ['user_id', { ...valid, user_id: 'not-a-uuid' }],
];
for (const [field, bad] of malformed) {
  test(`import rejects malformed ${field} without losing a valid earlier row: ${JSON.stringify(bad)}`, async t => {
    t.mock.method(console, 'error', () => {});
    const { res, inserts, processed } = await invoke({ rows: [valid, bad] });
    assert.equal(res.code, 200);
    assert.equal(res.body.inserted, 1);
    assert.equal(res.body.skipped_invalid_row, 1);
    assert.deepEqual(res.body.row_errors.map(e => [e.row, e.field]), [[2, field]]);
    assert.equal(typeof res.body.row_errors[0].error, 'string');
    assert.equal(inserts.length, 1);
    assert.deepEqual(processed, [[[employee], '2026-09-12', '2026-09-12']]);
    assert.equal(res.body.summaries_inserted, 1);
    assert.equal(res.body.summaries_updated, 2);
  });
}

for (const logged_at of [null, true, {}, [], 123, '', 'junk', '2026-02-30T08:00:00Z', '2026-09-12', '2026-09-12T24:00:00Z', '0000-09-12T08:00:00Z', '2026-09-12T08:00:00+16:00']) {
  test(`invalid timestamp is counted separately and cannot reach INSERT: ${JSON.stringify(logged_at)}`, async t => {
    t.mock.method(console, 'error', () => {});
    const { res, inserts, resolved } = await invoke({ rows: [{ ...valid, logged_at }, valid] });
    assert.equal(res.code, 200);
    assert.equal(res.body.skipped_invalid_timestamp, 1);
    assert.equal(res.body.skipped_invalid_row, 0);
    assert.deepEqual(res.body.row_errors.map(e => [e.row, e.field]), [[1, 'logged_at']]);
    assert.equal(inserts.length, 1);
    assert.deepEqual(resolved, [valid.logged_at]);
  });
}

for (const body of [null, [], 'bad', {}, { rows: [] }, { rows: {} }, { rows: [valid], source_file_name: {} }, { rows: [valid], source_file_name: 'bad\0file' }]) {
  test(`invalid import envelope causes no queries: ${JSON.stringify(body)}`, async t => {
    t.mock.method(console, 'error', () => {});
    const { res, calls } = await invoke(body);
    assert.equal(res.code, 400);
    assert.deepEqual(calls, []);
  });
}

test('all malformed rows report their original positions without queries', async () => {
  const { res, calls, processed } = await invoke({ rows: [null, {}, false] });
  assert.equal(res.code, 200);
  assert.equal(res.body.inserted, 0);
  assert.equal(res.body.skipped_invalid_row, 3);
  assert.deepEqual(res.body.row_errors.map(e => e.row), [1, 2, 3]);
  assert.deepEqual(calls, []);
  assert.deepEqual(processed, []);
});

test('error details are bounded while all rejected rows are counted', async () => {
  const { res } = await invoke({ rows: Array(125).fill(null) });
  assert.equal(res.code, 200);
  assert.equal(res.body.skipped_invalid_row, 125);
  assert.equal(res.body.row_errors.length, 100);
});

test('valid optional codes and identity are trimmed; raw text/timestamp are preserved', async () => {
  const row = { ...valid, user_id: ` ${employee.toUpperCase()} `, biometric_user_id: ' 1001 ', verify_code: ' 1 ', punch_code: '', work_code: null };
  const { res, inserts } = await invoke({ rows: [row], source_file_name: 'attlog.dat' });
  assert.equal(res.code, 200);
  assert.equal(res.body.skipped_invalid_row, 0);
  assert.deepEqual(res.body.row_errors, []);
  assert.deepEqual(inserts[0], [employee, '1001', valid.logged_at, '1', null, null, valid.raw_line, 'attlog.dat']);
});

test('duplicates still reach summary processing even beside a malformed row', async () => {
  const { res, processed } = await invoke({ rows: [null, valid] }, { duplicate: true });
  assert.equal(res.code, 200);
  assert.equal(res.body.inserted, 0);
  assert.equal(res.body.duplicates_skipped, 1);
  assert.equal(res.body.skipped_invalid_row, 1);
  assert.equal(processed.length, 1);
});

for (const gateReason of ['leave', 'holiday', 'no_schedule']) {
  test(`partial imports retain raw preservation and processing for ${gateReason}`, async () => {
    const { res, inserts, processed } = await invoke({ rows: [valid, null] }, { gateReason });
    assert.equal(res.code, 200);
    assert.equal(inserts.length, 1);
    assert.equal(res.body[`skipped_${gateReason}`], 1);
    assert.equal(processed.length, 1);
  });
}

test('overnight logical attendance date remains authoritative', async () => {
  const stamp = '2026-10-01T06:00:00+08:00';
  const { res, inserts, processed } = await invoke({ rows: [{ ...valid, logged_at: stamp }, null] }, { logicalDate: '2026-09-30' });
  assert.equal(res.code, 200);
  assert.equal(inserts[0][2], stamp);
  assert.deepEqual(processed, [[[employee], '2026-09-30', '2026-09-30']]);
});

test('mapping, employment, and duplicate counters remain distinct from malformed rows', async () => {
  const { res, inserts } = await invoke({ rows: [
    valid, null,
    { ...valid, biometric_user_id: 'unknown' },
    { ...valid, user_id: '22222222-2222-4222-8222-222222222222' },
    { ...valid, logged_at: '2024-01-01T08:00:00Z' },
  ] });
  assert.equal(res.code, 200);
  assert.equal(res.body.inserted, 1);
  assert.equal(res.body.skipped_invalid_row, 1);
  assert.equal(res.body.skipped_unmatched, 1);
  assert.equal(res.body.skipped_identity_mismatch, 1);
  assert.equal(res.body.skipped_outside_employment, 1);
  assert.equal(inserts.length, 1);
});

test('valid rows remain sorted chronologically and scopes process only represented days', async () => {
  const { res, inserts, processed } = await invoke({ rows: [
    { ...valid, logged_at: '2026-09-13T08:00:00+08:00' }, null, valid,
  ] });
  assert.equal(res.code, 200);
  assert.deepEqual(inserts.map(p => p[2]), [valid.logged_at, '2026-09-13T08:00:00+08:00']);
  assert.deepEqual(processed, [[[employee], '2026-09-12', '2026-09-12'], [[employee], '2026-09-13', '2026-09-13']]);
  assert.equal(res.body.row_errors[0].row, 2);
});

test('real processing failures are not reported as successful partial imports', async t => {
  t.mock.method(console, 'error', () => {});
  const { res, inserts } = await invoke({ rows: [valid] }, { processError: new Error('Processing unavailable') });
  assert.equal(res.code, 500);
  assert.equal(inserts.length, 1);
  assert.match(res.body.error, /Processing unavailable/);
});

for (const logged_at of ['2024-02-29T08:00:00Z', '2026-09-12T08:00:00.123456+08:00', '2026-09-12 08:00:00', '2026-09-12T08:00+0800']) {
  test(`valid timestamp representation is retained: ${logged_at}`, async () => {
    const { res, inserts } = await invoke({ rows: [{ ...valid, logged_at }] }, {
      users: [{ id: employee, biometric_user_id: '1001', is_active: true, date_hired: '2024-01-01' }],
    });
    assert.equal(res.code, 200);
    assert.equal(res.body.inserted, 1);
    assert.equal(res.body.skipped_invalid_timestamp, 0);
    assert.equal(inserts[0][2], logged_at);
  });
}

test('an unresolved logical date returns a row error without inserting', async () => {
  const { res, inserts, processed } = await invoke({ rows: [valid] }, { unresolved: true });
  assert.equal(res.code, 200);
  assert.equal(res.body.skipped_invalid_timestamp, 1);
  assert.deepEqual(res.body.row_errors.map(e => [e.row, e.field]), [[1, 'logged_at']]);
  assert.deepEqual(inserts, []);
  assert.deepEqual(processed, []);
});
