'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

// Opt-in: use a disposable test database, never the application's live schema.
test('migration preserves audit ink but invalidates it on correction, return and revocation', {
  skip: !process.env.LOCATOR_SIGNATURE_TEST_DATABASE_URL,
}, async () => {
  const db = new Client({ connectionString: process.env.LOCATOR_SIGNATURE_TEST_DATABASE_URL });
  const schema = `locator_signature_test_${randomUUID().replaceAll('-', '')}`;
  await db.connect();
  try {
    await db.query(`CREATE SCHEMA ${schema}`);
    await db.query(`SET search_path TO ${schema}, public`);
    await db.query(`
      CREATE FUNCTION ${schema}.uuid_generate_v4() RETURNS uuid
        LANGUAGE sql AS 'SELECT gen_random_uuid()';
      CREATE TABLE users (id uuid PRIMARY KEY);
      CREATE TABLE docutracker_signature_assets (id uuid PRIMARY KEY);
      CREATE TABLE locator_slips (
        id uuid PRIMARY KEY, employee_id uuid, department_id uuid,
        slip_date date, office text, reason text, request_type text,
        am_in boolean, am_out boolean, pm_in boolean, pm_out boolean,
        attachment_path text, attachment_uploaded_at timestamptz, status text
      );
    `);
    const migration = fs.readFileSync(path.join(__dirname, '../scripts/migrations/dtr/20261001_locator_signatures.sql'), 'utf8');
    await db.query(migration);
    const request = randomUUID();
    const signer = randomUUID();
    const asset = randomUUID();
    await db.query('INSERT INTO users VALUES ($1)', [signer]);
    await db.query('INSERT INTO docutracker_signature_assets VALUES ($1)', [asset]);
    await db.query("INSERT INTO locator_slips (id, employee_id, office, status) VALUES ($1, $2, 'Original', 'pending_department_head')", [request, signer]);
    await db.query(`INSERT INTO docutracker_locator_signatures
      (locator_slip_id, revision, slot_key, signature_asset_id, signed_by, signer_name_snapshot)
      VALUES ($1, 1, 'department_head', $2, $3, 'Head')`, [request, asset, signer]);
    const update = async (sql) => Number((await db.query(`${sql} WHERE id = $1 RETURNING signature_revision`, [request])).rows[0].signature_revision);
    assert.equal(await update("UPDATE locator_slips SET status = 'pending_hr'"), 1);
    assert.equal(await update("UPDATE locator_slips SET status = 'approved'"), 1);
    assert.equal(await update("UPDATE locator_slips SET status = 'returned_for_correction'"), 2);
    assert.equal(await update("UPDATE locator_slips SET office = 'Corrected'"), 3);
    assert.equal(await update("UPDATE locator_slips SET status = 'pending_department_head'"), 3);
    assert.equal(await update("UPDATE locator_slips SET attachment_path = 'replacement.pdf'"), 4);
    assert.equal(await update("UPDATE locator_slips SET status = 'revoked'"), 5);
    await db.query(migration);
    assert.equal((await db.query('SELECT revision FROM docutracker_locator_signatures')).rows[0].revision, 1);
    assert.equal((await db.query(`SELECT count(*)::int AS count FROM docutracker_locator_signatures s
      JOIN locator_slips ls ON ls.id = s.locator_slip_id AND ls.signature_revision = s.revision`)).rows[0].count, 0);
  } finally {
    await db.query('ROLLBACK');
    await db.query('SET search_path TO public');
    await db.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await db.end();
  }
});
