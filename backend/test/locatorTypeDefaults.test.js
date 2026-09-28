const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

function readBackendFile(relativePath) {
  return fs.readFileSync(path.resolve(__dirname, '..', relativePath), 'utf8');
}

function requiredMatch(source, pattern, description) {
  const match = source.match(pattern);
  assert.ok(match, description);
  return match[0];
}

test('fresh and runtime defaults do not seed Work From Home', () => {
  const schema = readBackendFile('scripts/init-schema.sql');
  const route = readBackendFile('src/routes/locatorSlips.js');

  const schemaSeed = requiredMatch(
    schema,
    /INSERT INTO locator_request_types[\s\S]*?ON CONFLICT \(code\) DO UPDATE SET/,
    'locator type seed must exist in init-schema.sql'
  );
  const runtimeDefaults = requiredMatch(
    route,
    /const DEFAULT_LOCATOR_TYPES = \[[\s\S]*?\n\];/,
    'runtime locator defaults must exist'
  );

  for (const defaults of [schemaSeed, runtimeDefaults]) {
    assert.match(defaults, /['"]locator['"]/);
    assert.match(defaults, /['"]pass_slip['"]/);
    assert.doesNotMatch(defaults, /work_from_home/);
  }
});

test('upgrade migration preserves WFH while removing system ownership', () => {
  const migration = readBackendFile(
    'scripts/migrations/dtr/20260927_locator_work_from_home_custom.sql'
  );

  assert.match(migration, /WHERE code = 'work_from_home'/i);
  assert.match(migration, /SET is_system = false/i);
  assert.doesNotMatch(migration, /DELETE\s+FROM/i);
  assert.doesNotMatch(migration, /is_active\s*=/i);
});

test('fresh schema and upgrade migration reject negative sort orders', () => {
  const schema = readBackendFile('scripts/init-schema.sql');
  const migration = readBackendFile(
    'scripts/migrations/dtr/20260927_locator_type_rule_constraints.sql'
  );
  const locatorTypeTable = requiredMatch(
    schema,
    /CREATE TABLE IF NOT EXISTS locator_request_types \([\s\S]*?\n\);/,
    'locator_request_types table must exist in init-schema.sql'
  );

  assert.match(
    locatorTypeTable,
    /chk_locator_request_types_sort_order_nonnegative[\s\S]*CHECK \(sort_order >= 0\)/i
  );
  assert.match(migration, /WHERE sort_order < 0/i);
  assert.match(
    migration,
    /ADD CONSTRAINT chk_locator_request_types_sort_order_nonnegative[\s\S]*CHECK \(sort_order >= 0\)/i
  );
});

test('DTR coverage behavior does not override the configured mode by type code', () => {
  const route = readBackendFile('src/routes/dtrDailySummary.js');

  assert.doesNotMatch(
    route,
    /normalizeLocatorRequestType\([^)]*request_type[^)]*\)\s*===\s*['"]work_from_home['"]/
  );
});
