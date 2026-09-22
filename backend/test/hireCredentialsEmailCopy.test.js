const test = require('node:test');
const assert = require('node:assert/strict');
const {
  HIRE_LOGIN_INSTRUCTIONS,
  buildHireCredentialsAccountNote,
  buildHireCredentialsPlainText,
} = require('../src/utils/emailJsMail');

test('hire EmailJS account note tells applicants to wait for HR', () => {
  const note = buildHireCredentialsAccountNote(true);
  assert.match(note, /Please wait for the HR Head or Admin before you sign in/);
  assert.match(note, /Do not try to log in on your own/);
  assert.doesNotMatch(note, /Please sign in to the HRMS/);
  assert.equal(HIRE_LOGIN_INSTRUCTIONS.includes('HR Head or Admin'), true);
});

test('SMTP hire email matches the EmailJS body format', () => {
  const text = buildHireCredentialsPlainText({
    applicantName: 'Jane Doe',
    username: 'jane@example.com',
    password: '8FDFxfs%t5Sk',
    accountNote: buildHireCredentialsAccountNote(true),
  });
  assert.match(text, /^Hello Jane Doe,/);
  assert.match(text, /Username: jane@example.com/);
  assert.match(text, /Password: 8FDFxfs%t5Sk/);
  assert.match(text, /Human Resource Management Office/);
});
