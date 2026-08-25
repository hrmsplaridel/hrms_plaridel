const test = require('node:test');
const assert = require('node:assert/strict');

const {
  EmployeeAccountSecurityError,
  lockAndValidateAccountTransition,
  lockAndValidateBulkAccountStatusTransition,
  revokeActiveRefreshTokens,
  writeAccountSecurityAudit,
} = require('../src/services/employeeAccountSecurity');

const ADMIN_ID = '11111111-1111-4111-8111-111111111111';
const OTHER_ADMIN_ID = '22222222-2222-4222-8222-222222222222';

function targetRow(overrides = {}) {
  return {
    id: ADMIN_ID,
    full_name: 'Admin User',
    email: 'admin@example.test',
    role: 'admin',
    is_active: true,
    employment_status: 'active',
    ...overrides,
  };
}

test('administrator cannot deactivate their own account', async () => {
  const db = {
    query: async () => ({ rowCount: 1, rows: [targetRow()] }),
  };

  await assert.rejects(
    lockAndValidateAccountTransition(db, {
      actorId: ADMIN_ID,
      targetId: ADMIN_ID,
      nextIsActive: false,
    }),
    (error) =>
      error instanceof EmployeeAccountSecurityError &&
      error.code === 'SELF_DEACTIVATION_BLOCKED'
  );
});

test('administrator cannot demote their own account', async () => {
  const db = {
    query: async () => ({ rowCount: 1, rows: [targetRow()] }),
  };

  await assert.rejects(
    lockAndValidateAccountTransition(db, {
      actorId: ADMIN_ID,
      targetId: ADMIN_ID,
      nextRole: 'employee',
    }),
    (error) =>
      error instanceof EmployeeAccountSecurityError &&
      error.code === 'SELF_DEMOTION_BLOCKED'
  );
});

test('last active administrator cannot be deactivated by another administrator', async () => {
  let queryIndex = 0;
  const results = [
    { rowCount: 1, rows: [{}] },
    { rowCount: 1, rows: [targetRow()] },
    { rowCount: 1, rows: [{ count: 0 }] },
  ];
  const db = { query: async () => results[queryIndex++] };

  await assert.rejects(
    lockAndValidateAccountTransition(db, {
      actorId: OTHER_ADMIN_ID,
      targetId: ADMIN_ID,
      nextIsActive: false,
    }),
    (error) => error.code === 'LAST_ACTIVE_ADMIN_BLOCKED'
  );
});

test('administrator transition is allowed when another active administrator remains', async () => {
  let queryIndex = 0;
  const results = [
    { rowCount: 1, rows: [{}] },
    { rowCount: 1, rows: [targetRow()] },
    { rowCount: 1, rows: [{ count: 1 }] },
  ];
  const db = { query: async () => results[queryIndex++] };

  const transition = await lockAndValidateAccountTransition(db, {
    actorId: OTHER_ADMIN_ID,
    targetId: ADMIN_ID,
    nextRole: 'employee',
  });

  assert.equal(transition.next.role, 'employee');
  assert.equal(transition.revokeSessions, true);
});

test('bulk deactivation cannot remove every active administrator', async () => {
  let queryIndex = 0;
  const results = [
    { rowCount: 1, rows: [{}] },
    { rowCount: 1, rows: [targetRow()] },
    { rowCount: 1, rows: [{ count: 0 }] },
  ];
  const db = { query: async () => results[queryIndex++] };

  await assert.rejects(
    lockAndValidateBulkAccountStatusTransition(db, {
      actorId: OTHER_ADMIN_ID,
      targetIds: [ADMIN_ID],
      isActive: false,
    }),
    (error) => error.code === 'LAST_ACTIVE_ADMIN_BLOCKED'
  );
});

test('session revocation and account audit use the provided transaction client', async () => {
  const calls = [];
  const db = {
    query: async (sql, params) => {
      calls.push({ sql, params });
      return { rowCount: 2, rows: [] };
    },
  };

  assert.equal(await revokeActiveRefreshTokens(db, ADMIN_ID), 2);
  await writeAccountSecurityAudit(db, {
    actorId: OTHER_ADMIN_ID,
    targetId: ADMIN_ID,
    action: 'employee_account_deactivated',
    previous: { role: 'admin', is_active: true },
    next: { role: 'admin', is_active: false },
    source: 'test',
  });

  assert.match(calls[0].sql, /UPDATE auth_refresh_tokens/i);
  assert.match(calls[1].sql, /INSERT INTO audit_logs/i);
  assert.equal(JSON.parse(calls[1].params[3]).source, 'test');
});
