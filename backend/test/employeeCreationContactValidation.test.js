const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
const { normalizePhilippinesMobileNumber } = require('../src/utils/passwordResetSms');

const valid = {
  email: 'employee@example.gov.ph', first_name: 'Test', last_name: 'Employee',
  full_name: 'Test Employee', date_hired: '2020-01-01', password: 'StrongPass12!',
};

async function create(body) {
  const queries = [];
  let connections = 0, hashes = 0, emails = 0;
  const client = {
    async query(sql, params = []) {
      queries.push({ sql, params });
      if (sql.includes('nextval')) return { rows: [{ n: 123 }] };
      if (sql.includes('INSERT INTO users')) return {
        rows: [{ id: '22222222-2222-4222-8222-222222222222', email: params[0],
          role: params[2], full_name: params[4], is_active: params[14], contact_number: params[10] }],
      };
      return { rows: [], rowCount: 0 };
    },
    release() {},
  };
  const restores = [
    withMockedModule('../src/config/db', { pool: {
      async connect() { connections++; return client; },
      async query() { throw new Error('Creation must use its transaction client'); },
    } }),
    withMockedModule('bcrypt', { async hash() { hashes++; return 'test-password-hash'; } }),
    withMockedModule('../src/utils/smtpMail', {
      isSmtpConfigured: () => true, async sendSmtpMail() { emails++; },
    }),
  ];
  const routePath = '../src/routes/employees';
  clearModule(routePath);
  try {
    const handler = require(routePath).stack.find(
      (layer) => layer.route?.path === '/' && layer.route.methods.post,
    ).route.stack.at(-1).handle;
    const res = {
      statusCode: 200, status(code) { this.statusCode = code; return this; },
      json(body) { this.body = body; return this; },
    };
    await handler({ user: { id: '11111111-1111-4111-8111-111111111111', role: 'super_admin' }, body }, res);
    return { res, queries, connections, hashes, emails };
  } finally {
    clearModule(routePath);
    restores.reverse().forEach((restore) => restore());
  }
}

for (const contact of ['abc', '12345', '0917123456', '091712345678', '0212345678', '+19171234567',
  'call 09171234567', '09171234567 ext. 1', '0917/123/4567', '++639171234567', '63917+1234567',
  9171234567, false, [], {}]) {
  test(`account creation rejects invalid contact_number=${JSON.stringify(contact)} before side effects`, async () => {
    const { res, queries, connections, hashes, emails } = await create({ ...valid, contact_number: contact });
    assert.equal(res.statusCode, 400);
    assert.match(res.body.error, /contact.number/i);
    assert.deepEqual(queries, []);
    assert.equal(connections, 0);
    assert.equal(hashes, 0);
    assert.equal(emails, 0);
  });
}

for (const contact of ['09171234567', '9171234567', '639171234567', '+639171234567', '00639171234567',
  '0917 123 4567', '+63 (917) 123-4567', ' 0917-123-4567 ', '0917.123.4567']) {
  test(`created contact ${JSON.stringify(contact)} remains usable by SMS recovery`, async () => {
    const { res, queries } = await create({ ...valid, contact_number: contact });
    assert.equal(res.statusCode, 201);
    assert.equal(res.body.contact_number, contact.trim());
    assert.equal(normalizePhilippinesMobileNumber(res.body.contact_number), '639171234567');
    assert.equal(queries.at(-1).sql, 'COMMIT');
  });
}

for (const contact of [undefined, null, '', '  ']) {
  test(`account creation keeps contact optional for ${JSON.stringify(contact)}`, async () => {
    const body = { ...valid };
    if (contact !== undefined) body.contact_number = contact;
    const { res, queries } = await create(body);
    assert.equal(res.statusCode, 201);
    assert.equal(res.body.contact_number, null);
    assert.equal(queries.at(-1).sql, 'COMMIT');
  });
}
