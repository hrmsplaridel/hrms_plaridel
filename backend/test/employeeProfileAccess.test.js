const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const actor = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const employee = {
  id: other, full_name: 'Sample Employee', role: 'employee',
  avatar_path: 'avatar.png', current_department_name: 'Finance',
  current_position_name: 'Staff', email: 'sample@example.invalid',
  date_of_birth: '1990-01-02', address: 'Private address',
  contact_number: 'Private phone', biometric_user_id: '42', salary_grade: 12,
};
const directoryFields = [
  'id', 'full_name', 'avatar_path', 'current_department_name', 'current_position_name',
];

async function invoke({ role = 'admin', access = false, accessError = false, path = '/', query = {}, self = false } = {}) {
  const calls = [];
  const restore = withMockedModule('../src/config/db', { pool: {
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.includes('FROM dtr_admin_access')) {
        if (accessError) throw new Error('Permission database unavailable');
        return { rows: access === null ? [] : [{ employees_allowed: access }] };
      }
      if (sql.includes('COUNT(*)')) return { rows: [{ c: 1 }] };
      if (sql.includes('FROM users u')) return { rows: [{ ...employee, id: self ? actor : other }] };
      throw new Error(`Unexpected query: ${sql}`);
    },
  } });
  const modules = ['../src/middleware/dtrAccess', '../src/routes/employees'];
  modules.forEach(clearModule);
  try {
    const route = require('../src/routes/employees').stack.find(l => l.route?.path === path && l.route.methods.get).route;
    const req = { user: { id: actor, role }, query, params: { id: self ? actor : other } };
    const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
    async function dispatch(index) {
      if (index >= route.stack.length) return;
      let next;
      await route.stack[index].handle(req, res, () => { next = dispatch(index + 1); return next; });
      if (next) await next;
    }
    await dispatch(1); // Authentication is supplied; run every authorization handler.
    return { res, calls };
  } finally {
    modules.forEach(clearModule);
    restore();
  }
}

for (const query of [{}, { limit: '10' }, { biometric_user_ids: '42' }]) {
  for (const access of [false, null]) {
    test(`restricted admin receives only employee directory fields: ${JSON.stringify({ query, access })}`, async () => {
      const { res, calls } = await invoke({ query, access });
      assert.equal(res.code, 200);
      const rows = res.body.employees || res.body;
      assert.equal(rows.length, 1);
      assert.deepEqual(Object.keys(rows[0]).sort(), [...directoryFields].sort());
      assert.equal(rows[0].full_name, employee.full_name);
      if (query.limit) assert.equal(res.body.total, 1);
      assert.ok(calls.some(c => c.sql.includes('FROM dtr_admin_access') && c.params[0] === actor));
    });
  }
  test(`employee-management permission retains private list fields: ${JSON.stringify(query)}`, async () => {
    const { res } = await invoke({ query, access: true });
    assert.equal(res.code, 200);
    const row = (res.body.employees || res.body)[0];
    for (const field of ['address', 'date_of_birth', 'contact_number', 'email', 'biometric_user_id', 'salary_grade']) {
      assert.equal(row[field], employee[field]);
    }
  });
}

for (const access of [false, null]) {
  test(`restricted admin cannot read another private profile: access=${access}`, async () => {
    const { res } = await invoke({ path: '/:id', access });
    assert.equal(res.code, 200);
    assert.deepEqual(Object.keys(res.body).sort(), [...directoryFields].sort());
  });
}

test('employee-management permission retains another employee private profile', async () => {
  const { res } = await invoke({ path: '/:id', access: true });
  assert.equal(res.code, 200);
  for (const field of ['address', 'date_of_birth', 'contact_number', 'email', 'salary_grade']) {
    assert.equal(res.body[field], employee[field]);
  }
});

for (const role of ['employee', 'admin']) {
  test(`${role} retains own private profile without employee-management access`, async () => {
    const { res, calls } = await invoke({ role, path: '/:id', self: true, accessError: true });
    assert.equal(res.code, 200);
    assert.equal(res.body.address, employee.address);
    assert.equal(calls.some(c => c.sql.includes('FROM dtr_admin_access')), false);
  });
}

test('ordinary employee retains redacted directory access', async () => {
  for (const path of ['/', '/:id']) {
    const { res } = await invoke({ role: 'employee', path });
    assert.equal(res.code, 200);
    assert.deepEqual(Object.keys(path === '/' ? res.body[0] : res.body).sort(), [...directoryFields].sort());
  }
});

test('super-admin retains private profile access', async () => {
  for (const path of ['/', '/:id']) {
    const { res } = await invoke({ role: 'super_admin', path });
    assert.equal(res.code, 200);
    assert.equal((path === '/' ? res.body[0] : res.body).address, employee.address);
  }
});

test('employee data fails closed when admin permissions cannot be verified', async t => {
  t.mock.method(console, 'error', () => {});
  for (const path of ['/', '/:id']) {
    const { res } = await invoke({ path, accessError: true });
    assert.ok(res.code >= 500);
    assert.equal(res.body.address, undefined);
    assert.equal(Array.isArray(res.body), false);
  }
});
