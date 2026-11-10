const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { copyEncryptedBackup } = require('../scripts/copy-encrypted-backup');

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hrms-encrypted-copy-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const id = randomUUID(), source = path.join(root, 'server', id), destination = path.join(root, 'external');
  await fs.mkdir(source, { recursive: true });
  const files = [];
  for (const name of ['database.dump.age', 'uploads.tar.gz.age']) {
    const bytes = Buffer.from('age-encryption.org/v1\nopaque encrypted bytes');
    await fs.writeFile(path.join(source, name), bytes);
    files.push({ name, sizeBytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
  }
  const manifest = { id, format: 2, status: 'succeeded', encryption: { scheme: 'age' }, files };
  await fs.writeFile(path.join(source, 'manifest.json'), JSON.stringify(manifest));
  return { source, destination, manifest };
}

test('copy validates encrypted artifacts and writes the manifest last; never overwrites an existing copy', async t => {
  const f = await fixture(t);
  const result = await copyEncryptedBackup(f.source, f.destination);
  assert.equal(result.directory, path.join(f.destination, f.manifest.id));
  assert.deepEqual((await fs.readdir(result.directory)).sort(), ['database.dump.age', 'manifest.json', 'uploads.tar.gz.age']);
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(result.directory, 'manifest.json'), 'utf8')), f.manifest);
  await assert.rejects(copyEncryptedBackup(f.source, f.destination), /already exists/);
});

test('corrupt source and plaintext backups are rejected before a completed copy is created', async t => {
  const f = await fixture(t);
  await fs.appendFile(path.join(f.source, 'database.dump.age'), 'corrupt');
  await assert.rejects(copyEncryptedBackup(f.source, f.destination), /integrity/);
  await assert.rejects(fs.stat(path.join(f.destination, f.manifest.id)), e => e.code === 'ENOENT');
  f.manifest.encryption = null;
  await fs.writeFile(path.join(f.source, 'manifest.json'), JSON.stringify(f.manifest));
  await assert.rejects(copyEncryptedBackup(f.source, f.destination), /encrypted/);
});

test('destination cannot be the backup source, its parent, or an uploads/project directory', async t => {
  const f = await fixture(t);
  await assert.rejects(copyEncryptedBackup(f.source, path.dirname(f.source)), /separate/);
  await assert.rejects(copyEncryptedBackup(f.source, path.join(f.source, 'copy')), /separate/);
  await assert.rejects(copyEncryptedBackup(f.source, path.resolve(__dirname, '..', 'uploads')), /project/);
});
