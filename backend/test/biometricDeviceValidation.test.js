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

async function invokeMutation({ method, path, body }) {
  const queries = [];
  const pool = {
    async query(sql, params) {
      queries.push({ sql: String(sql), params });
      return {
        rows: [{ id: deviceId, ...body }],
        rowCount: 1,
      };
    },
  };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = '../src/routes/biometricDevices';
  clearModule(routePath);
  const res = response();

  try {
    const router = require(routePath);
    const route = router.stack.find(
      (entry) => entry.route?.path === path && entry.route.methods[method]
    );
    await route.route.stack.at(-1).handle({ body, params: { id: deviceId } }, res);
    return { res, queries };
  } finally {
    clearModule(routePath);
    restoreDb();
  }
}

test('device create rejects string booleans instead of coercing them', async () => {
  const { res, queries } = await invokeMutation({
    method: 'post',
    path: '/',
    body: { name: 'Front Clock', is_active: 'false' },
  });

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /is_active must be a boolean/i);
  assert.equal(queries.length, 0);
});

test('device create rejects an unknown vendor instead of changing it to ZKTeco', async () => {
  const { res, queries } = await invokeMutation({
    method: 'post',
    path: '/',
    body: { name: 'Front Clock', vendor: 'hikvison' },
  });

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /vendor must be one of/i);
  assert.equal(queries.length, 0);
});

test('device mutations return controlled validation errors for invalid text and hosts', async () => {
  const invalidName = await invokeMutation({
    method: 'post',
    path: '/',
    body: { name: 123 },
  });
  const invalidHost = await invokeMutation({
    method: 'put',
    path: '/:id',
    body: { ip_address: 'http://192.168.1.20:4370' },
  });

  assert.equal(invalidName.res.statusCode, 400);
  assert.match(invalidName.res.body.error, /name must be a string/i);
  assert.equal(invalidName.queries.length, 0);
  assert.equal(invalidHost.res.statusCode, 400);
  assert.match(invalidHost.res.body.error, /valid IP address or hostname/i);
  assert.equal(invalidHost.queries.length, 0);
});

test('device create normalizes valid values without changing their meaning', async () => {
  const { res, queries } = await invokeMutation({
    method: 'post',
    path: '/',
    body: {
      name: '  Front Clock  ',
      device_id: '  ZK-01  ',
      location: '  Lobby  ',
      ip_address: '  clock-01.local  ',
      vendor: '  HIKVISION  ',
      is_active: false,
    },
  });

  assert.equal(res.statusCode, 201);
  assert.equal(queries.length, 1);
  assert.deepEqual(queries[0].params, [
    'Front Clock',
    'ZK-01',
    'Lobby',
    'clock-01.local',
    'hikvision',
    false,
  ]);
});

test('device update validates only supplied fields and preserves false', async () => {
  const { res, queries } = await invokeMutation({
    method: 'put',
    path: '/:id',
    body: { is_active: false },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(queries.length, 1);
  assert.deepEqual(queries[0].params, [false, deviceId]);
  assert.match(queries[0].sql, /is_active = \$1/);
});
