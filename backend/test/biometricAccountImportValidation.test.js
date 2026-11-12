const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const valid = {
  biometric_user_id: '1001',
  full_name: 'Imported Employee',
  email: 'employee@example.gov.ph',
  password: 'StrongPass12!',
  role: 'employee',
};

async function invoke(body, { duplicateField } = {}) {
  const queries = [];
  const passwords = [];
  const restores = [
    withMockedModule('../src/config/db', {
      pool: {
        async query(sql, params) {
          queries.push({ sql, params });
          if (sql.includes('nextval')) return { rows: [{ n: 123 }] };
          if (sql.includes('INSERT INTO users')) return { rows: [{ id: 'imported-id' }], rowCount: 1 };
          if (duplicateField && sql.includes(`WHERE ${duplicateField} =`)) {
            return { rows: [{ id: 'existing-id' }], rowCount: 1 };
          }
          return { rows: [], rowCount: 0 };
        },
      },
    }),
    withMockedModule('bcrypt', {
      async hash(password) {
        passwords.push(password);
        return 'test-password-hash';
      },
    }),
  ];
  const routePath = '../src/routes/biometricDevices';
  clearModule(routePath);
  try {
    const route = require(routePath).stack.find(
      (layer) => layer.route?.path === '/:id/import-user' && layer.route.methods.post,
    ).route;
    const res = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(value) { this.body = value; return this; },
    };
    await route.stack.at(-1).handle({ params: { id: 'device-id' }, body }, res);
    return { res, queries, passwords };
  } finally {
    clearModule(routePath);
    restores.reverse().forEach((restore) => restore());
  }
}

for (const [field, values, error] of [
  ['biometric_user_id', [undefined, null, '', '  ', 123, false, [], {}], /biometric/i],
  ['full_name', [undefined, null, '', '  ', 123, false, [], {}], /full name/i],
  ['email', [undefined, null, '', '  ', 'invalid', 'a b@example.test', 'a@@example.test', `${'a'.repeat(245)}@example.test`, 123, false, [], {}], /email/i],
  ['password', [undefined, null, '', '  ', 'x', 'StrongPas1!', 'strongpass12!', 'STRONGPASS12!', 'StrongPassword!', 'StrongPass123', '  Aa1!short  ', 123, false, [], {}], /password/i],
]) {
  for (const value of values) {
    test(`biometric account import rejects ${field}=${JSON.stringify(value)} before database access`, async (t) => {
      t.mock.method(console, 'error', () => {});
      const { res, queries, passwords } = await invoke({ ...valid, [field]: value });
      assert.equal(res.statusCode, 400);
      assert.match(res.body.error, error);
      assert.deepEqual(queries, []);
      assert.deepEqual(passwords, []);
    });
  }
}

for (const role of ['employee', 'admin']) {
  test(`valid biometric import normalizes identity and keeps the ${role} account inactive`, async () => {
    const password = ' StrongPass12! ';
    const { res, queries, passwords } = await invoke({
      ...valid, role, password,
      biometric_user_id: '  001001  ',
      full_name: '  Imported Employee  ',
      email: '  Employee@Example.Gov.Ph  ',
    });
    assert.equal(res.statusCode, 201);
    assert.equal(res.body.id, 'imported-id');
    assert.deepEqual(passwords, [password], 'Do not silently alter the submitted password');
    const insert = queries.find(({ sql }) => sql.includes('INSERT INTO users'));
    assert.deepEqual(insert.params, ['employee@example.gov.ph', 'test-password-hash', role, 'Imported Employee', 123, '001001']);
    assert.match(insert.sql, /\$4, false,/);
    assert.equal(queries[0].params[0], '001001');
    assert.equal(queries[1].params[0], 'employee@example.gov.ph');
  });
}

for (const duplicateField of ['biometric_user_id', 'email']) {
  test(`biometric import preserves ${duplicateField} duplicate rejection`, async () => {
    const { res, queries, passwords } = await invoke(valid, { duplicateField });
    assert.equal(res.statusCode, 409);
    assert.equal(queries.some(({ sql }) => sql.includes('INSERT INTO users')), false);
    assert.deepEqual(passwords, []);
  });
}
