/**
 * Year-end Mandatory/Forced Leave auto-deduction scheduler.
 *
 * Cron: Jan 1 at 00:01 Asia/Manila — runs once per year to automatically
 * apply forced leave deductions for employees who did not take the required
 * 5 working days during the previous calendar year.
 *
 * Multi-instance safe: uses PostgreSQL pg_try_advisory_lock so only one
 * worker runs per trigger (key 918273646, distinct from monthly accrual).
 *
 * Disable with YEAR_END_FORCED_LEAVE_CRON_ENABLED=false.
 */

const cron = require('node-cron');
const {
  applyYearEndForcedLeaveDeductions,
  manilaYearNow,
  CRON_ADVISORY_LOCK_KEY,
} = require('../services/leaveYearEndForcedLeave');
const { broadcastAppEvent } = require('../websockets/appEvents');

/** Jan 1 at 00:01 Asia/Manila */
const CRON_EXPRESSION = '1 0 1 1 *';
const CRON_TIMEZONE = 'Asia/Manila';

async function withAdvisoryLock(pool, fn) {
  const client = await pool.connect();
  try {
    const { rows } = await client.query(
      'SELECT pg_try_advisory_lock($1::bigint) AS got',
      [CRON_ADVISORY_LOCK_KEY],
    );
    if (!rows[0]?.got) return { ran: false, reason: 'advisory_lock_not_acquired' };
    try {
      await fn();
      return { ran: true };
    } finally {
      await client.query('SELECT pg_advisory_unlock($1::bigint)', [CRON_ADVISORY_LOCK_KEY]);
    }
  } finally {
    client.release();
  }
}

async function runYearEndForcedLeaveJob(pool) {
  // Deduct for the PREVIOUS calendar year (the year that just ended)
  const year = manilaYearNow() - 1;
  console.log(`[YearEndForcedLeave] Running auto-deduction for year ${year}`);

  const result = await applyYearEndForcedLeaveDeductions(pool, {
    year,
    actorUserId: null, // system-triggered
    dryRun: false,
    remarks: `Auto year-end deduction — unused mandatory/forced leave for ${year}`,
  });

  const { summary } = result;
  console.log(
    `[YearEndForcedLeave] Done year=${year}:`,
    `applied=${summary.applied}`,
    `already_deducted=${summary.already_deducted}`,
    `compliant=${summary.compliant}`,
    `insufficient_balance=${summary.insufficient_balance}`,
    `errors=${summary.errors}`,
  );

  if (summary.applied > 0) {
    broadcastAppEvent('leave_updated', {
      action: 'forced_leave_deduction',
      source: 'year_end_cron',
      year,
      applied: summary.applied,
    });
  }

  return result;
}

function scheduleYearEndForcedLeaveCron(pool) {
  const enabled = process.env.YEAR_END_FORCED_LEAVE_CRON_ENABLED !== 'false';
  if (!enabled) {
    console.log('[YearEndForcedLeave] Cron disabled via YEAR_END_FORCED_LEAVE_CRON_ENABLED=false');
    return;
  }

  cron.schedule(
    CRON_EXPRESSION,
    async () => {
      console.log('[YearEndForcedLeave] Cron tick — Jan 1 auto-deduction');
      try {
        await withAdvisoryLock(pool, () => runYearEndForcedLeaveJob(pool));
      } catch (err) {
        console.error('[YearEndForcedLeave] Cron error:', err);
      }
    },
    { timezone: CRON_TIMEZONE },
  );

  console.log(
    `[YearEndForcedLeave] Cron scheduled: "${CRON_EXPRESSION}" (${CRON_TIMEZONE}) — runs Jan 1 at 00:01`,
  );
}

module.exports = { scheduleYearEndForcedLeaveCron, runYearEndForcedLeaveJob };
