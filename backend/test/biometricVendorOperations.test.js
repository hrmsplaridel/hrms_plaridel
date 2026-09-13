'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const deviceId = '22222222-2222-4222-8222-222222222222';

function response() {
  return {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
}

async function invokeDeviceRoute({ method, path, vendor }) {
  let scriptCalls = 0;
  const pool = {
    async query(sql) {
      const text = String(sql);
      if (text.includes('FROM biometric_devices')) {
        return {
          rows: [{ ip_address: '192.0.2.10', vendor }],
          rowCount: 1,
        };
      }
      if (text.includes('FROM users')) {
        return {
          rows: [{
            id: '11111111-1111-4111-8111-111111111111',
            full_name: 'Test Employee',
            biometric_user_id: '1001',
          }],
          rowCount: 1,
        };
      }
      throw new Error(`Unexpected query: ${text}`);
    },
  };
  const execFile = (...args) => {
    scriptCalls++;
    const callback = args.at(-1);
    callback(null, JSON.stringify({ success: true, users: [] }), '');
  };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const restoreChildProcess = withMockedModule('child_process', { execFile });
  const routePath = '../src/routes/biometricDevices';
  clearModule(routePath);
  const res = response();

  try {
    const router = require(routePath);
    const route = router.stack.find(
      (entry) => entry.route?.path === path && entry.route.methods[method]
    );
    await route.route.stack.at(-1).handle({
      params: { id: deviceId },
      body: { employee_id: '11111111-1111-4111-8111-111111111111' },
    }, res);
    return { res, scriptCalls };
  } finally {
    clearModule(routePath);
    restoreChildProcess();
    restoreDb();
  }
}

test('device-user retrieval rejects non-ZKTeco vendors before running Python', async () => {
  const { res, scriptCalls } = await invokeDeviceRoute({
    method: 'get',
    path: '/:id/users',
    vendor: 'hikvision',
  });

  assert.equal(res.statusCode, 422);
  assert.equal(res.body.code, 'BIOMETRIC_VENDOR_USER_MANAGEMENT_UNSUPPORTED');
  assert.equal(scriptCalls, 0);
});

test('employee push rejects non-ZKTeco vendors before running Python', async () => {
  const { res, scriptCalls } = await invokeDeviceRoute({
    method: 'post',
    path: '/:id/push-user',
    vendor: 'anviz',
  });

  assert.equal(res.statusCode, 422);
  assert.equal(res.body.code, 'BIOMETRIC_VENDOR_USER_MANAGEMENT_UNSUPPORTED');
  assert.equal(scriptCalls, 0);
});

test('ZKTeco device-user retrieval continues using the existing adapter', async () => {
  const { res, scriptCalls } = await invokeDeviceRoute({
    method: 'get',
    path: '/:id/users',
    vendor: 'zkteco',
  });

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, []);
  assert.equal(scriptCalls, 1);
});

test('employee device filter rejects non-ZKTeco vendors before running Python', async () => {
  let scriptCalls = 0;
  const pool = {
    async query() {
      return {
        rows: [{ ip_address: '192.0.2.10', vendor: 'hikvision' }],
        rowCount: 1,
      };
    },
  };
  const execFile = () => { scriptCalls++; };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const restoreChildProcess = withMockedModule('child_process', { execFile });
  const servicePath = '../src/services/biometricDeviceUsers';
  clearModule(servicePath);

  try {
    const { getDeviceUserBiometricIds } = require(servicePath);
    const result = await getDeviceUserBiometricIds(deviceId);
    assert.equal(result.ok, false);
    assert.equal(result.statusCode, 422);
    assert.equal(result.code, 'BIOMETRIC_VENDOR_USER_MANAGEMENT_UNSUPPORTED');
    assert.equal(scriptCalls, 0);
  } finally {
    clearModule(servicePath);
    restoreChildProcess();
    restoreDb();
  }
});
