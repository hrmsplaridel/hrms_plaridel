require('dotenv').config();
const { pool } = require('../src/config/db');

(async () => {
  const t = await pool.query(`
    SELECT id, reference_number, status, meeting_request_status, appointment_status,
           staff_notes, submitted_at, endorsed_at
    FROM mayor_endorsement_requests
    WHERE reference_number LIKE 'MER-20261020-%'
       OR staff_notes ILIKE '%Phase 2.5%'
    ORDER BY submitted_at`);
  console.log('TEST', JSON.stringify(t.rows, null, 2));

  const leg = await pool.query(`
    SELECT id, reference_number, status, meeting_request_status, appointment_status
    FROM mayor_endorsement_requests
    WHERE appointment_status = 'scheduled'
      AND COALESCE(meeting_request_status, 'none') = 'none'`);
  console.log('LEGACY', JSON.stringify(leg.rows, null, 2));

  const all = await pool.query(`
    SELECT COUNT(*)::int AS n,
           COUNT(*) FILTER (WHERE status = 'endorsed')::int AS endorsed,
           COUNT(*) FILTER (WHERE status = 'pending')::int AS pending
    FROM mayor_endorsement_requests`);
  console.log('TOTALS', all.rows[0]);

  const cols = await pool.query(`
    SELECT column_name FROM information_schema.columns
    WHERE table_name = 'mayor_endorsement_requests'
    ORDER BY ordinal_position`);
  console.log('HAS_IS_TEST', cols.rows.some((r) => r.column_name === 'is_test'));
  await pool.end();
})().catch(async (e) => {
  console.error(e);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});
