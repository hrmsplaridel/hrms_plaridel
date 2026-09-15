'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const deviceId = '22222222-2222-4222-8222-222222222222';

async function deleteDevice({ error = null, found = true } = {}) {
  const pool = {
    async query(sql) {
      if (!String(sql).startsWith('DELETE FROM biometric_devices')) {
        throw new Error(`Unexpected query: ${sql}`);
      }
      if (error) throw error;
      return found
        ? { rows: [{ id: deviceId }], rowCount: 1 }
        : { rows: [], rowCount: 0 };
    },
  };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = '../src/routes/biometricDevices';
  clearModule(routePath);
  const res = {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
    send() { this.sent = true; return this; },
  };

  try {
    const router = require(routePath);
    const route = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.delete
    );
    await route.route.stack.at(-1).handle({ params: { id: deviceId } }, res);
    return res;
  } finally {
    clearModule(routePath);
    restoreDb();
  }
}

test('unused biometric device can be permanently deleted', async () => {
  const res = await deleteDevice();
  assert.equal(res.statusCode, 204);
  assert.equal(res.sent, true);
});

test('device with raw attendance history returns a clear conflict', async () => {
  const res = await deleteDevice({ error: { code: '23503' } });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.code, 'BIOMETRIC_DEVICE_HAS_ATTENDANCE_HISTORY');
  assert.match(res.body.error, /attendance history/i);
  assert.match(res.body.error, /deactivate/i);
});

test('schemas preserve registered biometric device provenance', () => {
  const initSchema = fs.readFileSync(
    path.join(__dirname, '../scripts/init-schema.sql'),
    'utf8'
  );
  const migration = fs.readFileSync(
    path.join(
      __dirname,
      '../scripts/migrations/dtr/20260913_add_biometric_attendance_device_ref.sql'
    ),
    'utf8'
  );

  assert.match(
    initSchema,
    /device_ref_id UUID REFERENCES biometric_devices\(id\) ON DELETE RESTRICT/
  );
  assert.match(
    migration,
    /FOREIGN KEY \(device_ref_id\)[\s\S]*REFERENCES biometric_devices\(id\)[\s\S]*ON DELETE RESTRICT/
  );
});
