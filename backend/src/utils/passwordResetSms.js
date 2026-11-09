'use strict';

const http = require('node:http');
const https = require('node:https');
const legacySms = require('./uniSmsSms');
const { encryptSmsGateField } = require('./smsGateEncryption');

const { normalizePhilippinesMobileNumber } = legacySms;
const smsError = (code, message) => Object.assign(new Error(message), { code });

// Local Server uses HTTP Basic auth. Only allow cleartext transport to private
// addresses; remote/public integrations must use HTTPS and be configured separately.
function privateHost(hostname) {
  if (hostname === 'localhost' || hostname === '[::1]' || /^\[f[cd][0-9a-f:]+\]$/i.test(hostname)) return true;
  const parts = hostname.split('.');
  if (parts.length !== 4 || parts.some(part => !/^\d{1,3}$/.test(part) || Number(part) > 255)) return false;
  const [first, second] = parts.map(Number);
  return first === 10 || first === 127 || (first === 192 && second === 168) ||
    (first === 172 && second >= 16 && second <= 31) || (first === 100 && second >= 64 && second <= 127);
}

function configuration(env) {
  const provider = (env.SMS_PROVIDER || 'unisms').trim().toLowerCase();
  if (provider === 'unisms') return { provider };
  if (provider !== 'smsgate') throw new Error('Unsupported SMS provider');
  const url = new URL(env.SMSGATE_URL || '');
  const username = (env.SMSGATE_USERNAME || '').trim();
  const password = env.SMSGATE_PASSWORD || '';
  const simNumber = env.SMSGATE_SIM_NUMBER == null || env.SMSGATE_SIM_NUMBER === '' ? null : Number(env.SMSGATE_SIM_NUMBER);
  const timeout = env.SMSGATE_TIMEOUT_MS == null || env.SMSGATE_TIMEOUT_MS === '' ? 10000 : Number(env.SMSGATE_TIMEOUT_MS);
  const mode = (env.SMSGATE_MODE || (privateHost(url.hostname) ? 'local' : 'cloud')).trim().toLowerCase();
  const passphrase = env.SMSGATE_ENCRYPTION_PASSPHRASE || '';
  const deviceId = (env.SMSGATE_DEVICE_ID || '').trim();
  const iterations = env.SMSGATE_ENCRYPTION_ITERATIONS == null || env.SMSGATE_ENCRYPTION_ITERATIONS === ''
    ? 300000 : Number(env.SMSGATE_ENCRYPTION_ITERATIONS);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.hash || url.search ||
      (url.protocol === 'http:' && !privateHost(url.hostname)) ||
      !username || username.includes(':') || /[\r\n]/.test(username) || !password ||
      (simNumber !== null && (!Number.isInteger(simNumber) || simNumber < 1 || simNumber > 3)) ||
      !Number.isInteger(timeout) || timeout < 1 || timeout > 30000) throw new Error('Invalid SMSGate configuration');
  if (!['local', 'cloud'].includes(mode) || (mode === 'local' && !privateHost(url.hostname)) ||
      (mode === 'cloud' && (url.protocol !== 'https:' || !deviceId || !passphrase)) ||
      (deviceId && !/^[a-zA-Z0-9_-]{1,128}$/.test(deviceId)) ||
      (passphrase && (passphrase.trim().length < 20 || passphrase.length > 1024 || /[\r\n]/.test(passphrase))) ||
      !Number.isInteger(iterations) || iterations < 75000 || iterations > 2000000) {
    throw new Error('Invalid SMSGate encryption configuration');
  }
  return { provider, url, username, password, simNumber, timeout, mode, deviceId, passphrase, iterations };
}

function postMessage(config, payload) {
  return new Promise((resolve, reject) => {
    const data = Buffer.from(JSON.stringify(payload), 'utf8');
    const transport = config.url.protocol === 'https:' ? https : http;
    let settled = false;
    let timer;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error); else resolve(value);
    };
    const req = transport.request(config.url, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${config.username}:${config.password}`, 'utf8').toString('base64')}`,
        'Content-Type': 'application/json', Accept: 'application/json', 'Content-Length': data.length,
      },
    }, res => {
      const chunks = [];
      let bytes = 0;
      res.on('data', chunk => {
        bytes += chunk.length;
        if (bytes > 65536) {
          finish(smsError('SMSGATE_RESPONSE_ERROR', 'SMS gateway response could not be processed.'));
          res.destroy(); req.destroy();
        } else chunks.push(chunk);
      });
      res.on('error', () => finish(smsError('SMSGATE_RESPONSE_ERROR', 'SMS gateway response could not be processed.')));
      res.on('end', () => {
        if (settled) return;
        if (res.statusCode < 200 || res.statusCode >= 300) {
          finish(smsError('SMSGATE_HTTP_ERROR', 'SMS gateway did not accept the request.'));
          return;
        }
        try {
          const response = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          const states = ['Pending', 'Processed', 'Sent', 'Delivered'];
          if (!response || typeof response.id !== 'string' || !response.id || !states.includes(response.state) ||
              response.recipients?.some(recipient => ['Failed', 'Expired', 'Canceled', 'Cancelled'].includes(recipient.state))) {
            throw new Error('Invalid acknowledgement');
          }
          // The gateway can echo the OTP in its response: return only status metadata.
          finish(null, { provider: 'smsgate', messageId: response.id, state: response.state });
        } catch (_) {
          finish(smsError('SMSGATE_RESPONSE_ERROR', 'SMS gateway response could not be processed.'));
        }
      });
    });
    req.on('error', () => finish(smsError('SMSGATE_CONNECTION_ERROR', 'SMS gateway could not be reached.')));
    timer = setTimeout(() => {
      finish(smsError('SMSGATE_TIMEOUT', 'SMS gateway request timed out.'));
      req.destroy();
    }, config.timeout);
    req.end(data);
  });
}

function createPasswordResetSms({ env = process.env, uniSms = legacySms, sendMessage = postMessage } = {}) {
  function getStatus() {
    try {
      const config = configuration(env);
      return { provider: config.provider,
        configured: config.provider === 'smsgate' || uniSms.isUniSmsConfigured() };
    } catch (_) {
      return { provider: (env.SMS_PROVIDER || '').trim().toLowerCase() === 'smsgate' ? 'smsgate' : 'unknown', configured: false };
    }
  }

  async function sendPasswordResetOtpSms(args) {
    let config;
    try { config = configuration(env); }
    catch (_) { throw smsError('SMS_CONFIGURATION_ERROR', 'SMS provider configuration is incomplete or invalid.'); }
    if (config.provider === 'unisms') return uniSms.sendPasswordResetOtpSms(args);
    const number = normalizePhilippinesMobileNumber(args.to);
    if (!number) throw smsError('INVALID_PH_MOBILE_NUMBER', 'Recipient phone number is not a valid Philippine mobile number.');
    const { code, ttlMinutes, expiresAt } = args;
    if (!/^\d{4,8}$/.test(String(code)) || !Number.isInteger(ttlMinutes) || ttlMinutes < 1 || ttlMinutes > 1440) {
      throw smsError('SMS_INVALID_OTP', 'SMS reset code or expiry is invalid.');
    }
    const template = env.SMSGATE_PASSWORD_RESET_TEMPLATE ||
      'Your HRMS Plaridel password reset code is {otp}. It expires in {minutes} minutes. Do not share this code.';
    const payload = {
      textMessage: { text: template.replace(/\{otp\}/g, String(code)).replace(/\{minutes\}/g, String(ttlMinutes)) },
      phoneNumbers: [`+${number}`],
      ...(config.simNumber === null ? {} : { simNumber: config.simNumber }),
      ttl: ttlMinutes * 60, priority: 100, withDeliveryReport: true,
    };
    if (expiresAt != null) {
      const expiry = new Date(expiresAt);
      if (!Number.isFinite(expiry.getTime()) || expiry.getTime() <= Date.now()) {
        throw smsError('SMS_INVALID_OTP', 'SMS reset code or expiry is invalid.');
      }
      delete payload.ttl;
      payload.validUntil = expiry.toISOString();
    }
    if (config.mode === 'cloud') payload.deviceId = config.deviceId;
    if (config.passphrase) {
      try {
        const [text, recipient] = await Promise.all([
          encryptSmsGateField(payload.textMessage.text, config.passphrase, config.iterations),
          encryptSmsGateField(payload.phoneNumbers[0], config.passphrase, config.iterations),
        ]);
        payload.textMessage.text = text;
        payload.phoneNumbers = [recipient];
        payload.isEncrypted = true;
      } catch (_) {
        throw smsError('SMSGATE_ENCRYPTION_ERROR', 'SMS gateway encryption could not be completed.');
      }
    }
    if (payload.validUntil && Date.parse(payload.validUntil) <= Date.now()) {
      throw smsError('SMS_INVALID_OTP', 'SMS reset code or expiry is invalid.');
    }
    // Do not retry or silently fall back: a timeout may occur after acceptance.
    return sendMessage(config, payload);
  }

  return { getStatus, sendPasswordResetOtpSms };
}

const service = createPasswordResetSms();
module.exports = { createPasswordResetSms, normalizePhilippinesMobileNumber,
  sendPasswordResetOtpSms: service.sendPasswordResetOtpSms,
  getPasswordResetSmsStatus: service.getStatus };
