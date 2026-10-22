'use strict';
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
(async () => {
  const r = await pool.query(`
    SELECT reference_number, status, meeting_request_status, appointment_status,
           COALESCE(is_test,false) AS is_test,
           COALESCE(applicant_full_name, '') AS name,
           to_char(submitted_at AT TIME ZONE 'Asia/Manila', 'YYYY-MM-DD HH24:MI') AS submitted_manila
    FROM mayor_endorsement_requests
    ORDER BY submitted_at DESC
    LIMIT 12
  `);
  console.log(JSON.stringify({ db: (await pool.query('select current_database() d')).rows[0].d, rows: r.rows }, null, 2));
  await pool.end();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
