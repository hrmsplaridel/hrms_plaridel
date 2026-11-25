'use strict';

/**
 * Next-morning attendance alerts: tell employees about a missing punch or an
 * absence with no leave/locator, while they still remember the day.
 *
 * Reads the completed DTR report (leave, locator, holiday, rest-day, roster and
 * flexi overlays applied). Dates with no biometric logs at all are skipped so a
 * delayed device import never produces false alerts; later runs pick them up.
 */
const { insertNotification } = require('./notificationService');

const ATTENDANCE_ALERT_TYPE = 'attendance_alert';
const DEFAULT_LOOKBACK_DAYS = 3;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function attendanceAlertsEnabled(env = process.env) {
  return String(env.ATTENDANCE_ALERTS_ENABLED || '').trim().toLowerCase() === 'true';
}

function classifyAttendanceIssue(row) {
  if (row?.status === 'absent') return 'absent';
  if (row?.status === 'incomplete' && row.attendance_remark !== 'In progress') {
    return 'missing_punch';
  }
  return null;
}

function addDays(dateStr, amount) {
  const date = new Date(`${dateStr}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
}

function displayDate(dateStr) {
  const [year, month, day] = dateStr.split('-').map(Number);
  return `${MONTHS[month - 1]} ${day}, ${year}`;
}

function alertContent(issue, dateStr) {
  const when = displayDate(dateStr);
  if (issue === 'absent') {
    return {
      title: `No attendance recorded on ${when}`,
      body: `You are marked absent on ${when}. If you were on leave or official business, file a leave application or locator slip so your DTR is corrected.`,
    };
  }
  return {
    title: `Missing time log on ${when}`,
    body: `Your DTR for ${when} is incomplete (a time-in or time-out is missing). Check your attendance and request a correction or file a locator slip if needed.`,
  };
}

async function loadImportedDates(db, startDate, endDate) {
  const result = await db.query(
    `SELECT DISTINCT (logged_at AT TIME ZONE 'Asia/Manila')::date::text AS log_date
       FROM biometric_attendance_logs
      WHERE logged_at >= ($1::date::timestamp AT TIME ZONE 'Asia/Manila')
        AND logged_at < (($2::date + 1)::timestamp AT TIME ZONE 'Asia/Manila')`,
    [startDate, endDate]
  );
  return new Set(result.rows.map((row) => String(row.log_date).slice(0, 10)));
}

async function loadSentKeys(db, dates) {
  const result = await db.query(
    `SELECT user_id, metadata->>'attendance_date' AS attendance_date
       FROM user_notifications
      WHERE type = $1 AND metadata->>'attendance_date' = ANY($2::text[])`,
    [ATTENDANCE_ALERT_TYPE, dates]
  );
  return new Set(result.rows.map((row) => `${row.user_id}|${row.attendance_date}`));
}

async function loadCompletedReport(listDtrDailySummaries, startDate, endDate) {
  const captured = {
    statusCode: 200,
    body: null,
    locals: {},
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
    setHeader() {},
  };
  await listDtrDailySummaries(
    {
      user: { id: null, role: 'admin' },
      bulkReport: true,
      query: { start_date: startDate, end_date: endDate, recompute: 'true' },
    },
    captured
  );
  if (captured.statusCode >= 400) {
    throw new Error(captured.body?.error || 'Failed to prepare the attendance report');
  }
  return Array.isArray(captured.body) ? captured.body : [];
}

/**
 * @param {object} options
 * @param {import('pg').Pool} options.db
 * @param {Function} options.listDtrDailySummaries completed DTR report handler
 * @param {string} options.today HRMS calendar date (YYYY-MM-DD); today is never checked
 */
async function runAttendanceAlerts({
  db,
  listDtrDailySummaries,
  today,
  lookbackDays = DEFAULT_LOOKBACK_DAYS,
  notify = insertNotification,
}) {
  const dates = [];
  for (let offset = lookbackDays; offset >= 1; offset -= 1) dates.push(addDays(today, -offset));
  const imported = await loadImportedDates(db, dates[0], dates[dates.length - 1]);
  const checked = dates.filter((date) => imported.has(date));
  const summary = {
    checked_dates: checked,
    skipped_dates: dates.filter((date) => !imported.has(date)),
    sent: 0,
    already_sent: 0,
  };
  if (checked.length === 0) return summary;

  const rows = await loadCompletedReport(
    listDtrDailySummaries,
    checked[0],
    checked[checked.length - 1]
  );
  const sentKeys = await loadSentKeys(db, checked);
  const handled = new Set();
  for (const row of rows) {
    const date = String(row.record_date || '').slice(0, 10);
    const userId = row.user_id ? String(row.user_id) : '';
    if (!userId || !checked.includes(date)) continue;
    const issue = classifyAttendanceIssue(row);
    if (!issue) continue;
    const key = `${userId}|${date}`;
    if (handled.has(key)) continue;
    handled.add(key);
    if (sentKeys.has(key)) {
      summary.already_sent += 1;
      continue;
    }
    try {
      await notify(db, {
        userId,
        category: 'dtr',
        type: ATTENDANCE_ALERT_TYPE,
        ...alertContent(issue, date),
        metadata: { attendance_date: date, issue },
      });
      summary.sent += 1;
    } catch (err) {
      if (err?.code !== '23505') throw err;
      summary.already_sent += 1;
    }
  }
  return summary;
}

module.exports = {
  ATTENDANCE_ALERT_TYPE,
  DEFAULT_LOOKBACK_DAYS,
  attendanceAlertsEnabled,
  classifyAttendanceIssue,
  runAttendanceAlerts,
};
