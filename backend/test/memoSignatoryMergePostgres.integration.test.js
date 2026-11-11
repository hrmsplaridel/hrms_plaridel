'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {Client, Pool} = require('pg');
const {configureOfficialSignatory} = require('../src/services/officialSignatoryService');
const {resolveMemoSignatories} = require('../src/services/docutrackerDocumentBuilderService');

test('memo migration, concurrent distinct signers and inactive resolution in PostgreSQL', {
  skip: process.env.MERGE_MEMO_DB_TEST !== '1',
}, async () => {
  require('dotenv').config({path: path.join(__dirname, '../.env'), quiet: true});
  const url = new URL(process.env.DATABASE_URL);
  assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(url.hostname));
  assert.equal(url.port, '5433');
  assert.equal(url.pathname, '/hrms_plaridel');
  const schema = `memo_merge_test_${randomUUID().replaceAll('-', '')}`;
  assert.match(schema, /^memo_merge_test_[0-9a-f]{32}$/);
  const admin = new Client({connectionString: process.env.DATABASE_URL});
  const pool = new Pool({connectionString: process.env.DATABASE_URL,
    options: `-c search_path=${schema},public`, max: 3});
  const people = [randomUUID(), randomUUID(), randomUUID()];
  await admin.connect();
  try {
    await admin.query(`CREATE SCHEMA "${schema}"`);
    await admin.query(`SET search_path TO "${schema}", public`);
    await admin.query(`CREATE TABLE users (
      id uuid PRIMARY KEY, full_name text, role text DEFAULT 'employee',
      is_active boolean DEFAULT true, employment_status text DEFAULT 'active',
      date_hired date, separation_date date, created_at timestamptz DEFAULT now()
    ); CREATE TABLE departments (id uuid PRIMARY KEY, name text, is_active boolean);
    CREATE TABLE positions (id uuid PRIMARY KEY, name text);
    CREATE TABLE assignments (id uuid PRIMARY KEY, employee_id uuid,
      position_id uuid, department_id uuid, effective_from date, effective_to date,
      created_at timestamptz, is_active boolean);`);
    const init = fs.readFileSync(path.join(__dirname, '../scripts/init-schema.sql'), 'utf8');
    const definition = init.match(/CREATE TABLE IF NOT EXISTS docutracker_official_signatories \(([\s\S]*?)\n\);/i);
    assert.ok(definition);
    await admin.query(definition[0]);
    await admin.query(`ALTER TABLE docutracker_official_signatories DROP CONSTRAINT docutracker_official_signatories_role_check;
      ALTER TABLE docutracker_official_signatories ADD CONSTRAINT docutracker_official_signatories_role_check
      CHECK (role_key IN ('leave_credit_certifier','dtr_office_hours_verifier','dtr_hr_officer'));`);
    const migration = fs.readFileSync(path.join(__dirname,
      '../scripts/migrations/docutracker/migrate-docutracker-memo-official-signatories-v1.sql'), 'utf8')
      .replace(/^\s*(?:BEGIN|COMMIT);\s*$/gm, '');
    await admin.query(migration);
    const constraint = (await admin.query(`SELECT pg_get_constraintdef(oid) AS definition
      FROM pg_constraint WHERE conrelid='docutracker_official_signatories'::regclass
      AND conname='docutracker_official_signatories_role_check'`)).rows[0].definition;
    for (const role of ['leave_credit_certifier', 'dtr_office_hours_verifier', 'dtr_hr_officer',
      'memo_prepared_by', 'memo_noted_by', 'memo_approved_by']) assert.ok(constraint.includes(role));
    for (const person of people) await admin.query(
      'INSERT INTO users(id,full_name) VALUES($1,$2)', [person, 'Fixture official']);

    const input = {employeeId: people[0], effectiveFrom: '2026-11-10', actorId: null};
    const roles = ['memo_noted_by', 'memo_approved_by'];
    const results = await Promise.allSettled(roles.map((roleKey, index) =>
      configureOfficialSignatory(pool, {...input, roleKey,
        employeeId: index === 0 ? people[0].toUpperCase() : people[0]})));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    const rejected = results.find(r => r.status === 'rejected');
    assert.equal(rejected.reason.status, 400);
    assert.match(rejected.reason.message, /cannot be the same account/);
    assert.equal((await admin.query('SELECT count(*)::int AS n FROM docutracker_official_signatories')).rows[0].n, 1);

    const losingRole = roles[results.findIndex(r => r.status === 'rejected')];
    await configureOfficialSignatory(pool, {...input, roleKey: losingRole,
      effectiveFrom: '2026-11-01', effectiveTo: '2026-11-09'});
    await configureOfficialSignatory(pool, {...input, roleKey: losingRole, employeeId: people[1]});
    await configureOfficialSignatory(pool, {...input, roleKey: 'memo_prepared_by', employeeId: people[2]});
    assert.equal((await resolveMemoSignatories(pool, {document_type: 'memo'})).configuration.mode, 'configured');
    await admin.query('UPDATE users SET is_active=false WHERE id=$1', [people[0]]);
    const resolution = await resolveMemoSignatories(pool, {document_type: 'memo'});
    assert.equal(resolution.configuration.mode, 'automatic');
    assert.equal(resolution.configuration.missing.length, 1);
  } finally {
    await pool.end();
    await admin.query('SET search_path TO public');
    await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await admin.end();
  }
});
