'use strict';

const { randomBytes, pbkdf2, createCipheriv } = require('node:crypto');
const { promisify } = require('node:util');
const deriveKey = promisify(pbkdf2);

// SMSGate's documented passphrase wire format (supported by the installed phone).
// Salt also serves as the CBC IV in this protocol; generate a new one per field.
async function encryptSmsGateField(text, passphrase, iterations) {
  const salt = randomBytes(16);
  const key = await deriveKey(passphrase, salt, iterations, 32, 'sha1');
  try {
    const cipher = createCipheriv('aes-256-cbc', key, salt);
    const ciphertext = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
    return `$aes-256-cbc/pbkdf2-sha1$i=${iterations}$${salt.toString('base64')}$${ciphertext.toString('base64')}`;
  } finally {
    key.fill(0);
  }
}

module.exports = { encryptSmsGateField };
