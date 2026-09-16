'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const runtimeFiles = [
  'src/routes/shifts.js',
  'src/routes/dtrDailySummary.js',
  'src/services/biometricProcessing.js',
  'src/services/shiftAttendance.js',
];

test('shift runtime code never alters the database schema', () => {
  for (const relativePath of runtimeFiles) {
    const source = fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
    assert.doesNotMatch(
      source,
      /ALTER\s+TABLE\s+shifts/i,
      `${relativePath} must rely on migrations instead of runtime DDL`,
    );
    assert.doesNotMatch(
      source,
      /ensureShiftPunchModeColumn/,
      `${relativePath} must not restore request-time schema mutation`,
    );
  }
});
