const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createPasswordResetSms } = require('../src/utils/passwordResetSms');

test.beforeEach(t => {
  // Cloud tests must never contact the public relay or a physical phone.
  for (const transport of [require('node:http'), require('node:https')]) {
    t.mock.method(transport, 'request', () => { throw new Error('Network is disabled in Cloud unit tests'); });
  }
});

const passphrase = 'Only-a-test-passphrase-2026!';
const cloudEnv = {
  SMS_PROVIDER: 'smsgate', SMSGATE_MODE: 'cloud',
  SMSGATE_URL: 'https://api.sms-gate.app/3rdparty/v1/messages',
  SMSGATE_USERNAME: 'cloud-user', SMSGATE_PASSWORD: 'cloud-password',
  SMSGATE_DEVICE_ID: 'specific-phone-2', SMSGATE_SIM_NUMBER: '2',
  SMSGATE_ENCRYPTION_PASSPHRASE: passphrase,
};

// Independent receiver, following SMSGate's documented five-part wire format.
function decryptLikePhone(value, secret = passphrase) {
  const parts = value.split('$');
  assert.equal(parts.length, 5);
  assert.equal(parts[0], '');
  assert.equal(parts[1], 'aes-256-cbc/pbkdf2-sha1');
  const iterations = Number(parts[2].slice(2));
  assert.equal(parts[2], `i=${iterations}`);
  const salt = Buffer.from(parts[3], 'base64');
  assert.equal(salt.length, 16);
  const key = crypto.pbkdf2Sync(secret, salt, iterations, 32, 'sha1');
  const decipher = crypto.createDecipheriv('aes-256-cbc', key, salt);
  return Buffer.concat([decipher.update(Buffer.from(parts[4], 'base64')), decipher.final()]).toString('utf8');
}

test('cloud encrypts the OTP text and recipient separately and targets the configured phone/SIM', async () => {
  let received;
  const service = createPasswordResetSms({ env: { ...cloudEnv }, sendMessage: async (config, payload) => {
    received = { config, payload };
    return { provider: 'smsgate', messageId: 'cloud-message', state: 'Pending' };
  } });
  const expiresAt = new Date(Date.now() + 300000);
  const result = await service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5, expiresAt });
  assert.equal(received.config.url.href, cloudEnv.SMSGATE_URL);
  assert.equal(received.config.username, cloudEnv.SMSGATE_USERNAME);
  assert.equal(received.config.password, cloudEnv.SMSGATE_PASSWORD);
  const payload = received.payload;
  assert.equal(payload.isEncrypted, true);
  assert.equal(payload.deviceId, cloudEnv.SMSGATE_DEVICE_ID);
  assert.equal(payload.simNumber, 2);
  assert.equal(payload.validUntil, expiresAt.toISOString());
  assert.equal(payload.priority, 100);
  assert.equal(decryptLikePhone(payload.textMessage.text),
    'Your UnityPillar password reset code is 123456. It expires in 5 minutes. Do not share this code.');
  assert.equal(decryptLikePhone(payload.phoneNumbers[0]), '+639171234567');
  assert.notEqual(payload.textMessage.text.split('$')[3], payload.phoneNumbers[0].split('$')[3]);
  assert.ok(!JSON.stringify(payload).includes('123456'));
  assert.ok(!JSON.stringify(payload).includes('639171234567'));
  assert.ok(!JSON.stringify(payload).includes(passphrase));
  assert.ok(!JSON.stringify(result).includes(passphrase));
});

test('fresh salts vary ciphertext across messages and custom Unicode text decrypts correctly', async () => {
  const payloads = [];
  const service = createPasswordResetSms({ env: { ...cloudEnv,
    SMSGATE_ENCRYPTION_ITERATIONS: '75000', SMSGATE_PASSWORD_RESET_TEMPLATE: 'HRMS código {otp} — {minutes} minuto.',
  }, sendMessage: async (_config, payload) => { payloads.push(payload); return { state: 'Pending' }; } });
  for (let n = 0; n < 2; n++) await service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5 });
  assert.equal(decryptLikePhone(payloads[0].textMessage.text), 'HRMS código 123456 — 5 minuto.');
  assert.notEqual(payloads[0].textMessage.text, payloads[1].textMessage.text);
  assert.notEqual(payloads[0].phoneNumbers[0], payloads[1].phoneNumbers[0]);
  assert.match(payloads[0].textMessage.text, /^\$aes-256-cbc\/pbkdf2-sha1\$i=75000\$/);
  assert.throws(() => decryptLikePhone(payloads[0].textMessage.text, 'wrong-passphrase'));
});

test('public SMSGate host automatically requires Cloud encryption even if mode is omitted', async () => {
  let payload;
  const env = { ...cloudEnv };
  delete env.SMSGATE_MODE;
  const service = createPasswordResetSms({ env, sendMessage: async (_config, body) => { payload = body; return {}; } });
  await service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5 });
  assert.equal(payload.isEncrypted, true);
});

test('Cloud configuration fails closed before any network send and never falls back to UniSMS', async t => {
  const cases = [
    { SMSGATE_ENCRYPTION_PASSPHRASE: '' },
    { SMSGATE_ENCRYPTION_PASSPHRASE: 'short' },
    { SMSGATE_DEVICE_ID: '' },
    { SMSGATE_MODE: 'local' },
    { SMSGATE_MODE: 'typo' },
    { SMSGATE_URL: 'http://192.168.1.3:8080/message' },
    { SMSGATE_ENCRYPTION_ITERATIONS: '100' },
    { SMSGATE_ENCRYPTION_ITERATIONS: '75000oops' },
    { SMSGATE_ENCRYPTION_ITERATIONS: '2000001' },
  ];
  for (const extra of cases) await t.test(Object.keys(extra)[0] + '=' + (extra.SMSGATE_MODE || 'invalid'), async () => {
    let calls = 0;
    const service = createPasswordResetSms({ env: { ...cloudEnv, ...extra },
      sendMessage: async () => calls++, uniSms: { sendPasswordResetOtpSms: async () => calls++ } });
    assert.equal(service.getStatus().configured, false);
    await assert.rejects(service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5 }),
      { code: 'SMS_CONFIGURATION_ERROR' });
    assert.equal(calls, 0);
  });
});

test('local mode keeps working and can also encrypt when the phone passphrase is configured', async () => {
  let received;
  const env = { ...cloudEnv, SMSGATE_MODE: 'local', SMSGATE_URL: 'http://192.168.1.3:8080/message' };
  const service = createPasswordResetSms({ env, sendMessage: async (_config, payload) => { received = payload; return {}; } });
  await service.sendPasswordResetOtpSms({ to: '09171234567', code: '123456', ttlMinutes: 5 });
  assert.equal(received.isEncrypted, true);
  assert.equal(decryptLikePhone(received.phoneNumbers[0]), '+639171234567');
});
