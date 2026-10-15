'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

async function withCorrectionRoute(run, { access = { locator_allowed: false, manage_allowed: true }, failLookup = false } = {}) {
  const state = { access, failLookup, lookups: 0, uploads: 0, connections: 0 };
  const query = async (sql, params) => {
    if (sql.includes('SELECT COALESCE') && sql.includes('FROM dtr_admin_access')) {
      state.lookups++;
      assert.deepEqual(params, ['11111111-1111-4111-8111-111111111111']);
      if (state.failLookup) throw new Error('Fixture permission lookup failure');
      return { rows: state.access ? [state.access] : [] };
    }
    // Router initialization is mocked; no schema or real records are written.
    return { rows: [] };
  };
  const restore = withMockedModule('../src/config/db', { pool: { query,
    connect: async () => { state.connections++; throw new Error('Correction database work must not run in access tests'); } } });
  clearModule('../src/middleware/dtrAccess');
  clearModule('../src/routes/locatorSlips');
  const originalError = console.error;
  try {
    console.error = () => {};
    const router = require('../src/routes/locatorSlips');
    const route = router.stack.find(e => e.route?.path === '/admin/corrections' && e.route.methods.post).route;
    assert.equal(route.stack[1].handle, require('../src/middleware/rbac').requireAdminOrHr);
    async function request(role = 'admin') {
      const req = { user: { id: '11111111-1111-4111-8111-111111111111', role } };
      const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
      // The caller is already authenticated. Run the real role/feature guards
      // in router order and observe the upload boundary without writing a file.
      for (const layer of route.stack.slice(1)) {
        if (layer.handle.name === 'uploadLocatorAttachmentMw') {
          state.uploads++;
          return res;
        }
        assert.notEqual(layer, route.stack.at(-1), 'Reached correction handler before upload boundary');
        let next = false;
        await layer.handle(req, res, () => { next = true; });
        if (!next) return res;
      }
      assert.fail('Correction upload boundary was not found');
    }
    await run({ state, request });
  } finally {
    console.error = originalError;
    clearModule('../src/routes/locatorSlips');
    clearModule('../src/middleware/dtrAccess');
    restore();
  }
}

for (const access of [{ locator_allowed: false, manage_allowed: true, reports_allowed: true }, {}, null]) {
  test(`correction rejects an admin without Locator permission before upload: ${JSON.stringify(access)}`, async () => {
    await withCorrectionRoute(async ({ state, request }) => {
      const res = await request();
      assert.equal(res.code, 403);
      assert.equal(res.body.error, 'DTR access is disabled for your account');
      assert.equal(state.lookups, 1);
      assert.equal(state.uploads, 0);
      assert.equal(state.connections, 0);
    }, { access });
  });
}

test('an admin with Locator permission can continue without other DTR permissions', async () => {
  await withCorrectionRoute(async ({ state, request }) => {
    assert.equal((await request()).code, 200);
    assert.equal(state.lookups, 1);
    assert.equal(state.uploads, 1);
  }, { access: { locator_allowed: true, manage_allowed: false, reports_allowed: false } });
});

test('HR correction access retains the existing role policy without an admin permission lookup', async () => {
  await withCorrectionRoute(async ({ state, request }) => {
    assert.equal((await request('hr')).code, 200);
    assert.equal(state.lookups, 0);
    assert.equal(state.uploads, 1);
  });
});

for (const role of ['employee', 'mayor', 'supervisor', 'super_admin']) {
  test(`${role} cannot bypass the correction admin/HR role guard`, async () => {
    await withCorrectionRoute(async ({ state, request }) => {
      assert.equal((await request(role)).code, 403);
      assert.equal(state.lookups, 0);
      assert.equal(state.uploads, 0);
      assert.equal(state.connections, 0);
    }, { access: { locator_allowed: true } });
  });
}

test('unverifiable correction permissions fail closed before upload', async () => {
  await withCorrectionRoute(async ({ state, request }) => {
    const res = await request();
    assert.equal(res.code, 503);
    assert.equal(res.body.error, 'DTR access could not be verified');
    assert.equal(state.uploads, 0);
    assert.equal(state.connections, 0);
  }, { failLookup: true });
});

test('correction permissions are rechecked after Locator access is revoked', async () => {
  await withCorrectionRoute(async ({ state, request }) => {
    assert.equal((await request()).code, 200);
    state.access.locator_allowed = false;
    const denied = await request();
    assert.equal(denied.code, 403);
    assert.equal(state.lookups, 2);
    assert.equal(state.uploads, 1);
  }, { access: { locator_allowed: true } });
});
