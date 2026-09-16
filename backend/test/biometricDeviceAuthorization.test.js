'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

test('biometric device management list requires Admin authorization', () => {
  const authMiddleware = (_req, _res, next) => next();
  const requireAdmin = (_req, _res, next) => next();
  const restoreAuth = withMockedModule('../src/middleware/auth', {
    authMiddleware,
  });
  const restoreRbac = withMockedModule('../src/middleware/rbac', {
    requireAdmin,
  });
  const routePath = '../src/routes/biometricDevices';
  clearModule(routePath);

  try {
    const router = require(routePath);
    const route = router.stack.find(
      (entry) => entry.route?.path === '/' && entry.route.methods.get
    );
    const handlers = route.route.stack.map((entry) => entry.handle);

    assert.equal(handlers[0], authMiddleware);
    assert.equal(handlers[1], requireAdmin);
    assert.equal(handlers.length, 3);
  } finally {
    clearModule(routePath);
    restoreRbac();
    restoreAuth();
  }
});
