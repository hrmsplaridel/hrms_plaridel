'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const userId = '11111111-1111-4111-8111-111111111111';
const loggedAt = '2026-09-12T08:00:00+08:00';

async function invokeIngestionRoute({
  path,
  body,
  gateReason,
  insertRowCount = 1,
  hasStoredPunch = false,
}) {
  const events = [];
  const processCalls = [];
  const pool = {
    async query(sql) {
      const text = String(sql);
      if (text.includes('FROM users WHERE biometric_user_id = ANY')) {
        return {
          rows: [{ id: userId, biometric_user_id: '1001' }],
          rowCount: 1,
        };
      }
      if (text.includes('SELECT 1') && text.includes('FROM biometric_attendance_logs')) {
        return hasStoredPunch
          ? { rows: [{ '?column?': 1 }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      if (text.includes('INSERT INTO biometric_attendance_logs')) {
        events.push('insert');
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

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const restoreProcessing = withMockedModule('../src/services/biometricProcessing', {
    getManilaDateStr: (value) => String(value).slice(0, 10),
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
      return { inserted: 0, updated: 0 };
    },
  });
  const routePath = '../src/routes/biometricAttendanceLogs';
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
    await route.route.stack.at(-1).handle({ body }, res);
    return { res, events, processCalls };
  } finally {
    clearModule(routePath);
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
      source_name: 'test-clock',
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.inserted, 1);
  assert.equal(res.body.skipped_no_schedule, 1);
  assert.ok(events.indexOf('insert') < events.indexOf('gate'));
  assert.deepEqual(processCalls, [[[userId], '2026-09-12', '2026-09-12']]);
});

test('manual import preserves a matched raw punch during blocking leave', async () => {
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
  assert.equal(res.body.inserted, 1);
  assert.equal(res.body.skipped_leave, 1);
  assert.ok(events.indexOf('insert') < events.indexOf('gate'));
  assert.deepEqual(processCalls, [[[userId], '2026-09-12', '2026-09-12']]);
});

test('device push reprocesses duplicate punches after a prior processing failure', async () => {
  const { res, events, processCalls } = await invokeIngestionRoute({
    path: '/push',
    gateReason: null,
    insertRowCount: 0,
    hasStoredPunch: true,
    body: {
      punches: [{ biometric_user_id: '1001', logged_at: loggedAt }],
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
