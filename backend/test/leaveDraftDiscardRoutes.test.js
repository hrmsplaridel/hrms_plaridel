'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const userId = '11111111-1111-4111-8111-111111111111';
const draftId = '22222222-2222-4222-8222-222222222222';

test('reviewer availability reports a missing reviewer before draft creation', async () => {
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query: async (sql) => {
      if (String(sql).includes('FROM positions p') || String(sql).includes('FROM leave_final_reviewer_backups')) return { rows: [] };
      return { rows: [] };
    } },
  });
  clearModule('../src/routes/leaveRoutes');
  try {
    const router = require('../src/routes/leaveRoutes');
    const route = router.stack.find((entry) => entry.route?.path === '/submission-availability' && entry.route.methods.get);
    assert.ok(route);
    const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
    await route.route.stack.at(-1).handle({ user: { id: userId } }, res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.can_submit, false);
    assert.match(res.body.reason, /final leave reviewer/i);
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
});

test('only the owner can discard an unsubmitted draft, retaining its history', async () => {
  const queries = [];
  const client = {
    async query(sql) {
      const statement = String(sql);
      queries.push(statement);
      if (statement === 'BEGIN' || statement === 'COMMIT') return { rows: [] };
      if (statement.includes('FROM leave_requests') && statement.includes('FOR UPDATE')) {
        return { rows: [{ id: draftId, status: 'draft', discarded_at: null }] };
      }
      if (statement.includes('UPDATE leave_requests')) return { rows: [{ id: draftId }] };
      return { rows: [] };
    },
    release() {},
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { connect: async () => client, query: async () => ({ rows: [] }) },
  });
  clearModule('../src/routes/leaveRoutes');
  try {
    const router = require('../src/routes/leaveRoutes');
    const route = router.stack.find((entry) => entry.route?.path === '/:id/discard' && entry.route.methods.patch);
    assert.ok(route);
    const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
    await route.route.stack.at(-1).handle({ user: { id: userId }, params: { id: draftId } }, res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.discarded, true);
    assert.ok(queries.some((sql) => sql.includes('discarded_at = now()')));
    assert.ok(queries.some((sql) => sql.includes('INSERT INTO leave_request_history')));
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
});

test('a submitted request cannot be discarded', async () => {
  const queries = [];
  const client = {
    async query(sql) {
      const statement = String(sql);
      queries.push(statement);
      if (statement === 'BEGIN' || statement === 'ROLLBACK') return { rows: [] };
      if (statement.includes('FROM leave_requests') && statement.includes('FOR UPDATE')) {
        return { rows: [{ id: draftId, status: 'pending_hr', discarded_at: null }] };
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
    const route = router.stack.find((entry) => entry.route?.path === '/:id/discard' && entry.route.methods.patch);
    const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
    await route.route.stack.at(-1).handle({ user: { id: userId }, params: { id: draftId } }, res);
    assert.equal(res.statusCode, 409);
    assert.equal(queries.some((sql) => sql.includes('UPDATE leave_requests')), false);
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
});

test('My Requests excludes discarded drafts from both page and count queries', async () => {
  const queries = [];
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { async query(sql) {
      queries.push(String(sql));
      if (String(sql).includes('COUNT(*) OVER()')) return { rows: [] };
      return { rows: [{ total: 0 }] };
    } },
  });
  clearModule('../src/routes/leaveRoutes');
  try {
    const router = require('../src/routes/leaveRoutes');
    const route = router.stack.find((entry) => entry.route?.path === '/my' && entry.route.methods.get);
    const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
    await route.route.stack.at(-1).handle({ user: { id: userId }, query: { paginated: 'true', offset: '50' } }, res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.total, 0);
    const listQueries = queries.filter((sql) => sql.includes('FROM leave_requests lr'));
    assert.equal(listQueries.length, 2);
    for (const sql of listQueries) assert.match(sql, /lr\.discarded_at IS NULL/);
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
});
