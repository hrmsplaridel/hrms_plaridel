const test = require('node:test');
const assert = require('node:assert/strict');
const {Pool} = require('pg');
const {buildPoolOptions} = require('../src/config/databasePoolOptions');

const enabled = process.env.RUN_DB_TIMEOUT_TESTS === '1';
test('local PostgreSQL cancels slow SQL, rolls back and reuses the connection', {skip: !enabled}, async () => {
  require('dotenv').config({quiet:true});
  const url = new URL(process.env.DATABASE_URL);
  assert.ok(['localhost','127.0.0.1'].includes(url.hostname) && url.port === '5433' && url.pathname === '/hrms_plaridel', 'Unexpected database target');
  const pool = new Pool({...buildPoolOptions({...process.env, PG_STATEMENT_TIMEOUT_MS: '100'}), max: 1});
  const client = await pool.connect();
  try {
    const setting = await client.query("SELECT setting::int AS ms FROM pg_settings WHERE name='statement_timeout'");
    assert.ok(setting.rows[0].ms > 0 && setting.rows[0].ms <= 100);
    await client.query('BEGIN');
    await client.query('CREATE TEMP TABLE timeout_rollback_check (value integer) ON COMMIT DROP');
    await client.query('INSERT INTO timeout_rollback_check VALUES (1)');
    await assert.rejects(client.query('SELECT pg_sleep(0.3)'), {code: '57014'});
    await client.query('ROLLBACK');
    const missing = await client.query("SELECT to_regclass('pg_temp.timeout_rollback_check') AS table_name");
    assert.equal(missing.rows[0].table_name, null);
  } finally {client.release();}
  try {
    assert.equal((await pool.query('SELECT 42 AS answer')).rows[0].answer, 42);
    assert.equal(pool.waitingCount, 0);
    assert.equal(pool.idleCount, 1);
    await assert.rejects(pool.query('SELECT pg_sleep(0.3)'), {code: '57014'});
    assert.equal((await pool.query('SELECT 43 AS answer')).rows[0].answer, 43);
  } finally {await pool.end();}

  const stricter = new Pool({...buildPoolOptions({...process.env, PG_STATEMENT_TIMEOUT_MS: '100'}), options: '-c statement_timeout=50'});
  try {
    assert.equal((await stricter.query("SELECT setting::int AS ms FROM pg_settings WHERE name='statement_timeout'")).rows[0].ms, 50);
  } finally {await stricter.end();}
});
