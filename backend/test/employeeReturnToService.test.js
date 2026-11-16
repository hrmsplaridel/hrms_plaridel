'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const ID = '11111111-1111-4111-8111-111111111111';
const ACTOR = '22222222-2222-4222-8222-222222222222';
const payload = {
  returned_on: '2026-11-16', reason: 'Approved return to municipal service',
  leave_credit_eligible: true,
  assignment: { department_id: ID, position_id: ID, shift_id: ID },
  attendance_policy_id: ID,
};
const source = '../src/services/employeeReturnToService';

for (const scenario of [{ role: 'employee', access: true, status: 403 },
  { role: 'admin', access: false, status: 403 }, { role: 'admin', access: true, status: 200 }]) {
  test(`return endpoint enforces employee-management access: ${JSON.stringify(scenario)}`, async () => {
    let returned = false;
    const restores = [
      withMockedModule('../src/config/db', { pool: { query: async () => ({ rows: [{ employees_allowed: scenario.access }] }) } }),
      withMockedModule(source, { returnEmployeeToService: async () => { returned = true; return { id: ID }; } }),
    ];
    clearModule('../src/middleware/dtrAccess'); clearModule('../src/routes/employees');
    try {
      const route = require('../src/routes/employees').stack.find(layer => layer.route?.path === '/:id/return-to-service').route;
      const req = { user: { id: ACTOR, role: scenario.role }, params: { id: ID }, body: payload };
      const res = { code: 200, status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
      async function dispatch(index) {
        if (index >= route.stack.length) return;
        let downstream;
        await route.stack[index].handle(req, res, () => { downstream = dispatch(index + 1); return downstream; });
        if (downstream) await downstream;
      }
      await dispatch(1); // Authenticated identities; exercise role and feature authorization.
      assert.equal(res.code, scenario.status);
      assert.equal(returned, scenario.status === 200);
    } finally {
      clearModule('../src/routes/employees'); clearModule('../src/middleware/dtrAccess');
      restores.reverse().forEach(restore => restore());
    }
  });
}

async function fixture(run, { status = 'resigned', separation = '2026-09-15', failSetup = false, employmentType = 'permanent', role = 'employee' } = {}) {
  const calls = [];
  let released = false;
  const previous = { id: ID, role, employment_status: status, is_active: false,
    full_name: 'Returning employee', email: 'return@example.test', date_hired: '2025-01-01',
    separation_date: separation, leave_credit_eligible: false, leave_credit_eligible_until: separation,
    last_service_return_date: null, employment_type: employmentType, auth_version: 4 };
  const client = { async query(sql, values = []) {
    calls.push({ sql, values });
    if (sql.includes('FROM users') && sql.includes('FOR UPDATE')) return { rowCount: 1, rows: [{ ...previous }] };
    if (sql.includes('UPDATE users')) return { rowCount: 1, rows: [{ ...previous,
      employment_status: 'active', is_active: true, separation_date: null, leave_credit_eligible_until: null,
      last_service_return_date: payload.returned_on, leave_credit_eligible: true }] };
    if (sql.includes('INSERT INTO employee_service_returns')) return { rowCount: 1, rows: [{ id: ACTOR }] };
    return { rowCount: 0, rows: [] };
  }, release() { released = true; } };
  let setup;
  const realSetup = require('../src/services/employeeSetupTransaction');
  const restore = withMockedModule('../src/services/employeeSetupTransaction', {
    ...realSetup,
    applyEmployeeSetup: async (db, options) => {
      assert.equal(db, client);
      setup = options.setup;
      if (failSetup) throw new realSetup.EmployeeSetupValidationError('Selected position does not belong to the selected department');
      return { assignment: { id: ID, effective_from: options.setup.effectiveFrom }, policyAssignment: null };
    },
  });
  clearModule(source);
  try {
    const service = require(source);
    await run({ service, calls, client, get setup() { return setup; }, get released() { return released; },
      invoke: body => service.returnEmployeeToService({ connect: async () => client }, {
        employeeId: ID, actorId: ACTOR, payload: body ?? payload, today: '2026-11-16',
      }) });
  } finally { clearModule(source); restore(); }
}

test('return preserves the closed employment period and original hire date in one transaction', async () => {
  await fixture(async f => {
    const result = await f.invoke();
    assert.equal(result.employment_status, 'active');
    assert.equal(result.is_active, true);
    assert.equal(result.date_hired, '2025-01-01');
    assert.equal(result.separation_date, null);
    assert.equal(f.setup.effectiveFrom, '2026-11-16');
    assert.equal(f.setup.assignment.shiftId, ID);
    const history = f.calls.find(c => c.sql.includes('INSERT INTO employee_service_returns'));
    assert.ok(history.values.includes('2025-01-01'));
    assert.ok(history.values.includes('2026-09-15'));
    assert.ok(history.values.includes('2026-11-16'));
    const update = f.calls.find(c => c.sql.includes('UPDATE users'));
    assert.doesNotMatch(update.sql, /date_hired\s*=/);
    assert.match(update.sql, /auth_version\s*=\s*auth_version\s*\+\s*1/);
    assert.ok(f.calls.some(c => c.sql.includes('UPDATE auth_refresh_tokens')));
    assert.ok(f.calls.some(c => c.sql.includes('INSERT INTO audit_logs')));
    assert.equal(f.calls[0].sql, 'BEGIN');
    assert.equal(f.calls.at(-1).sql, 'COMMIT');
    assert.equal(f.released, true);
  });
});

for (const [label, changes] of [
  ['before separation', { returned_on: '2026-09-14' }],
  ['same separation day', { returned_on: '2026-09-15' }],
  ['future date', { returned_on: '2026-11-17' }],
  ['invalid calendar date', { returned_on: '2026-02-31' }],
  ['missing reason', { reason: '' }],
  ['missing assignment', { assignment: null }],
  ['nonboolean eligibility', { leave_credit_eligible: 'true' }],
]) test(`return rejects ${label} without writing employment changes`, async () => {
  await fixture(async f => {
    await assert.rejects(f.invoke({ ...payload, ...changes }), error => error.statusCode === 400);
    assert.equal(f.calls.some(c => /INSERT INTO employee_service_returns|UPDATE users|COMMIT/.test(c.sql)), false);
  });
});

test('an already-active employee cannot be returned again', async () => {
  await fixture(async f => {
    await assert.rejects(f.invoke(), error => error.statusCode === 409);
    assert.equal(f.calls.some(c => c.sql === 'ROLLBACK'), true);
    assert.equal(f.calls.some(c => c.sql === 'COMMIT'), false);
  }, { status: 'active' });
});

test('an expired contract can begin a new service period', async () => {
  await fixture(async f => {
    await f.invoke();
    assert.ok(f.calls.find(c => c.sql.includes('INSERT INTO employee_service_returns')).values.includes('contract_expired'));
    assert.equal(f.calls.at(-1).sql, 'COMMIT');
  }, { status: 'contract_expired' });
});

test('a deceased employee cannot return to service', async () => {
  await fixture(async f => {
    await assert.rejects(f.invoke(), error => error.statusCode === 409 && /deceased/i.test(error.message));
    assert.equal(f.calls.some(c => c.sql.includes('UPDATE users')), false);
  }, { status: 'deceased' });
});

test('a system account cannot be returned as an employee', async () => {
  await fixture(async f => {
    await assert.rejects(f.invoke(), error => error.statusCode === 403);
    assert.equal(f.calls.some(c => c.sql.includes('UPDATE users')), false);
  }, { role: 'super_admin' });
});

test('JO/COS cannot bypass monthly-credit restrictions using the return endpoint', async () => {
  for (const employmentType of ['job_order', 'contract_of_service']) await fixture(async f => {
    await assert.rejects(f.invoke(), /JO\/COS/);
    assert.equal(f.calls.some(c => c.sql.includes('UPDATE users')), false);
  }, { employmentType });
});

test('an invalid assignment rolls back the history and account changes', async () => {
  await fixture(async f => {
    await assert.rejects(f.invoke(), /position/);
    assert.equal(f.calls.at(-1).sql, 'ROLLBACK');
    assert.equal(f.calls.some(c => c.sql === 'COMMIT'), false);
    assert.equal(f.released, true);
  }, { failSetup: true });
});

test('a backdated return queues completed months for reconciliation in the same transaction', async () => {
  await fixture(async f => {
    await f.invoke({ ...payload, returned_on: '2026-10-16' });
    const queued = f.calls.find(c => c.sql.includes('INSERT INTO dtr_month_end_reconciliation_queue'));
    assert.ok(queued);
    assert.equal(queued.values[1], '2026-10-16');
    assert.equal(queued.values[2], '2026-11-16');
    assert.equal(queued.values[3], 'employee_returned_to_service');
    assert.ok(f.calls.indexOf(queued) < f.calls.findIndex(c => c.sql === 'COMMIT'));
  });
});

test('service-period proration excludes gaps and preserves the old final month', async () => {
  const { serviceMonthCredit } = require('../src/services/employeeServicePeriods');
  const periods = [
    { from: '2025-01-01', to: '2026-09-15', eligible: true },
    { from: '2026-11-16', to: null, eligible: true },
  ];
  assert.equal(serviceMonthCredit(periods, '2026-09-01', 1.25).expectedDays, 0.625);
  assert.equal(serviceMonthCredit(periods, '2026-10-01', 1.25).expectedDays, 0);
  assert.equal(serviceMonthCredit(periods, '2026-11-01', 1.25).expectedDays, 0.625);
  assert.equal(serviceMonthCredit(periods, '2026-12-01', 1.25).expectedDays, 1.25);
  assert.equal(serviceMonthCredit([{ ...periods[0] }, { ...periods[1], eligible: false }], '2026-11-01', 1.25).expectedDays, 0);
});

test('multiple returns in a month count only eligible service days once', async () => {
  const { serviceMonthCredit } = require('../src/services/employeeServicePeriods');
  assert.equal(serviceMonthCredit([
    { from: '2026-11-01', to: '2026-11-05', eligible: true },
    { from: '2026-11-16', to: null, eligible: true },
  ], '2026-11-01', 1.25).expectedDays, 0.833);
});
