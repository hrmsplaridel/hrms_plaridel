/**
 * Schedules completed-month leave processing using the shared services.
 * Cron: 1st and 15th of every month at 00:00 Asia/Manila.
 * Both runs target the month that just ended; they never advance the new month.
 * The 1st is the initial posting and the 15th is a full reconciliation.
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
const {
  runMonthlyAttendanceDeductions,
} = require('../services/leaveAttendanceDeduction');
const { broadcastAppEvent } = require('../websockets/appEvents');

/** Stable key for pg_try_advisory_lock (must not collide with other app locks). */
const ACCRUAL_CRON_ADVISORY_LOCK_KEY = 918273645;

/** Initial posting: 00:00 on the 1st, every month. */
const CRON_EXPRESSION = '0 0 1 * *';
/** Full reconciliation: 00:00 on the 15th, every month. */
const RECONCILIATION_CRON_EXPRESSION = '0 0 15 * *';
const CRON_TIMEZONE = 'Asia/Manila';
const DEFAULT_STARTUP_RECOVERY_DELAY_MS = 15_000;
const MONTH_END_SCHEDULES = Object.freeze([
  Object.freeze({ runKind: 'initial', expression: CRON_EXPRESSION }),
  Object.freeze({
    runKind: 'reconciliation',
    expression: RECONCILIATION_CRON_EXPRESSION,
  }),
]);

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

function startupRecoveryDelayMs(value = process.env.LEAVE_ACCRUAL_STARTUP_RECOVERY_DELAY_MS) {
  if (value == null || String(value).trim() === '') {
    return DEFAULT_STARTUP_RECOVERY_DELAY_MS;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return DEFAULT_STARTUP_RECOVERY_DELAY_MS;
  return Math.max(0, Math.min(300_000, Math.trunc(parsed)));
}

/**
 * Calendar year-month in Asia/Manila as YYYY-MM.
 */
function manilaYearMonthNow(now = new Date()) {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: CRON_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
  });
  const parts = fmt.formatToParts(now);
  const y = parts.find((p) => p.type === 'year')?.value;
  const m = parts.find((p) => p.type === 'month')?.value;
  if (!y || !m) {
    throw new Error('manilaYearMonthNow: could not resolve YYYY-MM');
  }
  return `${y}-${m}`;
}

/** Previous completed Manila calendar month as YYYY-MM. */
function manilaCompletedYearMonthNow(now = new Date()) {
  const current = manilaYearMonthNow(now);
  const [year, month] = current.split('-').map((value) => parseInt(value, 10));
  const completed = new Date(year, month - 2, 1);
  return `${completed.getFullYear()}-${String(completed.getMonth() + 1).padStart(2, '0')}`;
}

function monthlyAccrualAffectedUserIds(result = {}) {
  const attendanceDetails = Array.isArray(result.attendanceDeductions?.details)
    ? result.attendanceDeductions.details
    : [];
  return [
    ...new Set(
      [
        ...(Array.isArray(result.details) ? result.details : []),
        ...attendanceDetails,
      ]
        .filter(
          (item) =>
            item.action === 'applied' ||
            item.action === 'adjusted' ||
            item.created_balance_row === true ||
            Number(item.balance_delta || 0) !== 0
        )
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
  const attendanceRowsUpdated = Number(
    result.attendanceDeductions?.rowsUpdated || 0
  );
  if (
    rowsUpdated <= 0 &&
    missingBalanceRowsCreated <= 0 &&
    attendanceRowsUpdated <= 0
  ) {
    return 0;
  }

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
    attendanceRowsUpdated,
    attendanceDeductedDays:
      result.attendanceDeductions?.totalDeductedDays || 0,
    attendanceWithoutPayDays:
      result.attendanceDeductions?.totalWithoutPayDays || 0,
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
async function runScheduledCompletedMonthEnd(
  pool,
  {
    runKind = 'initial',
    now = new Date(),
    accrualRunner = runLeaveMonthlyAccrual,
    attendanceRunner = runMonthlyAttendanceDeductions,
    resultBroadcaster = broadcastMonthlyAccrualResult,
  } = {}
) {
  const startedAt = now instanceof Date ? now.toISOString() : new Date(now).toISOString();
  const ym = manilaCompletedYearMonthNow(now);
  console.log(
    `[leaveMonthlyAccrual][cron][${runKind}] tick start at=${startedAt} completedTargetMonth=${ym} tz=${CRON_TIMEZONE}`,
  );

  let completedResult = null;
  const lockResult = await withAccrualAdvisoryLock(pool, async () => {
    const accrualResult = await accrualRunner(pool, {
      dryRun: false,
      maxCatchUpMonths: CRON_MAX_CATCH_UP_MONTHS,
      targetMonth: ym,
    });
    const attendanceDeductions = await attendanceRunner(pool, {
      dryRun: false,
      targetMonth: ym,
    });
    completedResult = {
      ...accrualResult,
      attendanceDeductions,
      runKind,
    };
    console.log(
      `[leaveMonthlyAccrual][cron][${runKind}] success`,
      JSON.stringify({
        at: new Date().toISOString(),
        runKind,
        targetYearMonth: completedResult.targetYearMonth,
        rowsUpdated: completedResult.rowsUpdated,
        rowsSkipped: completedResult.rowsSkipped,
        dryRun: completedResult.dryRun,
        rate: completedResult.rate,
        leaveTypes: completedResult.leaveTypes,
        attendanceRowsUpdated: attendanceDeductions.rowsUpdated,
        attendanceDeductedDays: attendanceDeductions.totalDeductedDays,
        attendanceWithoutPayDays: attendanceDeductions.totalWithoutPayDays,
      }),
    );
    const sent = resultBroadcaster(completedResult);
    if (sent > 0) {
      console.log(
        `[leaveMonthlyAccrual][cron][${runKind}] broadcast leave_updated monthly_accrual clients=${sent}`,
      );
    }
  });

  if (lockResult && !lockResult.ran) {
    console.log(
      `[leaveMonthlyAccrual][cron][${runKind}] skipped (${lockResult.reason}); another instance may be running`,
    );
  }
  return {
    ...lockResult,
    runKind,
    targetYearMonth: ym,
    result: completedResult,
  };
}

/**
 * Reconciles the latest completed month shortly after the API starts. This
 * recovers a cron tick missed while the backend was offline without delaying
 * server startup. The shared runner remains protected by the PostgreSQL
 * advisory lock and its month-level idempotency safeguards.
 */
function scheduleLeaveMonthlyAccrualStartupRecovery(
  pool,
  {
    enabled = process.env.LEAVE_ACCRUAL_STARTUP_RECOVERY_ENABLED !== 'false',
    delayMs = startupRecoveryDelayMs(),
    timerScheduler = setTimeout,
    recoveryRunner = runScheduledCompletedMonthEnd,
  } = {}
) {
  if (!enabled) {
    console.log(
      '[leaveMonthlyAccrual][startup_recovery] disabled ' +
        '(LEAVE_ACCRUAL_STARTUP_RECOVERY_ENABLED=false)',
    );
    return null;
  }

  const safeDelayMs = startupRecoveryDelayMs(delayMs);
  const timer = timerScheduler(async () => {
    try {
      const recovery = await recoveryRunner(pool, {
        runKind: 'startup_recovery',
      });
      console.log(
        '[leaveMonthlyAccrual][startup_recovery] completed',
        JSON.stringify({
          ran: recovery?.ran === true,
          reason: recovery?.reason || null,
          targetYearMonth: recovery?.targetYearMonth || null,
        }),
      );
    } catch (err) {
      console.error(
        '[leaveMonthlyAccrual][startup_recovery] error',
        err && err.stack ? err.stack : err,
      );
    }
  }, safeDelayMs);
  if (timer && typeof timer.unref === 'function') timer.unref();
  console.log(
    `[leaveMonthlyAccrual][startup_recovery] scheduled delayMs=${safeDelayMs}`,
  );
  return timer;
}

function scheduleLeaveMonthlyAccrualCron(pool) {
  if (process.env.LEAVE_ACCRUAL_CRON_ENABLED === 'false') {
    console.log(
      '[leaveMonthlyAccrual][cron] disabled (LEAVE_ACCRUAL_CRON_ENABLED=false)',
    );
    return null;
  }

  const tasks = {};
  for (const schedule of MONTH_END_SCHEDULES) {
    tasks[schedule.runKind] = cron.schedule(
      schedule.expression,
      async () => {
        try {
          await runScheduledCompletedMonthEnd(pool, {
            runKind: schedule.runKind,
          });
        } catch (err) {
          console.error(
            `[leaveMonthlyAccrual][cron][${schedule.runKind}] error`,
            err && err.stack ? err.stack : err,
          );
        }
      },
      {
        timezone: CRON_TIMEZONE,
      },
    );
    console.log(
      `[leaveMonthlyAccrual][cron] scheduled kind=${schedule.runKind} expr="${schedule.expression}" timezone=${CRON_TIMEZONE} maxCatchUpMonths=${CRON_MAX_CATCH_UP_MONTHS}`,
    );
  }
  tasks.startupRecovery = scheduleLeaveMonthlyAccrualStartupRecovery(pool);
  return tasks;
}

module.exports = {
  scheduleLeaveMonthlyAccrualCron,
  /** @internal for tests */
  manilaYearMonthNow,
  manilaCompletedYearMonthNow,
  runScheduledCompletedMonthEnd,
  scheduleLeaveMonthlyAccrualStartupRecovery,
  monthlyAccrualAffectedUserIds,
  broadcastMonthlyAccrualResult,
  CRON_EXPRESSION,
  RECONCILIATION_CRON_EXPRESSION,
  MONTH_END_SCHEDULES,
  CRON_TIMEZONE,
  CRON_MAX_CATCH_UP_MONTHS,
  DEFAULT_STARTUP_RECOVERY_DELAY_MS,
  startupRecoveryDelayMs,
};
