/**
 * One-shot admin backfill: fill empty automatic RSP/L&D signature slots.
 * Usage: node scripts/reResolveSourceSignatures.js [rsp|ld]
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { pool } = require('../src/config/db');
const {
  reResolveAutomaticSourceSignatures,
} = require('../src/services/docutrackerRspSignatureService');

async function main() {
  const moduleArg = process.argv[2] || null;
  const admin = await pool.query(
    `SELECT id, role, full_name
     FROM users
     WHERE lower(role) = 'admin' AND is_active = true
     ORDER BY created_at ASC NULLS LAST
     LIMIT 1`
  );
  if (!admin.rowCount) {
    throw new Error('No active admin user found to run backfill');
  }
  const user = admin.rows[0];
  console.log(
    `Running re-resolve as ${user.full_name || user.id}` +
      (moduleArg ? ` (module=${moduleArg})` : ' (rsp+ld)')
  );
  const summary = await reResolveAutomaticSourceSignatures(pool, user, moduleArg);
  console.log(JSON.stringify(summary, null, 2));
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await pool.end();
    } catch (_) {}
  });
