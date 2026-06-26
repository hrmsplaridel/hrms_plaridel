/**
 * Schedules automatic monthly leave accrual (VL/SL) using the shared service.
 * Cron: 1st of every month at 00:00 Asia/Manila.
 *
 * Multi-instance: uses PostgreSQL pg_try_advisory_lock so only one worker runs per tick.
 * Disable with LEAVE_ACCRUAL_CRON_ENABLED=false (e.g. local dev or secondary instances).
 *
 * Enhancement 7 — Self-healing for missed months:
 *   maxCatchUpMonths is driven by LEAVE_ACCRUAL_MAX_CATCH_UP_MONTHS (default 3).
 *   If the cron was down for February and March, the April run will automatically
 *   credit all missed months (up to the configured cap) in a single pass.
 */

const cron = require('node-cron');
const { runLeaveMonthlyAccrual } = require('../services/leaveMonthlyAccrual');
const { broadcastAppEvent } = require('../websockets/appEvents');

/** Stable key for pg_try_advisory_lock (must not collide with other app locks). */
const ACCRUAL_CRON_ADVISORY_LOCK_KEY = 918273645;

/** Cron: minute hour day-of-month month day-of-week — 00:00 on the 1st, every month. */
const CRON_EXPRESSION = '0 0 1 * *';
const CRON_TIMEZONE = 'Asia/Manila';

/**
 * Enhancement 7 — How many missed months to catch up per cron tick.
 * Default: 3 (covers a quarterly server outage automatically).
 * Override via LEAVE_ACCRUAL_MAX_CATCH_UP_MONTHS env var.
 * Set to 1 to restore the old single-month behaviour.
 */
const CRON_MAX_CATCH_UP_MONTHS = Math.max(
  1,
  Math.min(
    120,
    parseInt(process.env.LEAVE_ACCRUAL_MAX_CATCH_UP_MONTHS || '3', 10) || 3
  )
);

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

function monthlyAccrualAffectedUserIds(result = {}) {
  return [
    ...new Set(
      (Array.isArray(result.details) ? result.details : [])
        .filter((item) => item.action === 'applied' || item.created_balance_row === true)
        .map((item) => item.user_id)
        .filter(Boolean)
        .map((id) => String(id))
    ),
  ];
}

function broadcastMonthlyAccrualResult(result) {
  if (!result || result.dryRun) return 0;
  const rowsUpdated = Number(result.rowsUpdated || 0);
  const missingBalanceRowsCreated = Number(result.missingBalanceRowsCreated || 0);
  if (rowsUpdated <= 0 && missingBalanceRowsCreated <= 0) return 0;

  const affectedUserIds = monthlyAccrualAffectedUserIds(result);
  if (affectedUserIds.length === 0) return 0;

  return broadcastAppEvent('leave_updated', {
    action: 'monthly_accrual',
    source: 'cron',
    requestId: null,
    leaveRequestId: null,
    userId: affectedUserIds[0],
    userIds: affectedUserIds,
    user_ids: affectedUserIds,
    status: null,
    updatedAt: new Date().toISOString(),
    targetYearMonth: result.targetYearMonth,
    rowsUpdated: result.rowsUpdated,
    rowsSkipped: result.rowsSkipped,
    missingBalanceRowsCreated,
    leaveTypes: result.leaveTypes,
    balanceChanged: true,
  });
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
            maxCatchUpMonths: CRON_MAX_CATCH_UP_MONTHS,
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
          const sent = broadcastMonthlyAccrualResult(result);
          if (sent > 0) {
            console.log(
              `[leaveMonthlyAccrual][cron] broadcast leave_updated monthly_accrual clients=${sent}`,
            );
          }
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
    `[leaveMonthlyAccrual][cron] scheduled expr="${CRON_EXPRESSION}" timezone=${CRON_TIMEZONE} (1st of month 00:00 Manila) maxCatchUpMonths=${CRON_MAX_CATCH_UP_MONTHS}`,
  );
  return task;
}

module.exports = {
  scheduleLeaveMonthlyAccrualCron,
  /** @internal for tests */
  manilaYearMonthNow,
  monthlyAccrualAffectedUserIds,
  broadcastMonthlyAccrualResult,
  CRON_EXPRESSION,
  CRON_TIMEZONE,
  CRON_MAX_CATCH_UP_MONTHS,
};
