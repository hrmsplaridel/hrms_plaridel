// Explicit opt-in: only a disposable schema in the LOCAL development database.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { randomUUID } = require('node:crypto');
const { runTool, databaseEnvironment } = require('../src/services/systemBackups');

test('real tools round-trip an isolated PostgreSQL schema and local upload archive', { skip: process.env.BACKUP_INTEGRATION !== '1' }, async () => {
  require('dotenv').config({ path: path.resolve(__dirname, '../.env'), quiet: true });
  const url = new URL(process.env.DATABASE_URL);
  assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(url.hostname), 'Only local development database is allowed');
  const { Client } = require('pg');
  const db = new Client({ connectionString: url.toString() }); await db.connect();
  const schema = `backup_test_${randomUUID().replaceAll('-', '')}`;
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hrms-backup-tools-'));
  const env = databaseEnvironment(url.toString());
  try {
    await db.query(`CREATE SCHEMA ${schema}`);
    await db.query(`CREATE TABLE ${schema}.probe (value text); INSERT INTO ${schema}.probe VALUES ('round-trip marker')`);
    const dump = path.join(root, 'test.dump');
    await runTool(process.env.PG_DUMP_PATH || 'pg_dump', ['--format=custom', '--no-password', `--schema=${schema}`, `--file=${dump}`], env);
    await runTool(process.env.PG_RESTORE_PATH || 'pg_restore', ['--list', dump], env);
    await db.query(`TRUNCATE ${schema}.probe`);
    // Restore table/data only into the disposable schema, never clean existing objects.
    await runTool(process.env.PG_RESTORE_PATH || 'pg_restore', ['--no-password', '--exit-on-error', '--data-only', '--dbname=' + url.pathname.slice(1), dump], { ...env, PGHOST: url.hostname, PGPORT: url.port, PGUSER: decodeURIComponent(url.username), PGPASSWORD: decodeURIComponent(url.password) });
    assert.equal((await db.query(`SELECT value FROM ${schema}.probe`)).rows[0].value, 'round-trip marker');
    const uploads = path.join(root, 'uploads'); const restored = path.join(root, 'restored');
    await fs.mkdir(uploads); await fs.mkdir(restored);
    await fs.writeFile(path.join(uploads, 'example.txt'), 'upload marker');
    const archive = path.join(root, 'uploads.tar.gz');
    const tar = process.env.BACKUP_TAR_PATH || 'tar';
    await runTool(tar, ['--create', '--gzip', `--file=${archive}`, '--directory', uploads, '--', '.'], process.env);
    await runTool(tar, ['--list', '--gzip', `--file=${archive}`], process.env);
    await runTool(tar, ['--extract', '--gzip', `--file=${archive}`, '--directory', restored], process.env);
    assert.equal(await fs.readFile(path.join(restored, 'example.txt'), 'utf8'), 'upload marker');
  } finally {
    await db.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await db.end(); await fs.rm(root, { recursive: true, force: true });
  }
});
