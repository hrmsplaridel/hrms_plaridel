/**
 * Schedules automatic monthly leave accrual (VL/SL) using the shared service.
 * Cron: 1st of every month at 00:00 Asia/Manila.
 *
 * Multi-instance: uses PostgreSQL pg_try_advisory_lock so only one worker runs per tick.
 * Disable with LEAVE_ACCRUAL_CRON_ENABLED=false (e.g. local dev or secondary instances).
 */

const cron = require('node-cron');
const { runLeaveMonthlyAccrual } = require('../services/leaveMonthlyAccrual');

/** Stable key for pg_try_advisory_lock (must not collide with other app locks). */
const ACCRUAL_CRON_ADVISORY_LOCK_KEY = 918273645;

/** Cron: minute hour day-of-month month day-of-week — 00:00 on the 1st, every month. */
const CRON_EXPRESSION = '0 0 1 * *';
const CRON_TIMEZONE = 'Asia/Manila';

/**
 * Current calendar year-month in Asia/Manila as YYYY-MM (for targetMonth).
 */
function manilaYearMonthNow() {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: CRON_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
  });
  const parts = fmt.formatToParts(new Date());
  const y = parts.find((p) => p.type === 'year')?.value;
  const m = parts.find((p) => p.type === 'month')?.value;
  if (!y || !m) {
    throw new Error('manilaYearMonthNow: could not resolve YYYY-MM');
  }
  return `${y}-${m}`;
}

/**
 * @param {import('pg').Pool} pool
 * @param {() => Promise<void>} fn
 */
async function withAccrualAdvisoryLock(pool, fn) {
  const client = await pool.connect();
  try {
    const { rows } = await client.query('SELECT pg_try_advisory_lock($1::bigint) AS got', [
      ACCRUAL_CRON_ADVISORY_LOCK_KEY,
    ]);
    if (!rows[0]?.got) {
      return { ran: false, reason: 'advisory_lock_not_acquired' };
    }
    try {
      await fn();
      return { ran: true };
    } finally {
      await client.query('SELECT pg_advisory_unlock($1::bigint)', [ACCRUAL_CRON_ADVISORY_LOCK_KEY]);
    }
  } finally {
    client.release();
  }
}

/**
 * @param {import('pg').Pool} pool
 */
function scheduleLeaveMonthlyAccrualCron(pool) {
  if (process.env.LEAVE_ACCRUAL_CRON_ENABLED === 'false') {
    console.log(
      '[leaveMonthlyAccrual][cron] disabled (LEAVE_ACCRUAL_CRON_ENABLED=false)',
    );
    return null;
  }

  const task = cron.schedule(
    CRON_EXPRESSION,
    async () => {
      const startedAt = new Date().toISOString();
      let ym;
      try {
        ym = manilaYearMonthNow();
      } catch (e) {
        console.error('[leaveMonthlyAccrual][cron] failed to resolve Manila YYYY-MM', e);
        return;
      }

      console.log(
        `[leaveMonthlyAccrual][cron] tick start at=${startedAt} targetMonth=${ym} tz=${CRON_TIMEZONE}`,
      );

      try {
        const lockResult = await withAccrualAdvisoryLock(pool, async () => {
          const result = await runLeaveMonthlyAccrual(pool, {
            dryRun: false,
            maxCatchUpMonths: 1,
            targetMonth: ym,
          });
          console.log(
            '[leaveMonthlyAccrual][cron] success',
            JSON.stringify({
              at: new Date().toISOString(),
              targetYearMonth: result.targetYearMonth,
              rowsUpdated: result.rowsUpdated,
              rowsSkipped: result.rowsSkipped,
              dryRun: result.dryRun,
              rate: result.rate,
              leaveTypes: result.leaveTypes,
            }),
          );
        });

        if (lockResult && !lockResult.ran) {
          console.log(
            `[leaveMonthlyAccrual][cron] skipped (${lockResult.reason}); another instance may be running`,
          );
        }
      } catch (err) {
        console.error(
          '[leaveMonthlyAccrual][cron] error',
          err && err.stack ? err.stack : err,
        );
      }
    },
    {
      timezone: CRON_TIMEZONE,
    },
  );

  console.log(
    `[leaveMonthlyAccrual][cron] scheduled expr="${CRON_EXPRESSION}" timezone=${CRON_TIMEZONE} (1st of month 00:00 Manila)`,
  );
  return task;
}

module.exports = {
  scheduleLeaveMonthlyAccrualCron,
  /** @internal for tests */
  manilaYearMonthNow,
  CRON_EXPRESSION,
  CRON_TIMEZONE,
};
