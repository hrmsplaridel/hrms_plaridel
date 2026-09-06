const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

function responseRecorder() {
  return {
    statusCode: 200,
    payload: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.payload = body;
      return this;
    },
  };
}

test('shift catalog rejects employees and allows administrators', () => {
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      query: async () => {
        throw new Error('authorization test must not query the database');
      },
    },
  });
  const routePath = '../src/routes/shifts';
  clearModule(routePath);

  try {
    const router = require(routePath);
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/' && entry.route.methods.get,
    );
    assert.ok(layer, 'GET / shift catalog route not found');

    const guard = layer.route.stack
      .map((entry) => entry.handle)
      .find((handler) => handler.name === 'requireAdmin');
    assert.ok(guard, 'GET / shift catalog is missing the administrator guard');

    const employeeResponse = responseRecorder();
    let employeeAdvanced = false;
    guard(
      { user: { id: 'employee-1', role: 'employee' } },
      employeeResponse,
      () => {
        employeeAdvanced = true;
      },
    );
    assert.equal(employeeResponse.statusCode, 403);
    assert.equal(employeeResponse.payload?.error, 'Admin access required');
    assert.equal(employeeAdvanced, false);

    const adminResponse = responseRecorder();
    let adminAdvanced = false;
    guard(
      { user: { id: 'admin-1', role: 'admin' } },
      adminResponse,
      () => {
        adminAdvanced = true;
      },
    );
    assert.equal(adminAdvanced, true);
  } finally {
    clearModule(routePath);
    restoreDb();
  }
});
