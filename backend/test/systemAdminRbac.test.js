const test = require('node:test');
const assert = require('node:assert/strict');
const { requireSuperAdmin, requireAdminOrSuperAdmin } = require('../src/middleware/rbac');

function check(middleware, role) {
  let allowed = false;
  const response = {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json() { return this; },
  };
  middleware({ user: { role } }, response, () => { allowed = true; });
  return { allowed, status: response.statusCode };
}

test('system audit requires super-admin', () => {
  assert.equal(check(requireSuperAdmin, 'super_admin').allowed, true);
  assert.deepEqual(check(requireSuperAdmin, 'admin'), { allowed: false, status: 403 });
  assert.deepEqual(check(requireSuperAdmin, 'employee'), { allowed: false, status: 403 });
});

test('account creation accepts admin and super-admin during transition', () => {
  assert.equal(check(requireAdminOrSuperAdmin, 'super_admin').allowed, true);
  assert.equal(check(requireAdminOrSuperAdmin, 'admin').allowed, true);
  assert.deepEqual(check(requireAdminOrSuperAdmin, 'employee'), { allowed: false, status: 403 });
});
