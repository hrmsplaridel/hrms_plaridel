const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const security = require('../src/services/employeeAccountSecurity');
const { validateCreateEmployeePayload } = require('../src/utils/employeeAccountValidation');
const ID = '11111111-1111-4111-8111-111111111111';
const ACTOR = '22222222-2222-4222-8222-222222222222';
const current = { id: ID, date_of_birth: '1990-02-10', date_hired: '2024-01-01',
  employment_type: 'permanent', employment_status: 'active', leave_credit_eligible: true };

test.beforeEach(t => t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-11-02T04:00:00Z') }));

async function invoke(body, { locked = current } = {}) {
  const calls = [], writes = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params, transaction: true });
      if (sql.includes('FROM users')) return { rowCount: 1, rows: [locked] };
      if (sql.startsWith('UPDATE users SET')) {
        writes.push({ sql, params });
        const saved = { ...current };
        for (const match of sql.matchAll(/\b([a-z_]+)\s*=\s*\$(\d+)/g)) saved[match[1]] = params[Number(match[2]) - 1];
        return { rowCount: 1, rows: [saved] };
      }
      return { rowCount: 0, rows: [] };
    },
    release() { calls.push({ sql: 'release' }); },
  };
  const restores = [
    withMockedModule('../src/config/db', { pool: {
      query: async sql => { calls.push({ sql, transaction: false }); return { rowCount: 1, rows: [current] }; },
      connect: async () => client,
    } }),
    withMockedModule('../src/services/employeeAccountSecurity', {
      ...security,
      lockAndValidateAccountTransition: async () => {
        calls.push({ sql: 'security lock', transaction: true });
        return { changed: false, revokeSessions: false };
      },
    }),
  ];
  clearModule('../src/routes/employees');
  try {
    const handler = require('../src/routes/employees').stack.find(l => l.route?.path === '/:id' && l.route.methods.put).route.stack.at(-1).handle;
    const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
    await handler({ user: { id: ACTOR, role: 'admin' }, params: { id: ID }, body }, res);
    return { res, calls, writes };
  } finally {
    clearModule('../src/routes/employees');
    restores.reverse().forEach(restore => restore());
  }
}

for (const field of ['first_name', 'last_name', 'full_name']) {
  for (const value of ['', '  ', null, false, 123, [], {}]) {
    test(`employee edit rejects invalid ${field} ${JSON.stringify(value)}`, async () => {
      const { res, writes } = await invoke({ [field]: value });
      assert.equal(res.code, 400);
      assert.match(res.body.error, /name/i);
      assert.deepEqual(writes, []);
    });
  }
}
for (const value of ['not-an-email', '', '  ', null, true, [], {}, `${'a'.repeat(245)}@example.test`]) {
  test(`employee edit rejects invalid email ${JSON.stringify(value)}`, async () => {
    const { res, writes } = await invoke({ email: value });
    assert.equal(res.code, 400);
    assert.match(res.body.error, /email/i);
    assert.deepEqual(writes, []);
  });
}

for (const [field, values] of [
  ['date_of_birth', ['2099-01-01', '2026-02-30', '2000-01-01T00:00:00Z', ['1990-01-01'], 123, {}]],
  ['date_hired', ['2026-02-30', '2025-01-01T00:00:00Z', ['2025-01-01'], false, {}]],
]) {
  for (const value of values) {
    test(`employee edit rejects invalid ${field} ${JSON.stringify(value)}`, async () => {
      const { res, writes } = await invoke({ [field]: value });
      assert.equal(res.code, 400);
      assert.match(res.body.error, /birth|hired/i);
      assert.deepEqual(writes, []);
    });
  }
}
for (const field of ['middle_name', 'suffix', 'sex', 'contact_number', 'address', 'civil_status', 'nationality', 'avatar_path']) {
  test(`employee edit rejects non-text optional ${field}`, async () => {
    const { res, writes } = await invoke({ [field]: { unexpected: true } });
    assert.equal(res.code, 400);
    assert.deepEqual(writes, []);
  });
}

for (const body of [{ date_of_birth: '2025-01-01' }, { date_hired: '1989-01-01' },
  { date_of_birth: '2024-01-01', date_hired: '2024-01-01' }]) {
  test(`employee edit checks merged birth/hire chronology ${JSON.stringify(body)}`, async () => {
    const { res, writes } = await invoke(body);
    assert.equal(res.code, 400);
    assert.match(res.body.error, /birth.*hired|hired.*birth/i);
    assert.deepEqual(writes, []);
  });
}

for (const body of [{ email: ' new.email@example.test ' }, { first_name: 'María', last_name: "O'Neil", full_name: "María O'Neil" },
  { contact_number: '+63 912 345 6789' }, { date_of_birth: '1988-02-29' },
  { date_of_birth: '2020-01-01', date_hired: '2021-01-01' }]) {
  test(`employee edit preserves valid partial profile updates ${JSON.stringify(body)}`, async () => {
    const { res, writes, calls } = await invoke(body);
    assert.equal(res.code, 200);
    assert.equal(writes.length, 1);
    for (const [key, value] of Object.entries(body)) assert.equal(res.body[key], typeof value === 'string' ? value.trim() : value);
    assert.equal(calls.some(c => c.sql === 'COMMIT'), true);
  });
}

for (const empty of [null, '']) {
  test(`employee edit allows intentional optional clearing ${JSON.stringify(empty)}`, async () => {
    const body = { middle_name: empty, suffix: empty, sex: empty, contact_number: empty,
      address: empty, date_of_birth: empty, date_hired: empty };
    const { res, writes } = await invoke(body);
    assert.equal(res.code, 200);
    assert.equal(writes.length, 1);
    assert.equal(res.body.date_of_birth, null);
    assert.equal(res.body.date_hired, null);
    assert.equal(res.body.middle_name, empty);
  });
}

for (const [body, locked] of [
  [{ date_of_birth: '2000-01-01' }, { ...current, date_hired: '1999-01-01' }],
  [{ date_hired: '2000-01-01' }, { ...current, date_of_birth: '2005-01-01' }],
]) {
  test(`concurrent date edit is revalidated under the account lock ${JSON.stringify(body)}`, async t => {
    t.mock.method(console, 'error', () => {});
    const { res, writes, calls } = await invoke(body, { locked });
    assert.equal(res.code, 400);
    assert.match(res.body.error, /birth.*hired|hired.*birth/i);
    assert.deepEqual(writes, []);
    assert.equal(calls.some(c => c.sql === 'ROLLBACK'), true);
    assert.equal(calls.some(c => c.sql === 'COMMIT'), false);
  });
}

for (const birth of ['2099-01-01', '2025-01-01', '2024-01-01']) {
  test(`account creation shares birth chronology validation for ${birth}`, () => {
    const error = validateCreateEmployeePayload({ email: 'person@example.test', first_name: 'Test', last_name: 'Employee',
      full_name: 'Test Employee', date_hired: '2024-01-01', date_of_birth: birth });
    assert.match(error || '', /birth/i);
  });
}
