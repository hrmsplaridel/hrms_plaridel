const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

function response() {
  return {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('account creation requires an explicit admin grant but always permits super-admin', async () => {
  let allowed = false;
  const restore = withMockedModule('../src/config/db', {
    pool: {
      async query() { return { rows: [{ allowed }] }; },
    },
  });
  const path = '../src/middleware/accountCreationAccess';
  clearModule(path);
  try {
    const { requireAccountCreationAccess } = require(path);
    let nextCalls = 0;
    const next = () => { nextCalls++; };
    const denied = response();
    await requireAccountCreationAccess({ user: { role: 'admin', id: 'admin-1' } }, denied, next);
    assert.equal(denied.statusCode, 403);
    assert.equal(nextCalls, 0);

    allowed = true;
    await requireAccountCreationAccess({ user: { role: 'admin', id: 'admin-1' } }, response(), next);
    await requireAccountCreationAccess({ user: { role: 'super_admin' } }, response(), next);
    assert.equal(nextCalls, 2);

    const employee = response();
    await requireAccountCreationAccess({ user: { role: 'employee' } }, employee, next);
    assert.equal(employee.statusCode, 403);
  } finally {
    clearModule(path);
    restore();
  }
});

test('only super-admin can change account creation access and each change is audited', async () => {
  const queries = [];
  const client = {
    async query(sql, params) {
      queries.push({ sql, params });
      if (sql.includes('FROM users WHERE id')) return { rows: [{ role: 'admin' }] };
      if (sql.includes('COALESCE')) return { rows: [{ allowed: true }] };
      return { rows: [] };
    },
    release() {},
  };
  const restore = withMockedModule('../src/config/db', {
    pool: { async connect() { return client; } },
  });
  const path = '../src/routes/accountCreationAccess';
  clearModule(path);
  try {
    const router = require(path);
    const route = router.stack.find(entry => entry.route?.methods.put).route;
    const denied = response();
    route.stack[1].handle({ user: { role: 'admin' } }, denied, () => {});
    assert.equal(denied.statusCode, 403);

    const invalid = response();
    await route.stack[2].handle({ params: { adminId: 'bad' }, body: { allowed: false } }, invalid);
    assert.equal(invalid.statusCode, 400);

    const adminId = '00000000-0000-4000-8000-000000000001';
    const success = response();
    await route.stack[2].handle({
      user: { id: '00000000-0000-4000-8000-000000000002' },
      params: { adminId },
      body: { allowed: false },
    }, success);
    assert.equal(success.statusCode, 200);
    assert.equal(success.body.allowed, false);
    assert.ok(queries.some(({ sql }) => sql.includes('account_creation_access_changed')));
    assert.ok(queries.some(({ sql }) => sql === 'COMMIT'));
  } finally {
    clearModule(path);
    restore();
  }
});

test('public registration cannot create an account', () => {
  const router = require('../src/routes/auth');
  const route = router.stack.find(entry =>
    entry.route?.path === '/register' && entry.route.methods.post
  ).route;
  const res = response();
  route.stack.at(-1).handle({}, res);
  assert.equal(res.statusCode, 403);
  assert.match(res.body.error, /authorized administrator/i);
});

test('employee creation and biometric import both enforce account creation access', () => {
  const employeeRouter = require('../src/routes/employees');
  const biometricRouter = require('../src/routes/biometricDevices');
  const employeeCreate = employeeRouter.stack.find(entry =>
    entry.route?.path === '/' && entry.route.methods.post
  ).route;
  const biometricImport = biometricRouter.stack.find(entry =>
    entry.route?.path === '/:id/import-user' && entry.route.methods.post
  ).route;
  for (const route of [employeeCreate, biometricImport]) {
    assert.ok(route.stack.some(layer => layer.name === 'requireAccountCreationAccess'));
  }
});
