const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('forgot-password uses the selected SMS adapter while preserving privacy, cooldown and rollback', async t => {
  process.env.JWT_SECRET = 'isolated-sms-route-test-secret';
  let exists = true, recent = false, rejectSend = false;
  const queries = [], messages = [];
  let released = 0;
  const client = {
    async query(sql, params) {
      queries.push({ sql, params });
      if (sql.includes('SELECT id, email, full_name, contact_number, is_active')) return { rows: exists ? [{
        id: 'test-user', email: 'employee@test.local', contact_number: '09171234567', is_active: true,
      }] : [] };
      if (sql.includes('SELECT id FROM auth_password_reset_otps')) return { rowCount: recent ? 1 : 0, rows: [] };
      return { rows: [], rowCount: 0 };
    },
    release() { released++; },
  };
  const restores = [
    withMockedModule('../src/config/db', { pool: { query: async () => ({ rows: [], rowCount: 0 }), connect: async () => client } }),
    withMockedModule('../src/utils/passwordResetSms', {
      normalizePhilippinesMobileNumber: require('../src/utils/uniSmsSms').normalizePhilippinesMobileNumber,
      async sendPasswordResetOtpSms(args) {
        messages.push(args);
        if (rejectSend) throw new Error('sensitive gateway response');
        return { provider: 'smsgate', messageId: 'queued-message', state: 'Pending' };
      },
    }),
  ];
  clearModule('../src/routes/auth');
  t.after(() => { clearModule('../src/routes/auth'); restores.reverse().forEach(restore => restore()); });
  const router = require('../src/routes/auth');
  const handler = router.stack.find(entry => entry.route?.path === '/forgot-password').route.stack.at(-1).handle;
  async function request() {
    const res = { statusCode: 200, status(value) { this.statusCode = value; return this; }, json(value) { this.body = value; } };
    await handler({ body: { email: 'employee@test.local' }, ip: '127.0.0.1' }, res);
    return res;
  }

  const success = await request();
  assert.equal(success.statusCode, 200);
  assert.equal(messages.length, 1);
  assert.equal(messages[0].to, '639171234567');
  assert.match(messages[0].code, /^\d{6}$/);
  assert.ok(messages[0].expiresAt instanceof Date);
  const insert = queries.find(row => row.sql.includes('INSERT INTO auth_password_reset_otps'));
  assert.notEqual(insert.params[1], messages[0].code);
  assert.ok(!JSON.stringify(queries).includes(messages[0].code));
  assert.ok(!JSON.stringify(success.body).includes(messages[0].code));
  assert.ok(queries.some(row => row.sql === 'COMMIT'));

  recent = true;
  queries.length = 0;
  const cooldown = await request();
  assert.deepEqual(cooldown.body, success.body);
  assert.equal(messages.length, 1);
  assert.ok(!queries.some(row => row.sql.includes('INSERT INTO auth_password_reset_otps')));

  recent = false; rejectSend = true; queries.length = 0;
  const failed = await request();
  assert.deepEqual(failed.body, success.body);
  assert.ok(queries.some(row => row.sql === 'ROLLBACK'));
  assert.ok(!queries.some(row => row.sql === 'COMMIT'));
  exists = false;
  const missing = await request();
  assert.deepEqual(missing.body, success.body);
  assert.equal(messages.length, 2);
  assert.equal(released, 4);
});
