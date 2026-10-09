const test = require('node:test');
const assert = require('node:assert/strict');
const { savePrimaryReviewer } = require('../src/services/primaryReviewerDesignation');
const employeeId = '11111111-1111-4111-8111-111111111111';
const actorId = '22222222-2222-4222-8222-222222222222';

function fixture({ eligible = true, access = true, backup = false, auditFails = false } = {}) {
  const calls = [];
  const client = { release() {}, query: async (sql, params = []) => {
    calls.push({ sql, params });
    if (sql.includes('FROM users u')) return { rows: eligible ? [{ id: employeeId, role: 'admin', position_id: null, position_title: 'Shared Job Title' }] : [] };
    if (sql.includes('dtr_admin_access')) return { rows: [{ leave_allowed: access, locator_allowed: access }] };
    if (sql.includes('FROM leave_final_reviewer_backups')) return { rows: backup ? [{ id: 'backup-row' }] : [] };
    if (sql.includes('FROM primary_reviewer_designations')) return { rows: [{ id: actorId, employee_id: actorId, position_id: null, position_title_snapshot: 'Former Primary', effective_from: '2026-01-01', effective_to: null }] };
    if (sql.includes('INSERT INTO primary_reviewer_designations')) return { rows: [{ id: employeeId }] };
    if (sql.includes('INSERT INTO audit_logs') && auditFails) throw Error('audit failed');
    return { rows: [] };
  } };
  return { calls, pool: { connect: async () => client } };
}

test('dated replacement preserves the earlier designation and restores its later period', async () => {
  const { calls, pool } = fixture();
  await savePrimaryReviewer(pool, { employeeId, actorId, effectiveFrom: '2026-10-09', effectiveTo: '2026-10-31' });
  const inserts = calls.filter(c => c.sql.includes('INSERT INTO primary_reviewer_designations'));
  assert.equal(inserts.length, 2);
  assert.equal(inserts[0].params[2], actorId);
  assert.equal(inserts[1].params[2], employeeId);
  assert.equal(inserts[1].params[4], 'Shared Job Title');
  assert.equal(calls.at(-1).sql, 'COMMIT');
  assert.ok(calls.some(c => c.sql.includes('INSERT INTO audit_logs')));
});

for (const options of [{ eligible: false }, { access: false }, { backup: true }]) {
  test(`invalid primary assignment is rejected and rolled back: ${JSON.stringify(options)}`, async () => {
    const { calls, pool } = fixture(options);
    await assert.rejects(savePrimaryReviewer(pool, { employeeId, actorId, effectiveFrom: '2026-10-09' }), error => error.statusCode === 409);
    assert.equal(calls.at(-1).sql, 'ROLLBACK');
    assert.equal(calls.some(c => c.sql.includes('INSERT INTO primary_reviewer_designations')), false);
  });
}

test('audit failure rolls back a primary change', async () => {
  const { calls, pool } = fixture({ auditFails: true });
  await assert.rejects(savePrimaryReviewer(pool, { employeeId, actorId, effectiveFrom: '2026-10-09' }), /audit failed/);
  assert.equal(calls.at(-1).sql, 'ROLLBACK');
});

test('reversed or invalid designation dates cannot write', async () => {
  const { calls, pool } = fixture();
  for (const effectiveTo of ['2026-02-30', '2026-10-08']) {
    await assert.rejects(savePrimaryReviewer(pool, { employeeId, actorId, effectiveFrom: '2026-10-09', effectiveTo }), error => error.statusCode === 400);
  }
  assert.equal(calls.length, 0);
});
