const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  isMayorIntakeStubEmail,
  buildApplicantFullName,
  buildReferenceNumber,
  manilaDateSql,
} = require('../src/utils/mayorEndorsementIsolation');

test('stub email detection matches Mayor intake pattern', () => {
  assert.equal(isMayorIntakeStubEmail('mayor-intake-123@local.intake'), true);
  assert.equal(isMayorIntakeStubEmail('person@example.com'), false);
});

test('applicant full name is built from intake fields', () => {
  assert.equal(
    buildApplicantFullName({
      first_name: 'Ana',
      middle_name_or_initial: 'B',
      last_name: 'Cruz',
    }),
    'Ana B Cruz',
  );
});

test('reference numbers use Asia/Manila calendar date', () => {
  const id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  // 2026-10-19 18:00 UTC = 2026-10-20 02:00 Asia/Manila
  const ref = buildReferenceNumber(id, new Date('2026-10-19T18:00:00.000Z'));
  assert.equal(ref, 'MER-20261020-AAAAAAAA');
});

test('manila date SQL wraps expression with Asia/Manila', () => {
  assert.match(manilaDateSql('mer.endorsed_at'), /Asia\/Manila/);
});

test('Mayor route no longer updates recruitment application statuses', () => {
  const src = fs.readFileSync(
    path.join(__dirname, '../src/routes/mayorEndorsements.js'),
    'utf8',
  );
  assert.equal(src.includes("SET status = 'passed'"), false);
  assert.equal(src.includes("SET status = 'endorsed'"), true); // mayor table only
  assert.equal(/UPDATE\s+recruitment_applications[\s\S]{0,80}SET status/i.test(src), false);
  assert.match(src, /LEFT JOIN recruitment_applications/);
  assert.match(src, /independentIntakeEnabled/);
  assert.match(src, /mayor_endorsement_request/);
});

test('RSP application delete no longer deletes Mayor endorsements', () => {
  const src = fs.readFileSync(
    path.join(__dirname, '../src/routes/rspApplications.js'),
    'utf8',
  );
  assert.equal(
    src.includes('DELETE FROM public.mayor_endorsement_requests WHERE application_id'),
    false,
  );
});

test('isolation migrations are present and ordered', () => {
  const dir = path.join(__dirname, '../scripts/migrations');
  for (const name of [
    '20261020_mayor_isolation_m1_prep.sql',
    '20261020_mayor_isolation_m2_backfill.sql',
    '20261020_mayor_isolation_m3_decouple_fk.sql',
    '20261020_mayor_isolation_m4_staff_role.sql',
  ]) {
    const sql = fs.readFileSync(path.join(dir, name), 'utf8');
    assert.match(sql, /DO NOT RUN/i);
    assert.doesNotMatch(sql, /\bDROP TABLE\b/i);
  }
  const m3 = fs.readFileSync(
    path.join(dir, '20261020_mayor_isolation_m3_decouple_fk.sql'),
    'utf8',
  );
  assert.match(m3, /DROP CONSTRAINT IF EXISTS mayor_endorsement_requests_application_id_fkey/);
  assert.match(m3, /ALTER COLUMN application_id DROP NOT NULL/);
});
