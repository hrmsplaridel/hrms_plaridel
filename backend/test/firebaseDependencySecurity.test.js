const test = require('node:test');
const assert = require('node:assert/strict');
const lock = require('../package-lock.json');

function atLeast(version, minimum) {
  const actual = String(version).split('.').map(Number);
  for (let index = 0; index < minimum.length; index++) {
    if (!Number.isInteger(actual[index])) return false;
    if (actual[index] !== minimum[index]) return actual[index] > minimum[index];
  }
  return true;
}

for (const [name, minimum, advisory] of [
  ['glob', [14, 0, 2], 'GHSA-3g3m-2fjr-6pw4'],
  ['minimatch', [11, 0, 1], 'GHSA-g3hv-75wg-m249'],
]) {
  test(`locked dependency tree excludes vulnerable ${name} (${advisory})`, () => {
    for (const [packagePath, metadata] of Object.entries(lock.packages)) {
      if (!packagePath.endsWith(`/node_modules/${name}`) && packagePath !== `node_modules/${name}`) continue;
      assert.ok(atLeast(metadata.version, minimum), `${packagePath}@${metadata.version} is affected by ${advisory}`);
    }
  });
}

test('Firebase Messaging and Firestore initialize without making external requests', async () => {
  const { initializeApp, deleteApp } = require('firebase-admin/app');
  const { getMessaging } = require('firebase-admin/messaging');
  const { getFirestore } = require('firebase-admin/firestore');
  const app = initializeApp({ projectId: 'hrms-dependency-smoke-test' }, 'dependency-smoke-test');
  try {
    assert.equal(typeof getMessaging(app).send, 'function');
    const firestore = getFirestore(app);
    assert.equal(firestore.collection('dependency-health').doc('check').path, 'dependency-health/check');
  } finally {
    await deleteApp(app);
  }
});
