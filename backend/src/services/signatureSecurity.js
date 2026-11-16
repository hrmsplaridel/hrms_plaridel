'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const PREFIX = Buffer.from('UPSIG1\0');

function securityError(message, code = 'CONFLICT', statusCode = 409) {
  return Object.assign(new Error(message), { code, statusCode });
}
function keyring() {
  let ring;
  try {
    const raw = process.env.SIGNATURE_SECURITY_KEYS ||
      (process.env.SIGNATURE_SECURITY_KEY_FILE && fs.readFileSync(process.env.SIGNATURE_SECURITY_KEY_FILE, 'utf8'));
    ring = JSON.parse(raw);
    if (!/^[A-Za-z0-9_-]{1,32}$/.test(ring.active || '') || !ring.keys?.[ring.active]) throw Error();
    for (const [id, key] of Object.entries(ring.keys)) {
      if (!/^[A-Za-z0-9_-]{1,32}$/.test(id) || typeof key !== 'string' ||
          !/^[A-Za-z0-9+/]{43}=$/.test(key) || Buffer.from(key, 'base64').length !== 32) throw Error();
    }
  } catch (_) {
    throw securityError('Signature security keys are not configured correctly.', 'UNAVAILABLE', 503);
  }
  return ring;
}
function purposeKey(id, purpose) {
  const ring = keyring();
  if (!ring.keys[id]) throw securityError('The signature security key is unavailable.', 'UNAVAILABLE', 503);
  return Buffer.from(crypto.hkdfSync('sha256', Buffer.from(ring.keys[id], 'base64'),
    Buffer.from('UnityPillars signature security v1'), Buffer.from(purpose), 32));
}
function canonical(value) {
  if (value instanceof Date) return value.toISOString();
  if (Buffer.isBuffer(value)) return value.toString('base64');
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort()
    .filter(key => value[key] !== undefined).map(key => [key, canonical(value[key])]));
  return value;
}
function digest(value) {
  return crypto.createHash('sha256').update(Buffer.isBuffer(value) ? value : JSON.stringify(canonical(value))).digest('hex');
}
function isEncryptedSignature(bytes) {
  return Buffer.isBuffer(bytes) && bytes.subarray(0, PREFIX.length).equals(PREFIX);
}
function encryptSignature(bytes, { assetId, ownerId, mimeType }) {
  const id = keyring().active;
  const header = Buffer.from(JSON.stringify({ key_id: id, asset_id: String(assetId), owner_id: String(ownerId), mime_type: mimeType }));
  const length = Buffer.alloc(2); length.writeUInt16BE(header.length);
  const aad = Buffer.concat([PREFIX, length, header]);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', purposeKey(id, 'image-encryption'), iv);
  cipher.setAAD(aad);
  const encrypted = Buffer.concat([cipher.update(bytes), cipher.final()]);
  return Buffer.concat([aad, iv, cipher.getAuthTag(), encrypted]);
}
function decryptSignature(bytes, expected = {}, { allowLegacy = false } = {}) {
  if (!isEncryptedSignature(bytes)) {
    if (allowLegacy) return bytes;
    throw securityError('Legacy signature requires encryption migration.');
  }
  try {
    const end = PREFIX.length + 2 + bytes.readUInt16BE(PREFIX.length);
    if (end > 1024 || bytes.length < end + 29) throw Error();
    const metadata = JSON.parse(bytes.subarray(PREFIX.length + 2, end).toString('utf8'));
    for (const [field, name] of [['assetId', 'asset_id'], ['ownerId', 'owner_id'], ['mimeType', 'mime_type']]) {
      if (expected[field] != null && String(expected[field]) !== String(metadata[name])) throw Error();
    }
    const decipher = crypto.createDecipheriv('aes-256-gcm', purposeKey(metadata.key_id, 'image-encryption'), bytes.subarray(end, end + 12));
    decipher.setAAD(bytes.subarray(0, end)); decipher.setAuthTag(bytes.subarray(end + 12, end + 28));
    return Buffer.concat([decipher.update(bytes.subarray(end + 28)), decipher.final()]);
  } catch (error) {
    if (error.code === 'UNAVAILABLE') throw error;
    throw securityError('Signature image integrity verification failed.');
  }
}
function sealManifest(payload, purpose = 'receipt') {
  const keyId = keyring().active;
  const mac = crypto.createHmac('sha256', purposeKey(keyId, purpose)).update(JSON.stringify(canonical(payload))).digest('hex');
  return { key_id: keyId, payload, mac };
}
function verifyManifest(sealed, purpose = 'receipt') {
  if (!sealed || !/^[a-f0-9]{64}$/.test(sealed.mac || '')) throw securityError('Signature integrity verification failed.');
  const actual = crypto.createHmac('sha256', purposeKey(sealed.key_id, purpose)).update(JSON.stringify(canonical(sealed.payload))).digest();
  if (!crypto.timingSafeEqual(actual, Buffer.from(sealed.mac, 'hex'))) throw securityError('Signature integrity verification failed.');
  return sealed.payload;
}
function decodeAssetRow(row, field = 'signature_image_base64') {
  if (!row?.[field]) return row;
  const bytes = Buffer.from(row[field].replace(/\s+/g, ''), 'base64');
  if (!isEncryptedSignature(bytes)) return row; // Read compatibility while legacy data is migrated.
  return { ...row, [field]: decryptSignature(bytes, {
    assetId: row.signature_asset_id || row.asset_id || row.id,
    ownerId: row.owner_user_id || row.signed_by,
    mimeType: row.mime_type,
  }, { allowLegacy: true }).toString('base64') };
}
module.exports = { keyring, canonical, digest, encryptSignature, decryptSignature, isEncryptedSignature,
  sealManifest, verifyManifest, decodeAssetRow, securityError };
