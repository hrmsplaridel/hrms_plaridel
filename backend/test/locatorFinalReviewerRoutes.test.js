'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('locator final reviewer cannot decide their own request', async () => {
  const applicant = '11111111-1111-4111-8111-111111111111';
  const queries = [];
  const client = {
    async query(sql) {
      const statement = String(sql);
      queries.push(statement);
      if (statement.includes('FOR UPDATE')) {
        return { rows: [{ id: 'slip', status: 'pending_hr', employee_id: applicant }] };
      }
      return { rows: [] };
    },
    release() {},
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { connect: async () => client, query: async () => ({ rows: [] }) },
  });
  clearModule('../src/routes/locatorSlips');
  try {
    const router = require('../src/routes/locatorSlips');
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
        body: { reason: 'No' },
      }, response);
    } finally {
      console.error = originalError;
    }
    assert.equal(response.statusCode, 403);
    assert.match(response.body.error, /own locator/i);
    assert.equal(queries.some((query) => query.includes('UPDATE locator_slips')), false);
  } finally {
    clearModule('../src/routes/locatorSlips');
    restoreDb();
  }
});

test('locator HR list excludes requests that never reached final review', async () => {
  const statements = [];
  const query = async (sql) => {
    const statement = String(sql).replace(/\s+/g, ' ');
    statements.push(statement);
    if (statement.includes('COUNT(*)::integer AS total')) {
      return { rows: [{ total: 0 }] };
    }
    return { rows: [] };
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query, connect: async () => ({ query, release() {} }) },
  });
  clearModule('../src/routes/locatorSlips');
  try {
    const router = require('../src/routes/locatorSlips');
    const route = router.stack.find((entry) =>
      entry.route?.path === '/admin' && entry.route.methods.get
    );
    const response = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(body) { this.body = body; return this; },
    };
    await route.route.stack.at(-1).handle({ query: {} }, response);
    assert.equal(response.statusCode, 200);
    const listQuery = statements.find((statement) => statement.includes('COUNT(*)::integer AS total'));
    assert.match(listQuery, /review_history\.to_status IN \('pending', 'pending_hr'\)/);
    assert.match(listQuery, /ls\.is_retroactive_correction = true/);
  } finally {
    clearModule('../src/routes/locatorSlips');
    restoreDb();
  }
});
