'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('department head conflict lookup excludes current position and checks requested period', async () => {
  const queries = [];
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query(sql, params) {
        queries.push({ sql: String(sql), params });
        return { rows: [{ position_id: 'other-position', position_name: 'Department Head' }] };
      },
    },
  });
  clearModule('../src/routes/positions');
  try {
    const router = require('../src/routes/positions');
    const route = router.stack.find((entry) => entry.route?.path === '/department-head-conflict' && entry.route.methods.get);
    assert.ok(route);
    const response = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
    await route.route.stack.at(-1).handle({ query: {
      department_id: '11111111-1111-4111-8111-111111111111',
      exclude_position_id: '22222222-2222-4222-8222-222222222222',
      effective_from: '2026-09-21',
      effective_to: '2026-09-30',
    } }, response);
    assert.equal(response.statusCode, 200);
    assert.equal(response.body.position_name, 'Department Head');
    assert.deepEqual(queries[0].params, [
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '2026-09-21',
      '2026-09-30',
    ]);
    assert.match(queries[0].sql, /daterange\(/);
  } finally {
    clearModule('../src/routes/positions');
    restoreDb();
  }
});
