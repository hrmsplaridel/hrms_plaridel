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
            is_active: params[14], employment_status: params[20],
            leave_credit_eligible: params[22],
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

for (const status of ['resgined', 'unknown', '', '  ', 'ACTIVE', ' active ', null, true, false, 0, 123, [], ['active'], {}]) {
  test(`account creation rejects employment_status=${JSON.stringify(status)} before any side effects`, async () => {
    const { res, queries, connections, hashes, emails } = await create({ ...valid, employment_status: status });
    assert.equal(res.statusCode, 400);
    assert.match(res.body.error, /employment status/i);
    assert.deepEqual(queries, []);
    assert.equal(connections, 0);
    assert.equal(hashes, 0);
    assert.equal(emails, 0);
  });
}

for (const status of [undefined, 'active', 'inactive', 'resigned', 'retired', 'terminated']) {
  test(`account creation preserves ${status === undefined ? 'omitted status active default' : status}`, async () => {
    const body = { ...valid };
    if (status !== undefined) body.employment_status = status;
    if (['resigned', 'retired', 'terminated'].includes(status)) body.separation_date = '2021-01-01';
    const { res, queries, hashes, emails } = await create(body);
    const expectedStatus = status ?? 'active';
    const active = expectedStatus === 'active';
    assert.equal(res.statusCode, 201);
    assert.equal(res.body.employment_status, expectedStatus);
    assert.equal(res.body.is_active, active);
    assert.equal(res.body.leave_credit_eligible, active);
    assert.equal(hashes, 1);
    assert.equal(emails, active ? 1 : 0);
    assert.equal(queries.at(-1).sql, 'COMMIT');
  });
}

test('valid separated statuses still require a final service date', async () => {
  for (const status of ['resigned', 'retired', 'terminated']) {
    const { res, queries, connections, hashes, emails } = await create({ ...valid, employment_status: status });
    assert.equal(res.statusCode, 400);
    assert.match(res.body.error, /separation date is required/i);
    assert.deepEqual(queries, []);
    assert.equal(connections, 0);
    assert.equal(hashes, 0);
    assert.equal(emails, 0);
  }
});
