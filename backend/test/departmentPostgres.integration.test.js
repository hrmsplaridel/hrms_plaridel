'use strict';

const path = require('node:path');
const { randomUUID } = require('node:crypto');
const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const {
  DEPARTMENT_DEPENDENCIES,
  deleteMistakenDepartment,
} = require('../src/services/departmentLifecycle');

const hasDatabase = Boolean(process.env.DATABASE_URL);
const integrationTest = hasDatabase ? test : test.skip;
const schema = `department_test_${randomUUID().replaceAll('-', '')}`;
let adminPool;
let testPool;

test.before(async () => {
  if (!hasDatabase) return;
  adminPool = new Pool({ connectionString: process.env.DATABASE_URL });
  await adminPool.query(`CREATE SCHEMA ${schema}`);
  await adminPool.query(`CREATE SEQUENCE ${schema}.departments_department_number_seq`);
  await adminPool.query(
    `CREATE TABLE ${schema}.departments (
       id uuid PRIMARY KEY,
       department_number int UNIQUE NOT NULL DEFAULT
         nextval('${schema}.departments_department_number_seq'::regclass),
       name text NOT NULL UNIQUE,
       description text,
       is_active boolean NOT NULL DEFAULT true,
       created_at timestamptz NOT NULL DEFAULT now(),
       updated_at timestamptz NOT NULL DEFAULT now()
     )`
  );
  await adminPool.query(
    `CREATE TABLE ${schema}.audit_logs (
       id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
       user_id uuid,
       action text NOT NULL,
       entity_type text NOT NULL,
       entity_id uuid,
       details text,
       created_at timestamptz NOT NULL DEFAULT now()
     )`
  );
  for (const { table, column } of DEPARTMENT_DEPENDENCIES) {
    await adminPool.query(
      `CREATE TABLE ${schema}.${table} (
         id uuid PRIMARY KEY,
         ${column} uuid REFERENCES ${schema}.departments(id) ON DELETE RESTRICT
       )`
    );
  }
  testPool = new Pool({
    connectionString: process.env.DATABASE_URL,
    options: `-c search_path=${schema},public`,
  });
});

test.after(async () => {
  if (!hasDatabase) return;
  await testPool?.end();
  await adminPool.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
  await adminPool.end();
});

integrationTest('real foreign keys and lifecycle checks preserve used departments', async () => {
  const departmentId = randomUUID();
  const dependencyId = randomUUID();
  await testPool.query(
    'INSERT INTO departments (id, name) VALUES ($1::uuid, $2)',
    [departmentId, 'Integration Finance']
  );
  await testPool.query(
    'INSERT INTO positions (id, department_id) VALUES ($1::uuid, $2::uuid)',
    [dependencyId, departmentId]
  );

  await assert.rejects(
    testPool.query('DELETE FROM departments WHERE id = $1::uuid', [departmentId]),
    /violates RESTRICT setting of foreign key constraint/i
  );

  const client = await testPool.connect();
  try {
    await client.query('BEGIN');
    await assert.rejects(
      deleteMistakenDepartment(client, {
        actorId: null,
        departmentId,
        reason: 'Integration test',
      }),
      /positions/i
    );
    await client.query('ROLLBACK');
  } finally {
    client.release();
  }
  const remaining = await testPool.query(
    'SELECT 1 FROM departments WHERE id = $1::uuid',
    [departmentId]
  );
  assert.equal(remaining.rowCount, 1);

  await testPool.query('DELETE FROM positions WHERE id = $1::uuid', [dependencyId]);
  const deleteClient = await testPool.connect();
  try {
    await deleteClient.query('BEGIN');
    await deleteMistakenDepartment(deleteClient, {
      actorId: null,
      departmentId,
      reason: 'Integration test cleanup',
    });
    await deleteClient.query('COMMIT');
  } catch (error) {
    await deleteClient.query('ROLLBACK');
    throw error;
  } finally {
    deleteClient.release();
  }
  const deleted = await testPool.query(
    'SELECT 1 FROM departments WHERE id = $1::uuid',
    [departmentId]
  );
  const audit = await testPool.query(
    `SELECT action FROM audit_logs
      WHERE entity_id = $1::uuid`,
    [departmentId]
  );
  assert.equal(deleted.rowCount, 0);
  assert.equal(audit.rows[0].action, 'department_mistake_deleted');
});

integrationTest('concurrent inserts receive distinct sequence numbers', async () => {
  const inserts = await Promise.all([
    testPool.query(
      'INSERT INTO departments (id, name) VALUES ($1::uuid, $2) RETURNING department_number',
      [randomUUID(), 'Concurrent Legal']
    ),
    testPool.query(
      'INSERT INTO departments (id, name) VALUES ($1::uuid, $2) RETURNING department_number',
      [randomUUID(), 'Concurrent Tourism']
    ),
  ]);
  const numbers = inserts.map((result) => result.rows[0].department_number);

  assert.equal(new Set(numbers).size, 2);
  assert.equal(numbers.every((number) => Number.isInteger(number)), true);
});
