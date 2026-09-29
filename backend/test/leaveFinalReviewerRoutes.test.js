'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('HR/admin cannot reject their own leave even with role access', async () => {
  const applicant = '11111111-1111-4111-8111-111111111111';
  const queries = [];
  const client = {
    async query(sql) {
      const statement = String(sql);
      queries.push(statement);
      if (statement === 'BEGIN' || statement === 'ROLLBACK') return { rows: [] };
      if (statement.includes('FOR UPDATE OF lr')) {
        return { rows: [{ status: 'pending_hr', user_id: applicant, reserved_credit_days: 1 }] };
      }
      throw new Error(`Unexpected SQL: ${statement}`);
    },
    release() {},
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { connect: async () => client, query: async () => ({ rows: [] }) },
  });
  clearModule('../src/routes/leaveRoutes');
  try {
    const router = require('../src/routes/leaveRoutes');
    const route = router.stack.find((entry) =>
      entry.route?.path === '/:id/reject' && entry.route.methods.patch
    );
    const response = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(body) { this.body = body; return this; },
    };
    const originalError = console.error;
    console.error = () => {};
    try {
      await route.route.stack.at(-1).handle({
        user: { id: applicant, role: 'admin' },
        params: { id: '22222222-2222-4222-8222-222222222222' },
        body: {},
      }, response);
    } finally {
      console.error = originalError;
    }
    assert.equal(response.statusCode, 403);
    assert.match(response.body.error, /own leave/i);
    assert.equal(queries.some((query) => query.includes('UPDATE leave_requests')), false);
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
});
