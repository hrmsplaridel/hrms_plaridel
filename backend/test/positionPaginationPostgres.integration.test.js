'use strict';

const path = require('node:path');
const { randomUUID } = require('node:crypto');
const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const { withMockedModule } = require('./helpers/moduleMocks');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const hasDatabase = Boolean(process.env.DATABASE_URL);
const integrationTest = hasDatabase ? test : test.skip;
const schema = `position_page_test_${randomUUID().replaceAll('-', '')}`;
let adminPool;
let testPool;

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

async function invokeListRoute(query) {
  const restoreDb = withMockedModule('../src/config/db', { pool: testPool });
  const routePath = require.resolve('../src/routes/positions');
  delete require.cache[routePath];
  try {
    const router = require('../src/routes/positions');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/' && entry.route.methods.get
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const res = responseRecorder();
    await handler({ query, user: { role: 'admin' } }, res);
    return res;
  } finally {
    delete require.cache[routePath];
    restoreDb();
  }
}

test.before(async () => {
  if (!hasDatabase) return;
  adminPool = new Pool({ connectionString: process.env.DATABASE_URL });
  await adminPool.query(`CREATE SCHEMA ${schema}`);
  await adminPool.query(
    `CREATE TABLE ${schema}.departments (
       id uuid PRIMARY KEY,
       name text NOT NULL
     )`
  );
  await adminPool.query(
    `CREATE TABLE ${schema}.positions (
       id uuid PRIMARY KEY,
       position_number int,
       name text NOT NULL,
       description text,
       department_id uuid REFERENCES ${schema}.departments(id),
       is_active boolean NOT NULL DEFAULT true
     )`
  );
  await adminPool.query(
    `CREATE TABLE ${schema}.assignments (
       id uuid PRIMARY KEY,
       position_id uuid REFERENCES ${schema}.positions(id),
       is_active boolean NOT NULL DEFAULT true,
       effective_to date
     )`
  );
  await adminPool.query(
    `CREATE TABLE ${schema}.employee_other_positions (
       id uuid PRIMARY KEY,
       position_id uuid REFERENCES ${schema}.positions(id),
       is_active boolean NOT NULL DEFAULT true,
       effective_to date
     )`
  );
  await adminPool.query(
    `CREATE TABLE ${schema}.position_department_head_periods (
       id uuid PRIMARY KEY,
       position_id uuid REFERENCES ${schema}.positions(id),
       is_active boolean NOT NULL DEFAULT true,
       effective_from date NOT NULL,
       effective_to date,
       created_at timestamptz NOT NULL DEFAULT now()
     )`
  );

  testPool = new Pool({
    connectionString: process.env.DATABASE_URL,
    options: `-c search_path=${schema},public`,
  });

  const departmentId = randomUUID();
  await testPool.query(
    'INSERT INTO departments (id, name) VALUES ($1::uuid, $2)',
    [departmentId, 'Integration Human Resources']
  );
  for (let number = 1; number <= 15; number += 1) {
    await testPool.query(
      `INSERT INTO positions (
         id, position_number, name, description, department_id, is_active
       ) VALUES ($1::uuid, $2, $3, $4, $5::uuid, true)`,
      [
        randomUUID(),
        number,
        `Clerk ${String(number).padStart(2, '0')}`,
        `Integration position ${number}`,
        departmentId,
      ]
    );
  }
});

test.after(async () => {
  if (!hasDatabase) return;
  await testPool?.end();
  await adminPool.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
  await adminPool.end();
});

integrationTest('real PostgreSQL query returns stable pages and totals', async () => {
  const secondPage = await invokeListRoute({
    paginated: 'true',
    status: 'All',
    search: 'Clerk',
    page: '2',
    limit: '5',
  });

  assert.equal(secondPage.statusCode, 200);
  assert.deepEqual(secondPage.body.pagination, {
    page: 2,
    limit: 5,
    page_size: 5,
    total: 15,
    page_count: 3,
  });
  assert.deepEqual(
    secondPage.body.items.map((position) => position.name),
    ['Clerk 06', 'Clerk 07', 'Clerk 08', 'Clerk 09', 'Clerk 10']
  );

  const finalPage = await invokeListRoute({
    paginated: 'true',
    status: 'All',
    search: 'Clerk',
    page: '3',
    limit: '5',
  });
  assert.deepEqual(
    finalPage.body.items.map((position) => position.name),
    ['Clerk 11', 'Clerk 12', 'Clerk 13', 'Clerk 14', 'Clerk 15']
  );
});
