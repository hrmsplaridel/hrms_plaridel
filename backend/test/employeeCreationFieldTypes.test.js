const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const valid = {
  email: 'employee@example.gov.ph',
  first_name: 'Test',
  last_name: 'Employee',
  full_name: 'Test Employee',
  date_hired: '2020-01-01',
  password: 'StrongPass12!',
};

async function create(body) {
  const queries = [];
  let connections = 0;
  let hashes = 0;
  let emails = 0;
  const client = {
    async query(sql, params = []) {
      queries.push({ sql, params });
      if (sql.includes('nextval')) return { rows: [{ n: 123 }] };
      if (sql.includes('INSERT INTO users')) {
        return {
          rows: [{
            id: '22222222-2222-4222-8222-222222222222',
            email: params[0], role: params[2], full_name: params[4],
            is_active: params[14], salary_grade: params[17], biometric_user_id: params[21],
          }],
        };
      }
      return { rows: [], rowCount: 0 };
    },
    release() {},
  };
  const restores = [
    withMockedModule('../src/config/db', {
      pool: {
        async connect() { connections++; return client; },
        async query() { throw new Error('Creation must use its transaction client'); },
      },
    }),
    withMockedModule('bcrypt', {
      async hash() { hashes++; return 'test-password-hash'; },
    }),
    withMockedModule('../src/utils/smtpMail', {
      isSmtpConfigured: () => true,
      async sendSmtpMail() { emails++; },
    }),
  ];
  const routePath = '../src/routes/employees';
  clearModule(routePath);
  try {
    const handler = require(routePath).stack.find(
      (layer) => layer.route?.path === '/' && layer.route.methods.post,
    ).route.stack.at(-1).handle;
    const res = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(body) { this.body = body; return this; },
    };
    await handler({
      user: { id: '11111111-1111-4111-8111-111111111111', role: 'super_admin' },
      body,
    }, res);
    return { res, queries, connections, hashes, emails };
  } finally {
    clearModule(routePath);
    restores.reverse().forEach((restore) => restore());
  }
}

for (const [field, label] of [['salary_grade', 'Salary grade'], ['biometric_user_id', 'Biometric User ID']]) {
  for (const value of [0, 12, 1001, 1.5, true, false, [], ['12'], {}]) {
    test(`account creation rejects non-text ${field}=${JSON.stringify(value)} before any side effects`, async (t) => {
      t.mock.method(console, 'error', () => {});
      const { res, queries, connections, hashes, emails } = await create({ ...valid, [field]: value });
      assert.equal(res.statusCode, 400);
      assert.equal(res.body.error, `${label} must be text or null`);
      assert.deepEqual(queries, []);
      assert.equal(connections, 0);
      assert.equal(hashes, 0);
      assert.equal(emails, 0);
    });
  }

  for (const value of [undefined, null, '', '  ', '12', '  001001  ']) {
    test(`account creation preserves optional text ${field}=${JSON.stringify(value)}`, async () => {
      const body = { ...valid };
      if (value !== undefined) body[field] = value;
      const { res, queries, connections, hashes, emails } = await create(body);
      assert.equal(res.statusCode, 201);
      assert.equal(res.body[field], value?.trim() || null);
      assert.equal(connections, 1);
      assert.equal(hashes, 1);
      assert.equal(emails, 1);
      assert.equal(queries.at(-1).sql, 'COMMIT');
    });
  }
}

test('account creation accepts both text fields together and preserves leading zeroes', async () => {
  const { res, queries } = await create({ ...valid, salary_grade: ' 12 ', biometric_user_id: ' 001001 ' });
  assert.equal(res.statusCode, 201);
  assert.equal(res.body.salary_grade, '12');
  assert.equal(res.body.biometric_user_id, '001001');
  assert.equal(queries.at(-1).sql, 'COMMIT');
});
