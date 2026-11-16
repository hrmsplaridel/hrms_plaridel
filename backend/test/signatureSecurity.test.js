'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const security = () => require('../src/services/signatureSecurity');
const png = Buffer.from('89504e470d0a1a0a01020304', 'hex');
const identity = { assetId: 'asset-one', ownerId: 'owner-one', mimeType: 'image/png' };
let previous, previousFile;
test.beforeEach(() => {
  previous = process.env.SIGNATURE_SECURITY_KEYS;
  previousFile = process.env.SIGNATURE_SECURITY_KEY_FILE;
  delete process.env.SIGNATURE_SECURITY_KEY_FILE;
  process.env.SIGNATURE_SECURITY_KEYS = JSON.stringify({ active: 'test-v1', keys: { 'test-v1': crypto.randomBytes(32).toString('base64') } });
});
test.afterEach(() => {
  if (previous === undefined) delete process.env.SIGNATURE_SECURITY_KEYS;
  else process.env.SIGNATURE_SECURITY_KEYS = previous;
  if (previousFile === undefined) delete process.env.SIGNATURE_SECURITY_KEY_FILE;
  else process.env.SIGNATURE_SECURITY_KEY_FILE = previousFile;
});

test('signature bytes are encrypted with randomized authenticated envelopes', () => {
  const { encryptSignature, decryptSignature, isEncryptedSignature } = security();
  const one = encryptSignature(png, identity), two = encryptSignature(png, identity);
  assert.ok(isEncryptedSignature(one));
  assert.notDeepEqual(one, two);
  assert.equal(one.includes(png), false);
  assert.deepEqual(decryptSignature(one, identity), png);
});
test('ciphertext and owner/asset substitutions are rejected', () => {
  const { encryptSignature, decryptSignature } = security();
  const encrypted = encryptSignature(png, identity);
  for (const change of [{ ownerId: 'other' }, { assetId: 'other' }, { mimeType: 'image/jpeg' }]) {
    assert.throws(() => decryptSignature(encrypted, { ...identity, ...change }), /integrity/i);
  }
  encrypted[encrypted.length - 1] ^= 1;
  assert.throws(() => decryptSignature(encrypted, identity), /integrity/i);
});
test('missing keys fail closed and old keys remain readable after rotation', () => {
  const { encryptSignature, decryptSignature } = security();
  const encrypted = encryptSignature(png, identity);
  const ring = JSON.parse(process.env.SIGNATURE_SECURITY_KEYS);
  ring.active = 'test-v2'; ring.keys['test-v2'] = crypto.randomBytes(32).toString('base64');
  process.env.SIGNATURE_SECURITY_KEYS = JSON.stringify(ring);
  assert.deepEqual(decryptSignature(encrypted, identity), png);
  delete ring.keys['test-v1']; process.env.SIGNATURE_SECURITY_KEYS = JSON.stringify(ring);
  assert.throws(() => decryptSignature(encrypted, identity), /key|integrity/i);
  delete process.env.SIGNATURE_SECURITY_KEYS;
  assert.throws(() => encryptSignature(png, identity), /configured/i);
});
test('legacy bytes remain readable only through explicit migration compatibility', () => {
  const { decryptSignature } = security();
  assert.throws(() => decryptSignature(png, identity), /legacy|encrypt/i);
  assert.deepEqual(decryptSignature(png, identity, { allowLegacy: true }), png);
});
test('canonical document digest ignores object ordering but detects changed contents', () => {
  const { digest } = security();
  assert.equal(digest({ a: 1, b: [2, 3] }), digest({ b: [2, 3], a: 1 }));
  assert.notEqual(digest({ reason: 'Meeting' }), digest({ reason: 'Other purpose' }));
  assert.notEqual(digest([1, 2]), digest([2, 1]));
});
test('integrity receipt binds content, signer, signature image and document revision', () => {
  const { sealManifest, verifyManifest } = security();
  const manifest = { subject: 'leave:one:applicant:1', content_digest: 'content', image_digest: 'image', signer_id: 'owner-one', signed_at: '2026-11-16T12:00:00Z' };
  const sealed = sealManifest(manifest, 'receipt');
  assert.deepEqual(verifyManifest(sealed, 'receipt'), manifest);
  assert.throws(() => verifyManifest(sealed, 'authorization'), /integrity/i);
  const changed = { ...sealed, payload: { ...sealed.payload, signer_id: 'attacker' } };
  assert.throws(() => verifyManifest(changed, 'receipt'), /integrity/i);
});

test('asset service stores ciphertext and returns only usable image bytes to the owner', async () => {
  const { createSignatureAsset } = require('../src/services/docutrackerDocumentBuilderService');
  let stored;
  const db = { query: async (_sql, params) => {
    stored = params[1];
    return { rows: [{ id: params[6], owner_user_id: params[0], mime_type: params[2], image_base64: params[1].toString('base64') }] };
  } };
  const asset = await createSignatureAsset(db, { id: identity.ownerId }, {
    mime_type: identity.mimeType, source_type: 'drawn', image_base64: png.toString('base64'),
  });
  assert.notDeepEqual(stored, png);
  assert.equal(asset.image_base64, png.toString('base64'));
});
