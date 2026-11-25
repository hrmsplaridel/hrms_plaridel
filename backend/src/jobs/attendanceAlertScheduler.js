/**
 * Daily attendance alerts (missing punch / absence without leave).
 *
 * Cron: every day at 07:00 Asia/Manila, checking the previous few days.
 * Opt-in: set ATTENDANCE_ALERTS_ENABLED=true.
 *
 * Multi-instance safe: pg_try_advisory_lock key 918273647 (distinct from the
 * leave accrual 918273645 and year-end forced leave 918273646 jobs).
 */

const cron = require('node-cron');
const {
  attendanceAlertsEnabled,
  runAttendanceAlerts,
} = require('../services/attendanceAlerts');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');

const CRON_EXPRESSION = '0 7 * * *';
const CRON_TIMEZONE = 'Asia/Manila';
const ADVISORY_LOCK_KEY = 918273647;

async function runAttendanceAlertJob(pool) {
  const client = await pool.connect();
  try {
    const { rows } = await client.query(
      'SELECT pg_try_advisory_lock($1::bigint) AS got',
      [ADVISORY_LOCK_KEY]
    );
    if (!rows[0]?.got) return { ran: false, reason: 'advisory_lock_not_acquired' };
    try {
      const { loadDtrDependencies } = require('../modules/dtr/dependencies');
      const { createDtrRuntime } = require('../modules/dtr/dtr.runtime');
      const runtime = createDtrRuntime(loadDtrDependencies());
      const summary = await runAttendanceAlerts({
        db: pool,
        listDtrDailySummaries: runtime.listDtrDailySummaries,
        today: todayInHrmsTimezone(),
      });
      console.log(
        '[AttendanceAlerts] Done:',
        `sent=${summary.sent}`,
        `already_sent=${summary.already_sent}`,
        `checked=${summary.checked_dates.join(',') || '-'}`,
        `skipped_no_biometric_data=${summary.skipped_dates.join(',') || '-'}`
      );
      return { ran: true, summary };
    } finally {
      await client.query('SELECT pg_advisory_unlock($1::bigint)', [ADVISORY_LOCK_KEY]);
    }
  } finally {
    client.release();
  }
}

function scheduleAttendanceAlertCron(pool) {
  if (!attendanceAlertsEnabled()) {
    console.log('[AttendanceAlerts] Disabled (set ATTENDANCE_ALERTS_ENABLED=true to enable)');
    return false;
  }
  cron.schedule(
    CRON_EXPRESSION,
    async () => {
      try {
        await runAttendanceAlertJob(pool);
      } catch (err) {
        console.error('[AttendanceAlerts] Cron error:', err);
      }
    },
    { timezone: CRON_TIMEZONE }
  );
  console.log(`[AttendanceAlerts] Cron scheduled: "${CRON_EXPRESSION}" (${CRON_TIMEZONE})`);
  return true;
}

module.exports = { scheduleAttendanceAlertCron, runAttendanceAlertJob };
