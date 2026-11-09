const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { once } = require('node:events');
const { createPasswordResetSms } = require('../src/utils/passwordResetSms');

function settings(url, extra = {}) {
  return {
    SMS_PROVIDER: 'smsgate', SMSGATE_URL: url,
    SMSGATE_USERNAME: 'sms', SMSGATE_PASSWORD: 'test-gateway-password',
    SMSGATE_SIM_NUMBER: '2', ...extra,
  };
}

async function gateway(t, handler) {
  const server = http.createServer(handler);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => {
    server.closeAllConnections();
    server.close(resolve);
  }));
  return `http://127.0.0.1:${server.address().port}/message`;
}

test('local SMSGate submits a normalized OTP through SIM 2 and reports acceptance, not delivery', async t => {
  let received;
  const url = await gateway(t, async (req, res) => {
    const parts = [];
    for await (const chunk of req) parts.push(chunk);
    received = { method: req.method, path: req.url, headers: req.headers,
      body: JSON.parse(Buffer.concat(parts).toString()) };
    res.writeHead(202, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ id: 'message-1', state: 'Pending', textMessage: received.body.textMessage }));
  });
  const service = createPasswordResetSms({ env: settings(url) });
  assert.deepEqual(service.getStatus(), { provider: 'smsgate', configured: true });
  const result = await service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5 });
  assert.equal(received.method, 'POST');
  assert.equal(received.path, '/message');
  assert.equal(received.headers.authorization,
    `Basic ${Buffer.from('sms:test-gateway-password').toString('base64')}`);
  assert.deepEqual(received.body, {
    textMessage: { text: 'Your UnityPillar password reset code is 123456. It expires in 5 minutes. Do not share this code.' },
    phoneNumbers: ['+639171234567'], simNumber: 2, ttl: 300,
    priority: 100, withDeliveryReport: true,
  });
  assert.deepEqual(result, { provider: 'smsgate', messageId: 'message-1', state: 'Pending' });
  assert.ok(!JSON.stringify(result).includes('123456'));
});

test('SMSGate supports SIM 1, a custom template, and the exact OTP expiry', async t => {
  let payload;
  const expiresAt = new Date(Date.now() + 300000);
  const url = await gateway(t, async (req, res) => {
    const parts = [];
    for await (const chunk of req) parts.push(chunk);
    payload = JSON.parse(Buffer.concat(parts).toString());
    res.writeHead(202, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ id: 'message-2', state: 'Processed' }));
  });
  const service = createPasswordResetSms({ env: settings(url, {
    SMSGATE_SIM_NUMBER: '1', SMSGATE_PASSWORD_RESET_TEMPLATE: 'Code {otp}; valid {minutes} minutes.',
  }) });
  await service.sendPasswordResetOtpSms({ to: '+639171234567', code: '654321', ttlMinutes: 5, expiresAt });
  assert.equal(payload.simNumber, 1);
  assert.equal(payload.textMessage.text, 'Code 654321; valid 5 minutes.');
  assert.equal(payload.validUntil, expiresAt.toISOString());
  assert.equal(payload.ttl, undefined);
});

test('configuration errors fail closed without selecting UniSMS as a fallback', async t => {
  const cases = [
    { SMSGATE_PASSWORD: '' }, { SMSGATE_USERNAME: '' }, { SMSGATE_USERNAME: 'sms:other' },
    { SMSGATE_URL: '' }, { SMSGATE_URL: 'not a url' },
    { SMSGATE_URL: 'file:///tmp/message' },
    { SMSGATE_URL: 'http://public.example/message' },
    { SMSGATE_URL: 'http://sms:secret@127.0.0.1/message' },
    { SMSGATE_URL: 'http://127.0.0.1/message#secret' },
    { SMSGATE_SIM_NUMBER: '0' }, { SMSGATE_SIM_NUMBER: '2abc' },
    { SMSGATE_TIMEOUT_MS: '-1' }, { SMSGATE_TIMEOUT_MS: '60000' },
    { SMS_PROVIDER: 'unknown' },
  ];
  for (const extra of cases) await t.test(JSON.stringify(extra), async () => {
    let fallbackCalls = 0;
    const service = createPasswordResetSms({ env: settings('http://127.0.0.1:8080/message', extra),
      uniSms: { isUniSmsConfigured: () => true, sendPasswordResetOtpSms: async () => fallbackCalls++ } });
    assert.equal(service.getStatus().configured, false);
    await assert.rejects(service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5 }),
      { code: 'SMS_CONFIGURATION_ERROR' });
    assert.equal(fallbackCalls, 0);
  });
});

test('UniSMS remains the default provider and delegates its existing API unchanged', async () => {
  const args = { to: '09171234567', code: '123456', ttlMinutes: 5 };
  let received;
  const service = createPasswordResetSms({ env: {}, uniSms: {
    isUniSmsConfigured: () => true,
    sendPasswordResetOtpSms: async value => { received = value; return { provider: 'unisms' }; },
  } });
  assert.deepEqual(service.getStatus(), { provider: 'unisms', configured: true });
  assert.deepEqual(await service.sendPasswordResetOtpSms(args), { provider: 'unisms' });
  assert.equal(received, args);
});

test('invalid phone numbers and expired OTPs are rejected before contacting the gateway', async t => {
  let requests = 0;
  const url = await gateway(t, (_req, res) => { requests++; res.end('{}'); });
  const service = createPasswordResetSms({ env: settings(url) });
  await assert.rejects(service.sendPasswordResetOtpSms({ to: '63997191049', code: '123456', ttlMinutes: 5 }),
    { code: 'INVALID_PH_MOBILE_NUMBER' });
  await assert.rejects(service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5,
    expiresAt: new Date(Date.now() - 1000) }), { code: 'SMS_INVALID_OTP' });
  assert.equal(requests, 0);
});

test('HTTP failures, redirects, invalid responses and failed recipients do not expose message data', async t => {
  const cases = [
    [401, 'password=test-gateway-password; otp=123456'],
    [500, 'private provider error 123456'],
    [302, 'redirect'], [202, 'not json'], [200, '{}'],
    [202, JSON.stringify({ id: 'rejected', state: 'Failed', error: '123456' })],
    [202, JSON.stringify({ id: 'rejected', state: 'Pending', recipients: [{ state: 'Failed', error: '123456' }] })],
  ];
  for (const [status, body] of cases) await t.test(`${status} ${body.slice(0, 20)}`, async sub => {
    const url = await gateway(sub, (_req, res) => {
      res.writeHead(status, { Location: 'http://127.0.0.1:1/steal' }); res.end(body);
    });
    const service = createPasswordResetSms({ env: settings(url) });
    await assert.rejects(service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5 }), error => {
      assert.ok(!error.message.includes('123456'));
      assert.ok(!error.message.includes('test-gateway-password'));
      assert.ok(!error.message.includes('639171234567'));
      return true;
    });
  });
});

test('a stalled gateway times out without retrying the SMS', async t => {
  let requests = 0;
  const url = await gateway(t, () => { requests++; });
  const service = createPasswordResetSms({ env: settings(url, { SMSGATE_TIMEOUT_MS: '100' }) });
  await assert.rejects(service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5 }),
    { code: 'SMSGATE_TIMEOUT' });
  assert.equal(requests, 1);
});

test('an oversized gateway response is rejected', async t => {
  const url = await gateway(t, (_req, res) => { res.writeHead(202); res.end('x'.repeat(70000)); });
  const service = createPasswordResetSms({ env: settings(url) });
  await assert.rejects(service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5 }),
    { code: 'SMSGATE_RESPONSE_ERROR' });
});
