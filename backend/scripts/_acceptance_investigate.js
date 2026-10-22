'use strict';
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env.acceptance'), override: true });
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

(async () => {
  const ra = await pool.query(`
    SELECT id::text, email, full_name, status, created_at
    FROM recruitment_applications
    WHERE email ILIKE 'mayor-intake-%@local.intake'
       OR full_name ILIKE 'Disposable Accept%'
       OR full_name ILIKE '%Phase25%'
    ORDER BY created_at DESC
    LIMIT 20
  `);
  console.log('RA_MATCH', JSON.stringify(ra.rows, null, 2));

  const indep = await pool.query(`
    SELECT
      COUNT(*)::int AS total,
      COUNT(*) FILTER (WHERE application_id IS NULL)::int AS null_app,
      COUNT(*) FILTER (WHERE application_id IS NOT NULL)::int AS with_app
    FROM mayor_endorsement_requests
  `);
  console.log('MER_APP_STATS', indep.rows[0]);

  const withApp = await pool.query(`
    SELECT mer.reference_number, mer.application_id::text AS application_id,
           ra.email, ra.full_name, ra.status AS ra_status
    FROM mayor_endorsement_requests mer
    LEFT JOIN recruitment_applications ra ON ra.id = mer.application_id
    WHERE mer.application_id IS NOT NULL
  `);
  console.log('MER_WITH_APP', JSON.stringify(withApp.rows, null, 2));

  // Confirm operational still at 4
  const ops = new Pool({
    connectionString: process.env.DATABASE_URL.replace(
      '/hrms_plaridel_acceptance',
      '/hrms_plaridel',
    ),
  });
  const opsC = await ops.query('SELECT COUNT(*)::int AS c FROM mayor_endorsement_requests');
  console.log('OPS_MER_COUNT', opsC.rows[0]);
  await ops.end();
  await pool.end();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
