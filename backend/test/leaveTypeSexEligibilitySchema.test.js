const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const readBackendFile = (relativePath) => fs.readFileSync(
  path.resolve(__dirname, '..', relativePath),
  'utf8'
);

test('fresh schema defines constrained leave type sex eligibility', () => {
  const schema = readBackendFile('scripts/init-schema.sql');

  assert.match(
    schema,
    /sex_eligibility\s+TEXT\s+NOT NULL\s+DEFAULT\s+'any'/i
  );
  assert.match(schema, /CONSTRAINT\s+chk_leave_type_sex_eligibility/i);
  assert.match(
    schema,
    /sex_eligibility\s+IN\s*\(\s*'any'\s*,\s*'female'\s*,\s*'male'\s*\)/i
  );
  assert.match(
    schema,
    /WHEN\s+name\s+IN\s*\(\s*'maternityLeave'\s*,\s*'tenDayVawcLeave'\s*,\s*'specialLeaveBenefitsForWomen'\s*\)\s+THEN\s+'female'/i
  );
  assert.match(schema, /WHEN\s+name\s*=\s*'paternityLeave'\s+THEN\s+'male'/i);
});

test('upgrade migration normalizes and constrains leave type sex eligibility', () => {
  const migration = readBackendFile(
    'scripts/migrations/dtr/20260927_leave_type_sex_eligibility.sql'
  );

  assert.match(migration, /ADD COLUMN IF NOT EXISTS sex_eligibility TEXT/i);
  assert.match(migration, /ALTER COLUMN sex_eligibility SET DEFAULT 'any'/i);
  assert.match(migration, /ALTER COLUMN sex_eligibility SET NOT NULL/i);
  assert.match(migration, /ADD CONSTRAINT chk_leave_type_sex_eligibility/i);
});
