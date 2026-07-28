/**
 * CLI: run completed-month leave processing.
 * Credits Vacation/Sick Leave first, then posts the month's DTR equivalent-day
 * deduction to Vacation Leave.
 *
 * Usage:
 *   node scripts/run-leave-monthly-accrual.js [--dry-run] [--target-month=YYYY-MM] [--max-catch-up=N]
 *
 * Requires DATABASE_URL or same env as the API (see src/config/db).
 */
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });

const { pool } = require('../src/config/db');
const { runLeaveMonthlyAccrual } = require('../src/services/leaveMonthlyAccrual');
const {
  runMonthlyAttendanceDeductions,
} = require('../src/services/leaveAttendanceDeduction');

function parseArgs() {
  const argv = process.argv.slice(2);
  const dryRun = argv.includes('--dry-run');
  let targetMonth;
  let maxCatchUpMonths;
  for (const a of argv) {
    if (a.startsWith('--target-month=')) {
      targetMonth = a.split('=')[1];
    }
    if (a.startsWith('--max-catch-up=')) {
      maxCatchUpMonths = parseInt(a.split('=')[1], 10);
    }
  }
  return { dryRun, targetMonth, maxCatchUpMonths };
}

async function main() {
  const { dryRun, targetMonth, maxCatchUpMonths } = parseArgs();
  const accrualResult = await runLeaveMonthlyAccrual(pool, {
    dryRun,
    targetMonth,
    maxCatchUpMonths: Number.isFinite(maxCatchUpMonths) ? maxCatchUpMonths : undefined,
  });
  const previewEarnedByUser = new Map();
  if (dryRun) {
    for (const detail of accrualResult.details || []) {
      if (
        detail.leave_type === 'vacationLeave' &&
        detail.action === 'would_apply'
      ) {
        const key = String(detail.user_id);
        previewEarnedByUser.set(
          key,
          (previewEarnedByUser.get(key) || 0) + Number(detail.days_added || 0)
        );
      }
    }
  }
  const attendanceDeductions = await runMonthlyAttendanceDeductions(pool, {
    dryRun,
    targetMonth: accrualResult.targetYearMonth,
    balanceEarnedAdjustmentsByUser: previewEarnedByUser,
  });
  const result = { ...accrualResult, attendanceDeductions };
  console.log(JSON.stringify(result, null, 2));
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
