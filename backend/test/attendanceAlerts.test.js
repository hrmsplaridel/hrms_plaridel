'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ATTENDANCE_ALERT_TYPE,
  attendanceAlertsEnabled,
  classifyAttendanceIssue,
  runAttendanceAlerts,
} = require('../src/services/attendanceAlerts');

const ANA = '00000000-0000-4000-8000-000000000a01';
const BEN = '00000000-0000-4000-8000-000000000b02';
const CAT = '00000000-0000-4000-8000-000000000c03';
const DAN = '00000000-0000-4000-8000-000000000d04';

test('alerts are opt-in', () => {
  assert.equal(attendanceAlertsEnabled({}), false);
  assert.equal(attendanceAlertsEnabled({ ATTENDANCE_ALERTS_ENABLED: 'false' }), false);
  assert.equal(attendanceAlertsEnabled({ ATTENDANCE_ALERTS_ENABLED: 'true' }), true);
});

test('only unexplained absences and missing punches raise alerts', () => {
  assert.equal(classifyAttendanceIssue({ status: 'absent' }), 'absent');
  assert.equal(classifyAttendanceIssue({ status: 'incomplete', time_in: 'x' }), 'missing_punch');
  assert.equal(
    classifyAttendanceIssue({ status: 'incomplete', time_in: 'x', attendance_remark: 'In progress' }),
    null
  );
  for (const status of ['present', 'late', 'on_leave', 'holiday', 'on_field', 'rest_day', 'not_tracked']) {
    assert.equal(classifyAttendanceIssue({ status }), null, status);
  }
});

function fakeDb({ importedDates, existing = [] }) {
  const queries = [];
  return {
    queries,
    async query(sql, params) {
      const text = String(sql);
      queries.push({ sql: text, params });
      if (/FROM biometric_attendance_logs/i.test(text)) {
        return { rows: importedDates.map((log_date) => ({ log_date })) };
      }
      if (/FROM user_notifications/i.test(text)) {
        return { rows: existing };
      }
      throw new Error(`Unexpected query: ${text}`);
    },
  };
}

test('sends one alert per employee per imported date, skipping dates without biometric data', async () => {
  const db = fakeDb({
    importedDates: ['2026-12-01', '2026-12-03'],
    existing: [{ user_id: ANA, attendance_date: '2026-12-01' }],
  });
  const reportCalls = [];
  const sent = [];
  const summary = await runAttendanceAlerts({
    db,
    today: '2026-12-04',
    lookbackDays: 3,
    async listDtrDailySummaries(req, res) {
      reportCalls.push({ ...req.query, bulkReport: req.bulkReport, role: req.user.role });
      res.json([
        { user_id: ANA, record_date: '2026-12-01', status: 'absent' },
        { user_id: BEN, record_date: '2026-12-03', status: 'incomplete', time_in: 'x' },
        { user_id: BEN, record_date: '2026-12-03', status: 'absent' },
        { user_id: CAT, record_date: '2026-12-02', status: 'absent' },
        { user_id: DAN, record_date: '2026-12-01', status: 'on_leave' },
        { user_id: DAN, record_date: '2026-12-03', status: 'absent' },
      ]);
    },
    async notify(_db, payload) {
      sent.push(payload);
    },
  });

  assert.deepEqual(reportCalls, [{
    start_date: '2026-12-01', end_date: '2026-12-03', recompute: 'true',
    bulkReport: true, role: 'admin',
  }]);
  assert.deepEqual(
    sent.map((n) => [n.userId, n.metadata.attendance_date, n.metadata.issue]),
    [[BEN, '2026-12-03', 'missing_punch'], [DAN, '2026-12-03', 'absent']]
  );
  const ben = sent[0];
  assert.equal(ben.category, 'dtr');
  assert.equal(ben.type, ATTENDANCE_ALERT_TYPE);
  assert.match(ben.title, /missing/i);
  assert.match(ben.body, /Dec 3, 2026/);
  assert.match(sent[1].body, /leave|locator/i);
  assert.deepEqual(summary, {
    checked_dates: ['2026-12-01', '2026-12-03'],
    skipped_dates: ['2026-12-02'],
    sent: 2,
    already_sent: 1,
  });
});

test('does nothing when no recent date has biometric data', async () => {
  const db = fakeDb({ importedDates: [] });
  const summary = await runAttendanceAlerts({
    db,
    today: '2026-12-04',
    lookbackDays: 3,
    async listDtrDailySummaries() { throw new Error('must not run'); },
    async notify() { throw new Error('must not notify'); },
  });
  assert.equal(summary.sent, 0);
  assert.deepEqual(summary.skipped_dates, ['2026-12-01', '2026-12-02', '2026-12-03']);
});

test('a duplicate alert from a concurrent run is skipped', async () => {
  const db = fakeDb({ importedDates: ['2026-12-03'] });
  const summary = await runAttendanceAlerts({
    db,
    today: '2026-12-04',
    lookbackDays: 1,
    async listDtrDailySummaries(req, res) {
      res.json([{ user_id: BEN, record_date: '2026-12-03', status: 'absent' }]);
    },
    async notify() {
      throw Object.assign(new Error('duplicate'), { code: '23505' });
    },
  });
  assert.equal(summary.sent, 0);
  assert.equal(summary.already_sent, 1);
});

test('report failures stop the run', async () => {
  await assert.rejects(
    runAttendanceAlerts({
      db: fakeDb({ importedDates: ['2026-12-03'] }),
      today: '2026-12-04',
      lookbackDays: 1,
      async listDtrDailySummaries(req, res) { res.status(500).json({ error: 'boom' }); },
      async notify() {},
    }),
    /boom/
  );
});

test('the daily job is only scheduled when enabled, at 7:00 AM Manila', () => {
  const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
  const scheduled = [];
  const restoreCron = withMockedModule('node-cron', {
    schedule: (expression, _fn, options) => scheduled.push({ expression, options }),
  });
  const jobPath = '../src/jobs/attendanceAlertScheduler';
  clearModule(jobPath);
  const previous = process.env.ATTENDANCE_ALERTS_ENABLED;
  try {
    const { scheduleAttendanceAlertCron } = require(jobPath);
    delete process.env.ATTENDANCE_ALERTS_ENABLED;
    assert.equal(scheduleAttendanceAlertCron({}), false);
    assert.equal(scheduled.length, 0);
    process.env.ATTENDANCE_ALERTS_ENABLED = 'true';
    assert.equal(scheduleAttendanceAlertCron({}), true);
    assert.deepEqual(scheduled, [{ expression: '0 7 * * *', options: { timezone: 'Asia/Manila' } }]);
  } finally {
    if (previous === undefined) delete process.env.ATTENDANCE_ALERTS_ENABLED;
    else process.env.ATTENDANCE_ALERTS_ENABLED = previous;
    clearModule(jobPath);
    restoreCron();
  }
});
