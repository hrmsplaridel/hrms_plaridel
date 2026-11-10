// Explicit opt-in: only a disposable schema in the LOCAL development database.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { randomUUID } = require('node:crypto');
const { BackupService, runTool, databaseEnvironment } = require('../src/services/systemBackups');
const { copyEncryptedBackup } = require('../scripts/copy-encrypted-backup');

test('real tools round-trip an isolated PostgreSQL schema and local upload archive', { skip: process.env.BACKUP_INTEGRATION !== '1' }, async () => {
  require('dotenv').config({ path: path.resolve(__dirname, '../.env'), quiet: true });
  const url = new URL(process.env.DATABASE_URL);
  assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(url.hostname), 'Only local development database is allowed');
  const { Client } = require('pg');
  const db = new Client({ connectionString: url.toString() }); await db.connect();
  const schema = `backup_test_${randomUUID().replaceAll('-', '')}`;
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hrms-backup-tools-'));
  const env = databaseEnvironment(url.toString());
  const age = process.env.BACKUP_AGE_PATH || 'age';
  const keygen = process.env.BACKUP_AGE_KEYGEN_PATH || path.join(path.dirname(age), process.platform === 'win32' ? 'age-keygen.exe' : 'age-keygen');
  try {
    const identity = path.join(root, 'test-key.txt');
    await runTool(keygen, ['--output', identity], process.env);
    const recipient = (await fs.readFile(identity, 'utf8')).match(/^# public key: (age1\S+)$/m)?.[1];
    assert.ok(recipient, 'Disposable public recovery key was generated');
    await db.query(`CREATE SCHEMA ${schema}`);
    await db.query(`CREATE TABLE ${schema}.probe (value text); INSERT INTO ${schema}.probe VALUES ('round-trip marker')`);
    const dump = path.join(root, 'test.dump');
    await runTool(process.env.PG_DUMP_PATH || 'pg_dump', ['--format=custom', '--no-password', `--schema=${schema}`, `--file=${dump}`], env);
    await runTool(process.env.PG_RESTORE_PATH || 'pg_restore', ['--list', dump], env);
    await runTool(age, ['--encrypt', '--recipient', recipient, '--output', `${dump}.age`, dump], process.env);
    const recoveredDump = path.join(root, 'recovered.dump');
    await runTool(age, ['--decrypt', '--identity', identity, '--output', recoveredDump, `${dump}.age`], process.env);
    assert.deepEqual(await fs.readFile(recoveredDump), await fs.readFile(dump));
    await db.query(`TRUNCATE ${schema}.probe`);
    // Restore table/data only into the disposable schema, never clean existing objects.
    await runTool(process.env.PG_RESTORE_PATH || 'pg_restore', ['--no-password', '--exit-on-error', '--data-only', '--dbname=' + url.pathname.slice(1), recoveredDump], { ...env, PGHOST: url.hostname, PGPORT: url.port, PGUSER: decodeURIComponent(url.username), PGPASSWORD: decodeURIComponent(url.password) });
    assert.equal((await db.query(`SELECT value FROM ${schema}.probe`)).rows[0].value, 'round-trip marker');
    const uploads = path.join(root, 'uploads'); const restored = path.join(root, 'restored');
    await fs.mkdir(uploads); await fs.mkdir(restored);
    await fs.writeFile(path.join(uploads, 'example.txt'), 'upload marker');
    const archive = path.join(root, 'uploads.tar.gz');
    const tar = process.env.BACKUP_TAR_PATH || 'tar';
    await runTool(tar, ['--create', '--gzip', `--file=${archive}`, '--directory', uploads, '--', '.'], process.env);
    await runTool(tar, ['--list', '--gzip', `--file=${archive}`], process.env);
    await runTool(age, ['--encrypt', '--recipient', recipient, '--output', `${archive}.age`, archive], process.env);
    const recoveredArchive = path.join(root, 'recovered.tar.gz');
    await runTool(age, ['--decrypt', '--identity', identity, '--output', recoveredArchive, `${archive}.age`], process.env);
    await runTool(tar, ['--extract', '--gzip', `--file=${recoveredArchive}`, '--directory', restored], process.env);
    assert.equal(await fs.readFile(path.join(restored, 'example.txt'), 'utf8'), 'upload marker');
    // Run the complete service pipeline against only the disposable schema.
    // Audit/lock metadata is isolated too: never write test backup history to
    // the real application's audit table or backup directory.
    const metadataClient = { on() {}, removeListener() {}, release() {},
      query: async () => ({ rows: [{ acquired: true }] }) };
    const service = new BackupService({
      db: { connect: async () => metadataClient }, directory: path.join(root, 'service-backups'),
      uploads, databaseUrl: url.toString(), recipient, agePath: age,
      run: (exe, args, ...rest) => runTool(exe,
        args.includes('--format=custom') ? [...args, `--schema=${schema}`] : args, ...rest),
    });
    await service.request(); await service.wait();
    const completed = await service.snapshot();
    assert.equal(completed.history[0].status, 'succeeded');
    assert.equal(completed.health, 'current');
    const backupFolder = path.join(service.directory, completed.history[0].id);
    assert.deepEqual((await fs.readdir(backupFolder)).sort(), ['database.dump.age', 'manifest.json', 'uploads.tar.gz.age']);
    const copied = await copyEncryptedBackup(backupFolder, path.join(root, 'copy-verification'));
    const serviceDump = path.join(root, 'service-recovered.dump');
    await runTool(age, ['--decrypt', '--identity', identity, '--output', serviceDump, path.join(copied.directory, 'database.dump.age')], process.env);
    await runTool(process.env.PG_RESTORE_PATH || 'pg_restore', ['--list', serviceDump], env);
    await db.query(`TRUNCATE ${schema}.probe`);
    await runTool(process.env.PG_RESTORE_PATH || 'pg_restore', ['--no-password', '--exit-on-error', '--data-only', '--dbname=' + url.pathname.slice(1), serviceDump], env);
    assert.equal((await db.query(`SELECT value FROM ${schema}.probe`)).rows[0].value, 'round-trip marker');
    const wrongIdentity = path.join(root, 'wrong-key.txt');
    await runTool(keygen, ['--output', wrongIdentity], process.env);
    await assert.rejects(runTool(age, ['--decrypt', '--identity', wrongIdentity, '--output', path.join(root, 'wrong.dump'), `${dump}.age`], process.env));
  } finally {
    await db.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await db.end(); await fs.rm(root, { recursive: true, force: true });
  }
});
