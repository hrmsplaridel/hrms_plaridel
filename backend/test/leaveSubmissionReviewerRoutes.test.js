'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const applicant = '11111111-1111-4111-8111-111111111111';
const requestId = '22222222-2222-4222-8222-222222222222';

for (const [method, path] of [
  ['post', '/submit'],
  ['post', '/submit-with-attachment'],
  ['put', '/:id'],
]) {
  test(`${method.toUpperCase()} ${path} refuses submission without an eligible final reviewer`, async () => {
    const queries = [];
    const client = {
      async query(sql) {
        const statement = String(sql);
        queries.push(statement);
        if (statement === 'BEGIN' || statement === 'ROLLBACK') return { rows: [] };
        if (statement.includes('FROM positions p') || statement.includes('FROM leave_final_reviewer_backups')) {
          return { rows: [] };
        }
        throw new Error(`Unexpected SQL: ${statement}`);
      },
      release() {},
    };
    const restoreDb = withMockedModule('../src/config/db', {
      pool: {
        connect: async () => client,
        query: async (sql) => {
          if (String(sql).includes('FROM leave_requests')) {
            return { rows: [{ id: requestId, status: 'draft' }] };
          }
          return { rows: [] };
        },
      },
    });
    clearModule('../src/routes/leaveRoutes');
    try {
      const router = require('../src/routes/leaveRoutes');
      const route = router.stack.find((entry) => entry.route?.path === path && entry.route.methods[method]);
      const response = {
        statusCode: 200,
        status(code) { this.statusCode = code; return this; },
        json(body) { this.body = body; return this; },
      };
      const request = {
        user: { id: applicant, role: 'employee' },
        params: { id: requestId },
        body: { leave_type: 'Vacation Leave', start_date: '2026-09-22', end_date: '2026-09-22', status: 'pending' },
        file: method === 'post' && path.includes('attachment') ? { buffer: Buffer.from('test') } : undefined,
      };
      const originalError = console.error;
      console.error = () => {};
      try {
        await route.route.stack.at(-1).handle(request, response);
      } finally {
        console.error = originalError;
      }
      assert.equal(response.statusCode, 409);
      assert.match(response.body.error, /final leave reviewer/i);
      assert.ok(queries.includes('ROLLBACK'));
      assert.equal(queries.some((sql) => /INSERT INTO leave_requests|UPDATE leave_requests/.test(sql)), false);
    } finally {
      clearModule('../src/routes/leaveRoutes');
      restoreDb();
    }
  });
}
