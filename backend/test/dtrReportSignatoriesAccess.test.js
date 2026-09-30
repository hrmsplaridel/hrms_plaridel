const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

test('authenticated employees can resolve print officials without admin designation-history access', async () => {
  const restore = withMockedModule('../src/config/db', {
    pool: { query: async () => ({ rows: [] }) },
  });
  const path = '../src/routes/dtrReportSignatories';
  clearModule(path);
  try {
    const router = require(path);
    const route = router.stack.find((entry) => entry.route?.methods.get).route;
    assert.ok(route.stack.some((entry) => entry.handle.name === 'authMiddleware'));
    assert.equal(router.stack.filter((entry) => entry.route).length, 1);
    const response = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(data) { this.data = data; return this; },
    };
    await route.stack.at(-1).handle({ user: { role: 'employee' } }, response);
    assert.equal(response.statusCode, 200);
    assert.deepEqual(Object.keys(response.data.roles).sort(), ['dtr_hr_officer', 'dtr_office_hours_verifier']);
    assert.equal(response.data.items, undefined);
  } finally {
    clearModule(path);
    restore();
  }
});
