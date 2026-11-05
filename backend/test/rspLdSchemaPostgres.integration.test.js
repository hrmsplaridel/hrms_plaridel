const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

test('RSP/L&D initializer and upgrades agree; access reads preserve denials in PostgreSQL', {
  skip: process.env.RSP_LD_DB_TEST !== '1',
}, async () => {
  require('dotenv').config({ path: path.join(__dirname, '../.env'), quiet: true });
  const url = new URL(process.env.DATABASE_URL);
  assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(url.hostname), 'Local database only');
  const { Pool } = require('pg');
  const { buildPoolOptions } = require('../src/config/databasePoolOptions');
  const pool = new Pool(buildPoolOptions());
  const db = await pool.connect();
  const schema = `rspld_audit_${randomUUID().replaceAll('-', '')}`;
  try {
    await db.query('BEGIN');
    await db.query(`CREATE SCHEMA "${schema}"`);
    await db.query(`SET LOCAL search_path TO "${schema}", public`);
    await db.query('CREATE TABLE users(id uuid PRIMARY KEY, role text)');
    const existing = randomUUID(), newcomer = randomUUID();
    await db.query("INSERT INTO users VALUES($1,'admin')", [existing]);
    const init = fs.readFileSync(path.join(__dirname, '../scripts/init-schema.sql'), 'utf8');
    const recycle = fs.readFileSync(path.join(__dirname, '../scripts/migrations/20261103_rsp_ld_recycle_bin.sql'), 'utf8');
    const tables = [...recycle.matchAll(/ALTER TABLE public\.(\w+)/g)].map(match => match[1]);
    for (const table of ['rsp_admin_access', 'ld_admin_access', ...tables]) {
      const definition = init.match(new RegExp(`CREATE TABLE IF NOT EXISTS ${table} \\(([\\s\\S]*?)\\n\\);`));
      assert.ok(definition, table);
      await db.query(definition[0]);
    }
    const columns = async table => (await db.query(
      'SELECT column_name,column_default,is_nullable,data_type FROM information_schema.columns WHERE table_schema=$1 AND table_name=$2 ORDER BY column_name',
      [schema, table],
    )).rows;
    const fresh = { rsp: await columns('rsp_admin_access'), ld: await columns('ld_admin_access') };
    await db.query('DROP TABLE rsp_admin_access, ld_admin_access');
    for (const table of tables) await db.query(`ALTER TABLE "${table}" DROP COLUMN deleted_at`);
    for (const file of ['20261101_rsp_ld_admin_access.sql', '20261101_rsp_ld_granular_permissions.sql', '20261103_rsp_ld_recycle_bin.sql']) {
      const sql = fs.readFileSync(path.join(__dirname, '../scripts/migrations', file), 'utf8')
        .replace(/^BEGIN;\s*$/gm, '').replace(/^COMMIT;\s*$/gm, '')
        .replaceAll('public.', `"${schema}".`);
      await db.query(sql);
    }
    assert.deepEqual(await columns('rsp_admin_access'), fresh.rsp);
    assert.deepEqual(await columns('ld_admin_access'), fresh.ld);
    for (const table of tables) assert.ok((await columns(table)).some(col => col.column_name === 'deleted_at'));
    await db.query("INSERT INTO users VALUES($1,'admin')", [newcomer]);
    // Simulate a saved explicit denial while retaining a legacy parent flag.
    await db.query('UPDATE rsp_admin_access SET form_bi_allowed=false,form_applicants_profile_allowed=false,form_selection_lineup_allowed=false,form_computation_of_points_allowed=false,form_work_experience_allowed=false,form_turn_around_time_allowed=false,form_ojt_allowed=false WHERE admin_user_id=$1', [existing]);
    const { rspAdminAccess, ldAdminAccess } = require('../src/services/moduleAdminAccess');
    assert.equal(rspAdminAccess.anyAllowed(await rspAdminAccess.loadAccess(newcomer, db)), false);
    assert.equal(ldAdminAccess.anyAllowed(await ldAdminAccess.loadAccess(newcomer, db)), false);
    assert.equal((await rspAdminAccess.loadAccess(existing, db)).form_bi_allowed, false);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM rsp_admin_access')).rows[0].n, 1);
  } finally {
    // The schema, fixture accounts and all DDL are rolled back together.
    await db.query('ROLLBACK');
    db.release();
    await pool.end();
  }
});
