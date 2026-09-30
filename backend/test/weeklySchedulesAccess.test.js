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

for (const [method, path] of [['get', '/'], ['put', '/:employeeId/:weekStart']]) {
  test(`weekly schedule ${method.toUpperCase()} is restricted to administrators`, () => {
    const restoreDb = withMockedModule('../src/config/db', {
      pool: { query: async () => { throw new Error('must not query'); } },
    });
    const routePath = '../src/routes/weeklySchedules';
    clearModule(routePath);
    try {
      const router = require(routePath);
      const layer = router.stack.find(
        (entry) => entry.route?.path === path && entry.route.methods[method]
      );
      assert.ok(layer);
      assert.ok(layer.route.stack.some((entry) => entry.handle.name === 'authMiddleware'));
      const guard = layer.route.stack
        .map((entry) => entry.handle)
        .find((handler) => handler.name === 'requireAdmin');
      assert.ok(guard);

      const employeeResponse = responseRecorder();
      let advanced = false;
      guard(
        { user: { id: 'employee-1', role: 'employee' } },
        employeeResponse,
        () => { advanced = true; }
      );
      assert.equal(advanced, false);
      assert.equal(employeeResponse.statusCode, 403);

      guard(
        { user: { id: 'admin-1', role: 'admin' } },
        responseRecorder(),
        () => { advanced = true; }
      );
      assert.equal(advanced, true);
    } finally {
      clearModule(routePath);
      restoreDb();
    }
  });
}
