'use strict';
const fs = require('node:fs/promises');
const { createReadStream } = require('node:fs');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { spawn } = require('node:child_process');

const failure = (status, message) => Object.assign(new Error(message), { status });
const ownedId = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const artifactNames = ['database.dump', 'uploads.tar.gz', 'manifest.json'];
const inside = (parent, child) => child === parent || child.startsWith(parent + path.sep);

function databaseEnvironment(connectionString) {
  const url = new URL(connectionString);
  if (!['postgres:', 'postgresql:'].includes(url.protocol)) throw new Error('Unsupported database configuration');
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('PG')));
  Object.assign(env, { PGHOST: url.hostname.replace(/^\[|\]$/g, ''), PGPORT: url.port || '5432',
    PGDATABASE: decodeURIComponent(url.pathname.slice(1)), PGUSER: decodeURIComponent(url.username),
    PGPASSWORD: decodeURIComponent(url.password), PGCONNECT_TIMEOUT: '15' });
  const supported = { sslmode: 'PGSSLMODE', sslrootcert: 'PGSSLROOTCERT', sslcert: 'PGSSLCERT',
    sslkey: 'PGSSLKEY', sslpassword: 'PGSSLPASSWORD', options: 'PGOPTIONS',
    application_name: 'PGAPPNAME', connect_timeout: 'PGCONNECT_TIMEOUT',
    channel_binding: 'PGCHANNELBINDING', target_session_attrs: 'PGTARGETSESSIONATTRS', gssencmode: 'PGGSSENCMODE' };
  for (const [key, value] of url.searchParams) {
    if (!supported[key]) throw new Error('Unsupported database connection option');
    env[supported[key]] = value;
  }
  if (!env.PGDATABASE || !env.PGUSER || !env.PGHOST) throw new Error('Incomplete database configuration');
  return env;
}

// No shell, no connection URL in arguments, no raw stderr in API responses/logs.
function runTool(executable, args, env, signal) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { env, shell: false, windowsHide: true,
      stdio: ['ignore', 'ignore', 'ignore'], signal });
    const timeout = setTimeout(() => child.kill('SIGKILL'), 30 * 60 * 1000);
    child.once('error', () => { clearTimeout(timeout); reject(new Error('Backup tool could not run.')); });
    child.once('close', code => {
      clearTimeout(timeout);
      code === 0 ? resolve() : reject(new Error('Backup tool failed or timed out.'));
    });
  });
}

async function digest(file) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

class BackupService {
  constructor({ db, directory = process.env.BACKUP_DIR || path.resolve(__dirname, '../../.backups'),
    uploads = process.env.UPLOAD_DIR || path.resolve(__dirname, '../../uploads'),
    databaseUrl = process.env.DATABASE_URL, run = runTool, now = () => new Date() } = {}) {
    this.db = db; this.directory = path.resolve(directory); this.uploads = path.resolve(uploads);
    this.databaseUrl = databaseUrl; this.run = run; this.now = now;
    this.job = null; this.timer = null; this.preparing = false;
  }

  async init() {
    // Check lexical and resolved paths, including junctions/symlinks.
    if (inside(this.uploads, this.directory) || inside(this.directory, this.uploads)) {
      throw failure(503, 'Backup storage must be separate from uploads.');
    }
    await fs.mkdir(this.directory, { recursive: true, mode: 0o700 });
    const directory = await fs.realpath(this.directory);
    const uploads = await fs.realpath(this.uploads);
    if (inside(uploads, directory) || inside(directory, uploads)) {
      throw failure(503, 'Backup storage must be separate from uploads.');
    }
    this.directory = directory; this.uploads = uploads;
  }

  async read() {
    await this.init();
    try {
      const state = JSON.parse(await fs.readFile(path.join(this.directory, 'state.json'), 'utf8'));
      if (!Array.isArray(state.history) || !state.settings || typeof state.settings.revision !== 'string') throw new Error();
      return state;
    } catch (error) {
      if (error.code !== 'ENOENT') throw failure(503, 'Backup history is unreadable. Ask the server administrator to inspect backup storage.');
      return { settings: { enabled: false, time: '02:00', retentionDays: 7, revision: 'initial' }, history: [], scheduledDay: null };
    }
  }

  async write(state) {
    const temporary = path.join(this.directory, `state-${randomUUID()}.tmp`);
    try {
      await fs.writeFile(temporary, JSON.stringify(state, null, 2), { mode: 0o600, flag: 'wx' });
      await fs.rename(temporary, path.join(this.directory, 'state.json'));
    } finally { await fs.unlink(temporary).catch(() => {}); }
  }

  async lock() {
    const client = await this.db.connect();
    client.backupLockLost = false;
    client.backupErrorListener = () => { client.backupLockLost = true; };
    client.on('error', client.backupErrorListener);
    try {
      const result = await client.query('SELECT pg_try_advisory_lock(742019, 1) AS acquired');
      if (!result.rows[0].acquired) throw failure(409, 'A backup or settings update is already running.');
      return client;
    } catch (error) { client.removeListener('error', client.backupErrorListener); client.release(client.backupLockLost ? error : undefined); throw error; }
  }

  async unlock(client) {
    let error;
    try { await client.query('SELECT pg_advisory_unlock(742019, 1)'); } catch (e) { error = e; }
    client.removeListener('error', client.backupErrorListener);
    client.release(error);
  }

  async audit(client, actor, action, details) {
    await client.query(`INSERT INTO audit_logs (user_id, action, entity_type, details)
      VALUES ($1, $2, 'system_backup', $3::jsonb)`, [actor || null, action, JSON.stringify(details)]);
  }

  recover(state) {
    // Only called while holding the database lock: any recorded job has lost its owner.
    for (const row of state.history) if (row.status === 'running') {
      row.status = 'failed'; row.error = 'Backup interrupted. Create a new backup.';
      row.finishedAt = this.now().toISOString();
    }
  }

  async configure(input, actor) {
    if (!input || typeof input.enabled !== 'boolean' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(input.time) ||
        !Number.isInteger(input.retentionDays) || input.retentionDays < 1 || input.retentionDays > 90) {
      throw failure(400, 'Choose a valid daily time and retention of 1 to 90 days.');
    }
    const client = await this.lock();
    try {
      const state = await this.read(); this.recover(state);
      if (client.backupLockLost) throw failure(503, 'Backup database lock was lost. Try again.');
      if (input.revision !== state.settings.revision) throw failure(409, 'Backup settings changed. Refresh before saving.');
      const settings = { enabled: input.enabled, time: input.time, retentionDays: input.retentionDays, revision: randomUUID() };
      await this.audit(client, actor, 'backup_settings_changed', settings);
      state.settings = settings; await this.write(state);
      return settings;
    } finally { await this.unlock(client); }
  }

  localDay() {
    const stamp = new Date(this.now().getTime() + 8 * 3600000).toISOString();
    return { date: stamp.slice(0, 10), time: stamp.slice(11, 16) };
  }

  async request(source = 'manual', actor = null) {
    if (this.preparing || this.job) throw failure(409, 'A backup is already running.');
    this.preparing = true;
    let client;
    let handedOff = false;
    try {
      client = await this.lock();
      const state = await this.read(); this.recover(state);
      const local = this.localDay();
      if (source === 'scheduled' && (!state.settings.enabled || local.time < state.settings.time || state.scheduledDay === local.date)) {
        await this.write(state); return null;
      }
      if (source === 'manual' && state.history.some(r => this.now() - new Date(r.startedAt) < 60000)) {
        throw failure(429, 'Wait one minute before starting another backup.');
      }
      const row = { id: randomUUID(), source, status: 'running', startedAt: this.now().toISOString(), finishedAt: null, files: [], sizeBytes: 0 };
      await this.audit(client, actor, 'backup_started', { id: row.id, source });
      if (source === 'scheduled') state.scheduledDay = local.date;
      state.history.unshift(row); await this.write(state);
      this.job = this.execute(client, state, row, actor).catch(() => {
        console.error('[backups] Could not persist backup outcome. Check private backup storage.');
      }).finally(async () => { await this.unlock(client); this.job = null; });
      // Catch even a connection-release failure; never leave a rejected background promise.
      this.job = this.job.catch(() => { this.job = null; });
      handedOff = true;
      return { id: row.id, status: 'running' };
    } finally {
      this.preparing = false;
      if (client && !handedOff) await this.unlock(client);
    }
  }

  async execute(client, state, row, actor) {
    const folder = path.join(this.directory, row.id);
    const controller = new AbortController();
    const lostConnection = () => controller.abort();
    client.on('error', lostConnection);
    if (client.backupLockLost) controller.abort();
    let stage = 'preparing';
    try {
      if (!this.databaseUrl) throw new Error('Missing database configuration');
      await fs.mkdir(folder, { mode: 0o700 });
      for (const name of artifactNames.slice(0, 2)) await fs.writeFile(path.join(folder, name), '', { mode: 0o600, flag: 'wx' });
      const env = databaseEnvironment(this.databaseUrl);
      stage = 'database export';
      await this.run(process.env.PG_DUMP_PATH || 'pg_dump', ['--format=custom', '--no-password', '--lock-wait-timeout=30s', `--file=${path.join(folder, 'database.dump')}`], env, controller.signal);
      stage = 'database archive check';
      await this.run(process.env.PG_RESTORE_PATH || 'pg_restore', ['--list', path.join(folder, 'database.dump')], env, controller.signal);
      stage = 'upload archive';
      await this.run(process.env.BACKUP_TAR_PATH || 'tar', ['--create', '--gzip', `--file=${path.join(folder, 'uploads.tar.gz')}`, '--directory', this.uploads, '--', '.'], process.env, controller.signal);
      stage = 'upload archive check';
      await this.run(process.env.BACKUP_TAR_PATH || 'tar', ['--list', '--gzip', `--file=${path.join(folder, 'uploads.tar.gz')}`], process.env, controller.signal);
      for (const name of artifactNames.slice(0, 2)) {
        const file = path.join(folder, name); const stat = await fs.stat(file);
        if (!stat.size) throw new Error('Empty archive');
        row.files.push({ name, sizeBytes: stat.size, sha256: await digest(file) });
      }
      if (controller.signal.aborted) throw new Error('Lock lost');
      row.sizeBytes = row.files.reduce((sum, file) => sum + file.sizeBytes, 0);
      row.status = 'succeeded'; row.finishedAt = this.now().toISOString();
      await fs.writeFile(path.join(folder, 'manifest.json'), JSON.stringify({ ...row,
        format: 1, scope: 'PostgreSQL database and local uploads; external storage and server secrets excluded',
        recoveryTested: false }, null, 2), { mode: 0o600, flag: 'wx' });
    } catch (_) {
      row.status = 'failed'; row.finishedAt = this.now().toISOString(); row.files = [];
      row.error = `Failed during ${stage}. Check database tools, storage permissions, free space, and database connectivity on the server.`;
      await this.removeArtifacts(row.id).catch(() => {});
    } finally { client.removeListener('error', lostConnection); }
    if (controller.signal.aborted) throw new Error('Backup lock lost; do not overwrite another worker state');
    await this.write(state);
    try { await this.audit(client, actor, `backup_${row.status}`, { id: row.id, sizeBytes: row.sizeBytes }); }
    catch (_) { row.warning = 'Backup result could not be added to the audit log.'; }
    if (row.status === 'succeeded') {
      try { await this.prune(state); }
      catch (_) { row.warning = 'Backup completed, but retention cleanup needs attention.'; }
    }
    state.history = state.history.filter((r, index) => r.status === 'succeeded' || index < 100);
    await this.write(state);
  }

  async removeArtifacts(id) {
    if (!ownedId.test(id)) throw new Error('Invalid backup id');
    const folder = path.join(this.directory, id);
    const stat = await fs.lstat(folder).catch(e => { if (e.code === 'ENOENT') return null; throw e; });
    if (!stat) return;
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Unsafe backup directory');
    for (const name of artifactNames) await fs.unlink(path.join(folder, name)).catch(e => { if (e.code !== 'ENOENT') throw e; });
    await fs.rmdir(folder); // Never recursively delete unexpected files or directories.
  }

  async prune(state) {
    const latest = state.history.find(r => r.status === 'succeeded');
    const cutoff = this.now().getTime() - state.settings.retentionDays * 86400000;
    for (const row of state.history) {
      if (row.status === 'succeeded' && row !== latest && Date.parse(row.finishedAt) < cutoff) {
        await this.removeArtifacts(row.id); row.status = 'expired'; row.files = [];
      }
    }
  }

  async snapshot() {
    const state = await this.read();
    const lastSuccess = state.history.find(r => r.status === 'succeeded') || null;
    const latest = state.history[0];
    let health = !lastSuccess ? 'missing' : this.now() - new Date(lastSuccess.finishedAt) > 26 * 3600000 ? 'overdue' : 'current';
    if (latest?.status === 'failed') health = 'failed';
    if (latest?.status === 'running') health = 'running';
    if (lastSuccess) {
      try {
        if (!ownedId.test(lastSuccess.id)) throw new Error();
        for (const name of artifactNames) {
          const stat = await fs.stat(path.join(this.directory, lastSuccess.id, name));
          if (!stat.isFile() || !stat.size) throw new Error();
        }
      } catch (_) { health = 'missing_files'; }
    }
    return { settings: state.settings, history: state.history, lastSuccess, health,
      storageLocation: this.directory, timezone: 'Asia/Manila', scope: 'Database + local uploads' };
  }

  async tick() {
    if (this.job || this.preparing) return;
    try { await this.request('scheduled'); } catch (_) { /* Next tick retries a transient lock/storage outage. */ }
  }
  start() { if (!this.timer) { this.timer = setInterval(() => void this.tick(), 60000); this.timer.unref(); void this.tick(); } }
  stop() { clearInterval(this.timer); this.timer = null; }
  async wait() { await this.job; }
}
module.exports = { BackupService, runTool, databaseEnvironment };
