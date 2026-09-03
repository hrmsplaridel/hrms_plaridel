const test = require('node:test');
const assert = require('node:assert/strict');

const {
  EmployeeAccountSecurityError,
  lockAndValidateAccountTransition,
  lockAndValidateBulkAccountStatusTransition,
  lockAndPlanBulkAccountStatusTransition,
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

test('bulk status planning rejects a separated employee while updating valid accounts', async () => {
  const activeEmployeeId = '33333333-3333-4333-8333-333333333333';
  const resignedEmployeeId = '44444444-4444-4444-8444-444444444444';
  let queryIndex = 0;
  const results = [
    { rowCount: 0, rows: [] },
    {
      rowCount: 2,
      rows: [
        targetRow({
          id: activeEmployeeId,
          full_name: 'Active Employee',
          role: 'employee',
          is_active: false,
          employment_status: 'active',
        }),
        targetRow({
          id: resignedEmployeeId,
          full_name: 'Resigned Employee',
          role: 'employee',
          is_active: false,
          employment_status: 'resigned',
        }),
      ],
    },
  ];
  const db = { query: async () => results[queryIndex++] };

  const plan = await lockAndPlanBulkAccountStatusTransition(db, {
    actorId: OTHER_ADMIN_ID,
    targetIds: [activeEmployeeId, resignedEmployeeId],
    isActive: true,
  });

  assert.deepEqual(
    plan.updateTargets.map((target) => target.id),
    [activeEmployeeId]
  );
  assert.equal(plan.results[0].outcome, 'updated');
  assert.equal(plan.results[1].outcome, 'rejected');
  assert.equal(plan.results[1].code, 'EMPLOYMENT_STATUS_NOT_ACTIVE');
});

test('protected administrator does not cancel a valid employee deactivation', async () => {
  const employeeId = '55555555-5555-4555-8555-555555555555';
  let queryIndex = 0;
  const results = [
    { rowCount: 0, rows: [] },
    {
      rowCount: 2,
      rows: [
        targetRow({ id: ADMIN_ID }),
        targetRow({
          id: employeeId,
          full_name: 'Employee User',
          role: 'employee',
          is_active: true,
        }),
      ],
    },
  ];
  const db = { query: async () => results[queryIndex++] };

  const plan = await lockAndPlanBulkAccountStatusTransition(db, {
    actorId: ADMIN_ID,
    targetIds: [ADMIN_ID, employeeId],
    isActive: false,
  });

  assert.deepEqual(
    plan.updateTargets.map((target) => target.id),
    [employeeId]
  );
  assert.equal(plan.results[0].code, 'SELF_DEACTIVATION_BLOCKED');
  assert.equal(plan.results[1].outcome, 'updated');
});

test('bulk status planning reports missing and already-correct accounts', async () => {
  const inactiveEmployeeId = '66666666-6666-4666-8666-666666666666';
  const missingEmployeeId = '77777777-7777-4777-8777-777777777777';
  let queryIndex = 0;
  const results = [
    { rowCount: 0, rows: [] },
    {
      rowCount: 1,
      rows: [
        targetRow({
          id: inactiveEmployeeId,
          role: 'employee',
          is_active: false,
        }),
      ],
    },
  ];
  const db = { query: async () => results[queryIndex++] };

  const plan = await lockAndPlanBulkAccountStatusTransition(db, {
    actorId: OTHER_ADMIN_ID,
    targetIds: [inactiveEmployeeId, missingEmployeeId],
    isActive: false,
  });

  assert.equal(plan.updateTargets.length, 0);
  assert.equal(plan.results[0].outcome, 'skipped');
  assert.equal(plan.results[1].outcome, 'not_found');
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
