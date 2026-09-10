'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const sourceFiles = [
  'src/services/attendancePolicyResolver.js',
  'src/services/biometricProcessing.js',
  'src/services/leaveAttendanceDeduction.js',
  'src/routes/dtrDailySummary.js',
];

test('all attendance calculation paths select only the explicit active default', () => {
  for (const relativePath of sourceFiles) {
    const source = fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
    const defaultQuery = source.match(
      /FROM attendance_policies(?:\s+p)?\s+WHERE[\s\S]{0,180}?LIMIT 1`/
    );

    assert.ok(defaultQuery, `${relativePath} must contain a bounded default-policy query`);
    assert.match(
      defaultQuery[0],
      /(?:p\.)?is_default\s*=\s*true/,
      `${relativePath} must require an explicitly marked default`
    );
    assert.match(
      defaultQuery[0],
      /(?:p\.)?is_active\s*=\s*true/,
      `${relativePath} must require an active default`
    );
    assert.doesNotMatch(
      defaultQuery[0],
      /ORDER BY[\s\S]*updated_at/,
      `${relativePath} must not fall back to the most recently edited policy`
    );
  }
});

test('DTR and biometric policy queries load the global conversion switch', () => {
  for (const relativePath of [
    'src/routes/dtrDailySummary.js',
    'src/services/biometricProcessing.js',
  ]) {
    const source = fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
    const policyLoaders = [
      source.match(
        /async function getActiveDefaultAttendancePolicy\(\)[\s\S]*?\r?\n}\r?\n/
      )?.[0],
      source.match(
        /async function getAttendancePolicyForEmployeeDate\([\s\S]*?\r?\n}\r?\n/
      )?.[0],
    ];
    for (const loader of policyLoaders) {
      assert.ok(loader, `${relativePath} must contain both policy loaders`);
      assert.match(
        loader,
        /use_equivalent_day_conversion/,
        `${relativePath} must load the global conversion switch`
      );
    }
  }
});
