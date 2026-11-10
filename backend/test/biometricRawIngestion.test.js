'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const userId = '11111111-1111-4111-8111-111111111111';
const deviceId = '22222222-2222-4222-8222-222222222222';
const loggedAt = '2026-09-12T08:00:00+08:00';

async function invokeIngestionRoute({
  path,
  body,
  gateReason,
  insertRowCount = 1,
  hasStoredPunch = false,
  processError = null,
  logicalDate = null,
  importConflict = null,
  conflictError = null,
  userLookupRows = [{
    id: userId,
    biometric_user_id: '1001',
    is_active: true,
    employment_status: 'active',
    date_hired: null,
    separation_date: null,
  }],
}) {
  const events = [];
  const processCalls = [];
  const syncUpdates = [];
  const rawInserts = [];
  const pool = {
    async query(sql, params = []) {
      const text = String(sql);
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(text)) {
        events.push(text.toLowerCase());
        return { rows: [], rowCount: 0 };
      }
      if (text.includes('pg_advisory_xact_lock')) return { rows: [], rowCount: 1 };
      if (text.includes('FROM biometric_devices') && text.includes('WHERE id = $1::uuid')) {
        return { rows: [{ id: params[0], is_active: true }], rowCount: 1 };
      }
      if (text.includes('UPDATE biometric_devices') && text.includes('last_sync_at = now()')) {
        events.push('sync');
        syncUpdates.push(params[0]);
        return {
          rows: [{ last_sync_at: '2026-09-12T00:05:00.000Z' }],
          rowCount: 1,
        };
      }
      if (
        text.includes('FROM users') &&
        text.includes('WHERE biometric_user_id = ANY')
      ) {
        return {
          rows: userLookupRows,
          rowCount: userLookupRows.length,
        };
      }
      if (text.includes('SELECT 1') && text.includes('FROM biometric_attendance_logs')) {
        return hasStoredPunch
          ? { rows: [{ '?column?': 1 }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      if (text.includes('INSERT INTO biometric_attendance_logs')) {
        events.push('insert');
        rawInserts.push({ text, params });
        return insertRowCount > 0
          ? { rows: [{ id: 'raw-log-id' }], rowCount: insertRowCount }
          : { rows: [], rowCount: 0 };
      }
      if (text.includes('MIN((logged_at AT TIME ZONE')) {
        return {
          rows: [{ min_date: '2026-09-12', max_date: '2026-09-12' }],
          rowCount: 1,
        };
      }
      throw new Error(`Unexpected query: ${text}`);
    },
  };
  pool.connect = async () => ({ query: pool.query.bind(pool), release() { events.push('release'); } });

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const restoreProcessing = withMockedModule('../src/services/biometricProcessing', {
    getManilaDateStr: (value) => String(value).slice(0, 10),
    resolveBiometricPunchDate: async (_employee, value) => logicalDate || String(value).slice(0, 10),
    evaluateBiometricDayGate: async () => {
      events.push('gate');
      return {
        allowed: gateReason == null,
        reason: gateReason ?? null,
        shiftInfo: gateReason == null ? { endMinutes: 1020 } : null,
      };
    },
    isPunchAfterShiftEnd: () => false,
    processBiometricLogsToSummary: async (...args) => {
      events.push('process');
      processCalls.push(args);
      if (processError) throw processError;
      return { inserted: 0, updated: 0 };
    },
  });
  const routePath = '../src/routes/biometricAttendanceLogs';
  const restoreConflicts = withMockedModule('../src/services/manualImportConflicts', {
    createManualImportConflictChecker: () => async args => {
      events.push('coverage');
      if (conflictError) throw conflictError;
      return typeof importConflict === 'function' ? importConflict(args) : importConflict || {
        exclusion: ['holiday', 'leave'].includes(gateReason) ? {
          code: gateReason === 'leave' ? 'approved_leave' : 'holiday', message: 'Covered attendance date.',
        } : null, warnings: [],
      };
    },
  });
  clearModule(routePath);

  const res = {
    statusCode: 200,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };

  try {
    const router = require(routePath);
    const route = router.stack.find(
      (entry) => entry.route?.path === path && entry.route.methods.post
    );
    if (path === '/import/preview') {
      const guards = route.route.stack.map(entry => entry.handle);
      assert.equal(guards[0], require('../src/middleware/auth').authMiddleware);
      assert.equal(guards[1], require('../src/middleware/rbac').requireAdmin);
      assert.equal(guards[2], require('../src/middleware/dtrAccess').requireDtrManageIfAdmin);
    }
    await route.route.stack.at(-1).handle({ body }, res);
    return { res, events, processCalls, syncUpdates, rawInserts };
  } finally {
    clearModule(routePath);
    restoreConflicts();
    restoreProcessing();
    restoreDb();
  }
}

test('device push preserves a matched raw punch when no schedule is configured', async () => {
  const { res, events, processCalls } = await invokeIngestionRoute({
    path: '/push',
    gateReason: 'no_schedule',
    body: {
      punches: [{ biometric_user_id: '1001', logged_at: loggedAt }],
      biometric_device_id: deviceId,
      source_name: 'test-clock',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 1);
  assert.equal(res.body.skipped_no_schedule, 1);
  assert.ok(events.indexOf('insert') < events.indexOf('gate'));
  assert.deepEqual(processCalls, [[[userId], '2026-09-12', '2026-09-12']]);
});

test('next-morning device punch keeps its raw timestamp and uses the previous attendance date', async () => {
  const nextMorning = '2026-10-01T07:00:00+08:00';
  const { res, processCalls, rawInserts } = await invokeIngestionRoute({
    path: '/push', logicalDate: '2026-09-30',
    body: { punches: [{ biometric_user_id: '1001', logged_at: nextMorning }], biometric_device_id: deviceId },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(rawInserts[0].params[2], nextMorning);
  assert.deepEqual(processCalls, [[[userId], '2026-09-30', '2026-09-30']]);
});

test('manual import excludes a matched punch during approved leave before raw insertion', async () => {
  const { res, events, processCalls } = await invokeIngestionRoute({
    path: '/import',
    gateReason: 'leave',
    body: {
      rows: [{
        user_id: userId,
        biometric_user_id: '1001',
        logged_at: loggedAt,
        raw_line: `1001\t${loggedAt}`,
      }],
      source_file_name: 'attlog.dat',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 0);
  assert.equal(res.body.skipped_leave, 1);
  assert.equal(events.includes('insert'), false);
  assert.equal(res.body.row_errors[0].code, 'approved_leave');
  assert.deepEqual(processCalls, []);
});

const importRow = (time = loggedAt) => ({ biometric_user_id: '1001', logged_at: time, raw_line: `1001\t${time}` });

test('manual preview reports excluded rows and locator warnings without writing records', async () => {
  const { res, rawInserts, processCalls, events } = await invokeIngestionRoute({
    path: '/import/preview', gateReason: null,
    body: { rows: [importRow(), importRow('2026-09-12T17:00:00+08:00')] },
    importConflict: ({ loggedAt: at }) => at === loggedAt
      ? { exclusion: { code: 'holiday', message: 'Excluded holiday punch.' }, warnings: [] }
      : { exclusion: null, warnings: [{ code: 'locator_review', message: 'Verify approved locator coverage.' }] },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.rows_ready, 1);
  assert.equal(res.body.rows_excluded, 1);
  assert.equal(res.body.row_errors[0].row, 1);
  assert.equal(res.body.review_warnings[0].row, 2);
  assert.equal(res.body.review_warnings[0].attendance_date, '2026-09-12');
  assert.deepEqual(rawInserts, []); assert.deepEqual(processCalls, []);
  assert.equal(events.includes('begin'), false);
});

test('manual confirmation excludes newly approved coverage even if client asks to bypass it', async () => {
  const { res, rawInserts } = await invokeIngestionRoute({
    path: '/import', gateReason: 'holiday',
    body: { rows: [importRow()], ignore_conflicts: true, warnings_reviewed: true },
  });
  assert.equal(res.body.inserted, 0);
  assert.equal(res.body.skipped_holiday, 1);
  assert.deepEqual(rawInserts, []);
});

test('manual import requires warning acknowledgement before any row is saved', async () => {
  const { res, rawInserts, events } = await invokeIngestionRoute({
    path: '/import', gateReason: null, body: { rows: [importRow()] },
    importConflict: { exclusion: null, warnings: [{ code: 'locator_review', message: 'Review locator.' }] },
  });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.code, 'IMPORT_REVIEW_REQUIRED');
  assert.deepEqual(rawInserts, []);
  assert.ok(events.includes('rollback'));
});

test('reviewed locator warnings permit real punches and do not override blocked rows', async () => {
  const { res, rawInserts, events } = await invokeIngestionRoute({
    path: '/import', gateReason: null,
    body: { rows: [importRow(), importRow('2026-09-12T17:00:00+08:00')], warnings_reviewed: true },
    importConflict: ({ loggedAt: at }) => at === loggedAt
      ? { exclusion: { code: 'approved_leave', message: 'Leave.' }, warnings: [] }
      : { exclusion: null, warnings: [{ code: 'locator_review', message: 'Review locator.' }] },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 1); assert.equal(res.body.skipped_leave, 1);
  assert.equal(rawInserts.length, 1);
  assert.ok(events.indexOf('commit') < events.indexOf('process'));
});

test('manual coverage lookup failure rolls back without saving any punches', async () => {
  const { res, rawInserts, events } = await invokeIngestionRoute({
    path: '/import', gateReason: null, body: { rows: [importRow()] },
    conflictError: new Error('Coverage unavailable'),
  });
  assert.equal(res.statusCode, 500);
  assert.deepEqual(rawInserts, []);
  assert.ok(events.includes('rollback')); assert.ok(events.includes('release'));
});

test('device push preserves raw evidence on leave and holidays without manual review', async () => {
  for (const gateReason of ['holiday', 'leave']) {
    const { res, rawInserts, events } = await invokeIngestionRoute({
      path: '/push', gateReason,
      body: { punches: [importRow()], biometric_device_id: deviceId },
    });
    assert.equal(res.statusCode, 200); assert.equal(rawInserts.length, 1);
    assert.equal(events.includes('coverage'), false);
  }
});

test('manual import resolves employee identity from the current biometric mapping', async () => {
  const { res, rawInserts } = await invokeIngestionRoute({
    path: '/import',
    gateReason: null,
    body: {
      rows: [{
        biometric_user_id: '1001',
        logged_at: loggedAt,
        raw_line: `1001\t${loggedAt}`,
      }],
      source_file_name: 'attlog.dat',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 1);
  assert.equal(res.body.skipped_unmatched, 0);
  assert.equal(res.body.skipped_identity_mismatch, 0);
  assert.equal(rawInserts.length, 1);
  assert.equal(rawInserts[0].params[0], userId);
});

test('manual import skips a stale employee and biometric identity pair', async () => {
  const staleUserId = '33333333-3333-4333-8333-333333333333';
  const { res, rawInserts, processCalls } = await invokeIngestionRoute({
    path: '/import',
    gateReason: null,
    body: {
      rows: [{
        user_id: staleUserId,
        biometric_user_id: '1001',
        logged_at: loggedAt,
        raw_line: `1001\t${loggedAt}`,
      }],
      source_file_name: 'attlog.dat',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 0);
  assert.equal(res.body.skipped_identity_mismatch, 1);
  assert.deepEqual(rawInserts, []);
  assert.deepEqual(processCalls, []);
});

test('manual import skips a biometric ID without a current employee mapping', async () => {
  const { res, rawInserts, processCalls } = await invokeIngestionRoute({
    path: '/import',
    gateReason: null,
    userLookupRows: [],
    body: {
      rows: [{
        user_id: userId,
        biometric_user_id: '1001',
        logged_at: loggedAt,
        raw_line: `1001\t${loggedAt}`,
      }],
      source_file_name: 'attlog.dat',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 0);
  assert.equal(res.body.skipped_unmatched, 1);
  assert.deepEqual(rawInserts, []);
  assert.deepEqual(processCalls, []);
});

test('manual import skips punches after an inactive employee separation date', async () => {
  const { res, rawInserts, processCalls } = await invokeIngestionRoute({
    path: '/import',
    gateReason: null,
    userLookupRows: [{
      id: userId,
      biometric_user_id: '1001',
      is_active: false,
      employment_status: 'inactive',
      date_hired: '2025-01-01',
      separation_date: '2026-08-31',
    }],
    body: {
      rows: [{
        user_id: userId,
        biometric_user_id: '1001',
        logged_at: loggedAt,
        raw_line: `1001\t${loggedAt}`,
      }],
      source_file_name: 'attlog.dat',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 0);
  assert.equal(res.body.skipped_outside_employment, 1);
  assert.deepEqual(rawInserts, []);
  assert.deepEqual(processCalls, []);
});

test('manual import accepts historical punches within an inactive employee employment period', async () => {
  const { res, rawInserts } = await invokeIngestionRoute({
    path: '/import',
    gateReason: null,
    userLookupRows: [{
      id: userId,
      biometric_user_id: '1001',
      is_active: false,
      employment_status: 'inactive',
      date_hired: '2025-01-01',
      separation_date: '2026-09-30',
    }],
    body: {
      rows: [{
        user_id: userId,
        biometric_user_id: '1001',
        logged_at: loggedAt,
        raw_line: `1001\t${loggedAt}`,
      }],
      source_file_name: 'attlog.dat',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 1);
  assert.equal(res.body.skipped_outside_employment, 0);
  assert.equal(rawInserts.length, 1);
});

test('device push reprocesses duplicate punches after a prior processing failure', async () => {
  const { res, events, processCalls } = await invokeIngestionRoute({
    path: '/push',
    gateReason: null,
    insertRowCount: 0,
    hasStoredPunch: true,
    body: {
      punches: [{ biometric_user_id: '1001', logged_at: loggedAt }],
      biometric_device_id: deviceId,
      source_name: 'test-clock',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 0);
  assert.equal(res.body.duplicates_skipped, 1);
  assert.ok(events.includes('process'));
  assert.deepEqual(processCalls, [[[userId], '2026-09-12', '2026-09-12']]);
});

test('device push processes only dates represented in the incoming batch', async () => {
  const { res, processCalls } = await invokeIngestionRoute({
    path: '/push',
    gateReason: null,
    body: {
      punches: [
        { biometric_user_id: '1001', logged_at: '2026-09-10T08:00:00+08:00' },
        { biometric_user_id: '1001', logged_at: '2026-09-12T08:00:00+08:00' },
      ],
      biometric_device_id: deviceId,
      source_name: 'test-clock',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 2);
  assert.deepEqual(processCalls, [
    [[userId], '2026-09-10', '2026-09-10'],
    [[userId], '2026-09-12', '2026-09-12'],
  ]);
});

test('successful empty device heartbeat advances last_sync_at', async () => {
  const { res, events, processCalls, syncUpdates } = await invokeIngestionRoute({
    path: '/push',
    gateReason: null,
    body: {
      punches: [],
      biometric_device_id: deviceId,
      sync_heartbeat: true,
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.sync_heartbeat, true);
  assert.equal(res.body.biometric_device_id, deviceId);
  assert.equal(res.body.last_sync_at, '2026-09-12T00:05:00.000Z');
  assert.deepEqual(syncUpdates, [deviceId]);
  assert.deepEqual(processCalls, []);
  assert.deepEqual(events, ['sync']);
});

test('registered device push stores its authoritative UUID on every raw punch', async () => {
  const { res, rawInserts } = await invokeIngestionRoute({
    path: '/push',
    gateReason: null,
    body: {
      punches: [{ biometric_user_id: '1001', logged_at: loggedAt }],
      biometric_device_id: deviceId,
      source_name: 'editable-device-label',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(rawInserts.length, 1);
  assert.match(rawInserts[0].text, /source_file_name, device_ref_id/);
  assert.equal(rawInserts[0].params[5], deviceId);
});

test('device push rejects punches without a registered device UUID', async () => {
  const { res, rawInserts } = await invokeIngestionRoute({
    path: '/push',
    gateReason: null,
    body: {
      punches: [{ biometric_user_id: '1001', logged_at: loggedAt }],
      source_name: 'unattributed-clock',
    },
  });

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /biometric_device_id is required/i);
  assert.deepEqual(rawInserts, []);
});

test('failed attendance processing does not advance device last_sync_at', async () => {
  const { res, events, syncUpdates } = await invokeIngestionRoute({
    path: '/push',
    gateReason: null,
    processError: new Error('simulated processing failure'),
    body: {
      punches: [{ biometric_user_id: '1001', logged_at: loggedAt }],
      biometric_device_id: deviceId,
      source_name: 'test-clock',
    },
  });

  assert.equal(res.statusCode, 500);
  assert.deepEqual(syncUpdates, []);
  assert.equal(events.includes('sync'), false);
});
