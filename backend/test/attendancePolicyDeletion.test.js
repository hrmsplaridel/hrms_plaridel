'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const policyId = '11111111-1111-4111-8111-111111111111';

async function deletePolicy({ deleted = true, exists = true, error = null } = {}) {
  const queries = [];
  const invalidations = [];
  const pool = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ text, params });
      if (text.startsWith('DELETE FROM attendance_policies')) {
        if (error) throw error;
        return deleted
          ? { rows: [{ id: policyId }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      if (text.includes('FROM attendance_policies') && text.includes('AS is_used')) {
        return exists
          ? { rows: [{ id: policyId, is_used: true }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      throw new Error(`Unexpected query: ${text}`);
    },
  };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const restoreCache = withMockedModule('../src/services/attendancePolicyCache', {
    invalidateAttendancePolicyCache: (options) => invalidations.push(options),
  });
  const routePath = '../src/routes/attendancePolicies';
  clearModule(routePath);
  const res = {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
    send() { this.sent = true; return this; },
  };
  try {
    const router = require(routePath);
    const route = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.delete
    );
    await route.route.stack.at(-1).handle({ params: { id: policyId } }, res);
    return { res, queries, invalidations };
  } finally {
    clearModule(routePath);
    restoreCache();
    restoreDb();
  }
}

test('unused attendance policy can be permanently deleted', async () => {
  const { res, queries, invalidations } = await deletePolicy();

  assert.equal(res.statusCode, 204);
  assert.equal(res.sent, true);
  assert.match(queries[0].text, /NOT EXISTS[\s\S]*policy_assignments/);
  assert.match(queries[0].text, /NOT EXISTS[\s\S]*dtr_daily_summary/);
  assert.deepEqual(invalidations, [undefined]);
});

test('policy with assignment or DTR history returns a clear conflict', async () => {
  const { res, invalidations } = await deletePolicy({ deleted: false });

  assert.equal(res.statusCode, 409);
  assert.match(res.body.error, /history/i);
  assert.match(res.body.error, /deactivate/i);
  assert.deepEqual(invalidations, []);
});

test('missing policy returns not found instead of a history conflict', async () => {
  const { res } = await deletePolicy({ deleted: false, exists: false });
  assert.equal(res.statusCode, 404);
});

test('foreign-key protection is translated to a conflict response', async () => {
  const originalConsoleError = console.error;
  console.error = () => {};
  try {
    const { res } = await deletePolicy({ error: { code: '23503' } });
    assert.equal(res.statusCode, 409);
    assert.match(res.body.error, /deactivate/i);
  } finally {
    console.error = originalConsoleError;
  }
});

test('authoritative and migration schemas restrict attendance-policy history deletion', () => {
  const initSchema = fs.readFileSync(
    path.join(__dirname, '../scripts/init-schema.sql'),
    'utf8'
  );
  const migration = fs.readFileSync(
    path.join(
      __dirname,
      '../scripts/migrations/dtr/20260910_attendance_policy_history_protection.sql'
    ),
    'utf8'
  );

  assert.match(
    initSchema,
    /attendance_policy_id UUID NOT NULL REFERENCES attendance_policies\(id\) ON DELETE RESTRICT/
  );
  assert.match(
    initSchema,
    /attendance_policy_id UUID REFERENCES attendance_policies\(id\) ON DELETE RESTRICT/
  );
  assert.match(migration, /policy_assignments_attendance_policy_id_fkey[\s\S]*ON DELETE RESTRICT/);
  assert.match(migration, /dtr_daily_summary_attendance_policy_id_fkey[\s\S]*ON DELETE RESTRICT/);
});
