const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { BackupService } = require('../src/services/systemBackups');

async function fixture(t, overrides = {}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hrms-backup-test-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const uploads = path.join(root, 'uploads'); await fs.mkdir(uploads);
  let locked = false;
  const audits = [];
  const db = { connect: async () => ({
    on() {}, removeListener() {}, release() {},
    query: async (sql, args) => {
      if (sql.includes('pg_try_advisory_lock')) {
        const acquired = !locked; if (acquired) locked = true;
        return { rows: [{ acquired }] };
      }
      if (sql.includes('pg_advisory_unlock')) locked = false;
      if (sql.includes('INSERT INTO audit_logs')) audits.push(args);
      return { rows: [] };
    },
  }) };
  const run = async (exe, args) => {
    const output = args.find(a => a.startsWith('--file='));
    if (output) await fs.writeFile(output.slice(7), 'test backup content');
  };
  const service = new BackupService({ db, directory: path.join(root, 'backups'), uploads,
    databaseUrl: 'postgres://test:SECRET@localhost/test', run, ...overrides });
  return { service, root, audits, db };
}

test('backup publishes both verified artifacts and safe history; schedule defaults off', async t => {
  const { service, audits } = await fixture(t);
  assert.equal((await service.snapshot()).settings.enabled, false);
  await service.request('manual', null); await service.wait();
  const state = await service.snapshot();
  assert.equal(state.history[0].status, 'succeeded');
  assert.equal(state.health, 'current');
  assert.equal(state.history[0].files.length, 2);
  assert.ok(state.history[0].files.every(f => f.sha256.length === 64));
  assert.ok(audits.length >= 2);
  assert.ok(!JSON.stringify(state).includes('SECRET'));
});

test('failed tool does not publish success or leak process errors', async t => {
  const { service } = await fixture(t, { run: async () => { throw new Error('password=SECRET'); } });
  await service.request('manual', null); await service.wait();
  const state = await service.snapshot();
  assert.equal(state.history[0].status, 'failed');
  assert.equal(state.lastSuccess, null);
  assert.ok(!JSON.stringify(state).includes('SECRET'));
});

test('lock excludes concurrent jobs and settings; malformed settings are rejected', async t => {
  let finish;
  const pending = new Promise(resolve => { finish = resolve; });
  const { service } = await fixture(t, { run: async () => { await pending; throw new Error(); } });
  await service.request('manual', null);
  await assert.rejects(service.request('manual', null), e => e.status === 409);
  finish(); await service.wait();
  await assert.rejects(service.configure({ enabled: true, time: '25:61', retentionDays: -1 }, null), e => e.status === 400);
});

test('backup destination cannot be inside uploads', async t => {
  const { root, db } = await fixture(t);
  const service = new BackupService({ db, uploads: path.join(root, 'uploads'), directory: path.join(root, 'uploads', 'backups') });
  await assert.rejects(service.snapshot());
});

test('schedule catches up once per Manila day and stale configuration is rejected', async t => {
  const { service } = await fixture(t, { now: () => new Date('2026-10-04T03:00:00Z') });
  const state = await service.snapshot();
  const settings = { enabled: true, time: '02:00', retentionDays: 7, revision: state.settings.revision };
  await service.configure(settings, null);
  await assert.rejects(service.configure(settings, null), e => e.status === 409);
  await service.tick(); await service.wait();
  await service.tick(); await service.wait();
  assert.equal((await service.snapshot()).history.length, 1);
});

test('retention deletes only expired successful artifacts after a newer success', async t => {
  let now = new Date('2026-10-01T03:00:00Z');
  const { service } = await fixture(t, { now: () => now });
  const initial = await service.snapshot();
  await service.configure({ ...initial.settings, retentionDays: 1 }, null);
  await service.request(); await service.wait();
  const first = (await service.snapshot()).history[0];
  now = new Date('2026-10-04T03:00:00Z');
  await service.request(); await service.wait();
  const state = await service.snapshot();
  assert.equal(state.history[0].status, 'succeeded');
  assert.equal(state.history[1].status, 'expired');
  await assert.rejects(fs.stat(path.join(service.directory, first.id)), e => e.code === 'ENOENT');
  assert.ok(await fs.stat(path.join(service.directory, state.history[0].id, 'database.dump')));
});

test('failed backup preserves the previous good copy; missing artifacts are reported', async t => {
  let now = new Date('2026-10-01T03:00:00Z');
  const { service } = await fixture(t, { now: () => now });
  await service.request(); await service.wait();
  const first = (await service.snapshot()).lastSuccess;
  now = new Date('2026-10-20T03:00:00Z');
  service.run = async () => { throw new Error(); };
  await service.request(); await service.wait();
  assert.equal((await service.snapshot()).lastSuccess.id, first.id);
  const file = path.join(service.directory, first.id, 'database.dump');
  await fs.unlink(file);
  assert.equal((await service.snapshot()).health, 'missing_files');
});

test('interrupted history is recovered and corrupt metadata fails closed', async t => {
  const { service } = await fixture(t);
  const state = await service.read();
  state.history.push({ id: 'interrupted', status: 'running', startedAt: '2020-01-01T00:00:00Z' });
  await service.write(state);
  await service.tick();
  assert.equal((await service.snapshot()).history[0].status, 'failed');
  await fs.writeFile(path.join(service.directory, 'state.json'), '{broken');
  await assert.rejects(service.snapshot(), e => e.status === 503);
});

test('cleanup refuses unowned ids and overlapping service instances cannot start', async t => {
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const { service, db } = await fixture(t, { run: async () => { await gate; throw new Error(); } });
  await assert.rejects(service.removeArtifacts('../uploads'));
  await service.request();
  const other = new BackupService({ db, directory: service.directory, uploads: service.uploads });
  await assert.rejects(other.request(), e => e.status === 409);
  release(); await service.wait();
});

test('connection secrets stay out of command arguments and SSL settings survive', async t => {
  const { databaseEnvironment } = require('../src/services/systemBackups');
  const env = databaseEnvironment('postgres://user:p%40ss@localhost:5433/hrms?sslmode=require');
  assert.equal(env.PGPASSWORD, 'p@ss'); assert.equal(env.PGSSLMODE, 'require');
  assert.equal(env.PGDATABASE, 'hrms'); assert.equal(env.PGPORT, '5433');
  const calls = [];
  const { service } = await fixture(t, { run: async (exe, args) => {
    calls.push(args); throw new Error();
  } });
  await service.request(); await service.wait();
  assert.ok(calls.length); assert.ok(!JSON.stringify(calls).includes('SECRET'));
});
