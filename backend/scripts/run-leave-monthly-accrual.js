/**
 * CLI: run monthly leave accrual (Vacation + Sick, 1.25 days per month per type).
 *
 * Usage:
 *   node scripts/run-leave-monthly-accrual.js [--dry-run] [--target-month=YYYY-MM] [--max-catch-up=N]
 *
 * Requires DATABASE_URL or same env as the API (see src/config/db).
 */
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });

const { pool } = require('../src/config/db');
const { runLeaveMonthlyAccrual } = require('../src/services/leaveMonthlyAccrual');

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
  const result = await runLeaveMonthlyAccrual(pool, {
    dryRun,
    targetMonth,
    maxCatchUpMonths: Number.isFinite(maxCatchUpMonths) ? maxCatchUpMonths : undefined,
  });
  console.log(JSON.stringify(result, null, 2));
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
