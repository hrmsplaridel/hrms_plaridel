'use strict';
const fs = require('node:fs/promises');
const { createReadStream, constants } = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const names = ['database.dump.age', 'uploads.tar.gz.age'];
const inside = (parent, child) => parent === child || child.startsWith(parent + path.sep);

async function resolvedPath(value) {
  try { return await fs.realpath(value); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    const parent = path.dirname(value);
    if (parent === value) throw error;
    return path.join(await resolvedPath(parent), path.basename(value));
  }
}

async function verify(file, expected) {
  const stat = await fs.lstat(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size !== expected.sizeBytes) throw new Error('Backup integrity check failed.');
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  if (hash.digest('hex') !== expected.sha256) throw new Error('Backup integrity check failed.');
}

async function copyEncryptedBackup(sourceFolder, destinationRoot) {
  if (!sourceFolder || !destinationRoot) throw new Error('Provide the completed source folder and a separate destination root.');
  const source = await fs.realpath(path.resolve(sourceFolder));
  const destination = await resolvedPath(path.resolve(destinationRoot));
  const project = await fs.realpath(path.resolve(__dirname, '../..'));
  if (inside(project, destination)) throw new Error('The destination must be outside the project.');
  if (inside(source, destination) || inside(destination, source)) throw new Error('Choose a separate destination outside the source backup storage.');
  const manifestPath = path.join(source, 'manifest.json');
  const stat = await fs.lstat(manifestPath);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 1024 * 1024) throw new Error('Invalid backup manifest.');
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  if (manifest.format !== 2 || manifest.status !== 'succeeded' || manifest.encryption?.scheme !== 'age') throw new Error('Only completed encrypted backups can be copied with this command.');
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(manifest.id) || path.basename(source) !== manifest.id) throw new Error('Invalid backup identity.');
  if (!Array.isArray(manifest.files) || manifest.files.length !== names.length) throw new Error('Invalid backup artifact list.');
  for (const name of names) {
    const expected = manifest.files.find(file => file.name === name);
    if (!expected || !Number.isSafeInteger(expected.sizeBytes) || expected.sizeBytes <= 0 || !/^[a-f0-9]{64}$/.test(expected.sha256)) throw new Error('Invalid backup artifact details.');
    await verify(path.join(source, name), expected);
  }
  await fs.mkdir(destination, { recursive: true, mode: 0o700 });
  const folder = path.join(destination, manifest.id);
  try { await fs.mkdir(folder, { mode: 0o700 }); }
  catch (error) { if (error.code === 'EEXIST') throw new Error('A copy of this backup already exists; it was not overwritten.'); throw error; }
  try {
    for (const name of names) {
      const target = path.join(folder, name);
      await fs.copyFile(path.join(source, name), target, constants.COPYFILE_EXCL);
      await fs.chmod(target, 0o600);
      await verify(target, manifest.files.find(file => file.name === name));
    }
    // A copy is complete only after both ciphertext hashes match the manifest.
    await fs.writeFile(path.join(folder, 'manifest.json'), JSON.stringify(manifest, null, 2), { mode: 0o600, flag: 'wx' });
    return { directory: folder, filesVerified: names.length };
  } catch (error) {
    for (const name of [...names, 'manifest.json']) await fs.unlink(path.join(folder, name)).catch(() => {});
    await fs.rmdir(folder).catch(() => {});
    throw error;
  }
}

if (require.main === module) {
  const [source, destination, ...extra] = process.argv.slice(2);
  if (extra.length) { console.error('Usage: node scripts/copy-encrypted-backup.js <backup-folder> <destination-root>'); process.exitCode = 1; }
  else copyEncryptedBackup(source, destination).then(result => {
    console.log(`Verified encrypted copy: ${result.directory}`);
    console.log('Store this copy on separate/offline storage. This command does not verify physical separation or update server backup history.');
  }).catch(error => { console.error(error.message); process.exitCode = 1; });
}
module.exports = { copyEncryptedBackup };
