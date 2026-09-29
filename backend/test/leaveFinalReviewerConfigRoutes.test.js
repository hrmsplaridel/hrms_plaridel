'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const primaryId = '11111111-1111-4111-8111-111111111111';
const backupId = '22222222-2222-4222-8222-222222222222';

test('final reviewer config reports the official holder and ranked backups', async () => {
  const pool = {
    async query(sql) {
      const statement = String(sql);
      if (statement.includes('FROM positions p')) {
        return { rows: [{ id: primaryId, name: 'Official Reviewer' }] };
      }
      if (statement.includes('FROM leave_final_reviewer_backups')) {
        return { rows: [{ id: backupId, name: 'Backup Reviewer' }] };
      }
      if (statement.includes('FROM users')) {
        return { rows: [
          { id: primaryId, name: 'Official Reviewer' },
          { id: backupId, name: 'Backup Reviewer' },
        ] };
      }
      throw new Error(`Unexpected SQL: ${statement}`);
    },
  };
  const restore = withMockedModule('../src/config/db', { pool });
  clearModule('../src/routes/positions');
  try {
    const router = require('../src/routes/positions');
    const route = router.stack.find((entry) =>
      entry.route?.path === '/leave-final-reviewers' && entry.route.methods.get
    );
    const response = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(body) { this.body = body; return this; },
    };
    await route.route.stack.at(-1).handle({
      query: { effective_date: '2026-10-01' },
    }, response);
    assert.equal(response.statusCode, 200);
    assert.equal(response.body.effective_date, '2026-10-01');
    assert.equal(response.body.primary.id, primaryId);
    assert.deepEqual(response.body.backups.map((row) => row.id), [backupId]);
  } finally {
    clearModule('../src/routes/positions');
    restore();
  }
});

test('backup assignment rejects an impossible effective date', async () => {
  const restore = withMockedModule('../src/config/db', {
    pool: { connect: async () => { throw new Error('Should not open a transaction'); } },
  });
  clearModule('../src/routes/positions');
  try {
    const router = require('../src/routes/positions');
    const route = router.stack.find((entry) =>
      entry.route?.path === '/leave-final-reviewers' && entry.route.methods.put
    );
    const response = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(body) { this.body = body; return this; },
    };
    await route.route.stack.at(-1).handle({
      body: { effective_from: '2026-02-30', employee_ids: [] },
      user: { id: primaryId },
    }, response);
    assert.equal(response.statusCode, 400);
  } finally {
    clearModule('../src/routes/positions');
    restore();
  }
});
