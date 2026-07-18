const test = require('node:test');
const assert = require('node:assert/strict');

const { isMobileClient } = require('../src/utils/sessionDevice');

test('native Flutter mobile hints are classified as mobile', () => {
  assert.equal(isMobileClient('Dart/3.8', 'Android device - HRMS 1.0.0'), true);
  assert.equal(isMobileClient('Dart/3.8', 'iPhone or iPad - HRMS 1.0.0'), true);
});

test('desktop clients remain allowed', () => {
  assert.equal(isMobileClient('Dart/3.8 (dart:io)', 'Windows PC - HRMS 1.0.0'), false);
  assert.equal(
    isMobileClient(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0',
      'Web browser - HRMS 1.0.0',
    ),
    false,
  );
});

test('mobile browser user agents are classified as mobile', () => {
  assert.equal(
    isMobileClient(
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Mobile Safari/537.36',
      'Web browser - HRMS 1.0.0',
    ),
    true,
  );
});
