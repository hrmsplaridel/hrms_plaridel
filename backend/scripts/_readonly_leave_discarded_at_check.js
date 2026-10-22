/** Read-only: compare leave_requests.discarded_at on ops vs staging. No writes. */
'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { Pool } = require('pg');

function urlFor(dbName) {
  const u = new URL(process.env.DATABASE_URL);
  u.pathname = `/${dbName}`;
  return u.toString();
}

async function inspect(dbName) {
  const pool = new Pool({ connectionString: urlFor(dbName) });
  try {
    const col = await pool.query(`
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'leave_requests'
        AND column_name = 'discarded_at'
    `);
    const db = await pool.query('SELECT current_database() AS db');
    return {
      database: db.rows[0].db,
      has_discarded_at: col.rows.length > 0,
      column: col.rows[0] || null,
    };
  } finally {
    await pool.end();
  }
}

(async () => {
  const ops = await inspect('hrms_plaridel');
  let staging = null;
  try {
    staging = await inspect('hrms_plaridel_acceptance');
  } catch (e) {
    staging = { error: String(e.message || e) };
  }
  console.log(JSON.stringify({ ops, staging }, null, 2));
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
