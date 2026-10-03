const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const bcrypt = require('bcrypt');
const { pool } = require('../src/config/db');

async function main() {
  const email = String(
    process.env.HRMS_SUPER_ADMIN_USERNAME || process.env.HRMS_SUPER_ADMIN_EMAIL || ''
  ).trim().toLowerCase();
  const password = process.env.HRMS_SUPER_ADMIN_PASSWORD || '';
  const name = String(process.env.HRMS_SUPER_ADMIN_NAME || 'System Administrator').trim();
  if ((email !== 'superadmin' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) || password.length < 12 || !name) {
    throw new Error('Set HRMS_SUPER_ADMIN_USERNAME=superadmin (or HRMS_SUPER_ADMIN_EMAIL), HRMS_SUPER_ADMIN_PASSWORD (12+ characters), and optionally HRMS_SUPER_ADMIN_NAME.');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const existing = await client.query(
      `SELECT id, email FROM users WHERE role = 'super_admin' FOR UPDATE`
    );
    if (existing.rowCount) {
      throw new Error(`A super-admin account already exists (${existing.rows[0].email}). Credentials were not changed.`);
    }
    const hash = await bcrypt.hash(password, 12);
    const inserted = await client.query(
      `INSERT INTO users (employee_number, email, password_hash, role, full_name,
                          is_active, employment_status, leave_credit_eligible)
       VALUES (NULL, $1, $2, 'super_admin', $3, true, 'active', false)
       RETURNING id, email`,
      [email, hash, name]
    );
    await client.query(
      `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
       VALUES ($1::uuid, 'super_admin_created', 'system_account', $1::uuid, $2)`,
      [inserted.rows[0].id, JSON.stringify({ email, source: 'bootstrap_script' })]
    );
    await client.query('COMMIT');
    console.log(`Created separate super-admin account: ${email}`);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
}).finally(() => pool.end());
