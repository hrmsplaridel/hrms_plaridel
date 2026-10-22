const test = require('node:test');
const assert = require('node:assert/strict');
const {
  officialScopeSql,
  officialEndorsementDateSql,
  parseReportPeriod,
  MANILA_TZ,
} = require('../src/services/mayorEndorsementStats');

test('official scope excludes is_test by default', () => {
  assert.match(officialScopeSql('mer', false), /is_test/);
  assert.match(officialScopeSql('mer', false), /false/);
  assert.equal(officialScopeSql('mer', true), 'TRUE');
});

test('official endorsement date prefers endorsed_at then legacy timestamps', () => {
  const sql = officialEndorsementDateSql('mer');
  assert.match(sql, /endorsed_at/);
  assert.match(sql, /office_form_approved_at/);
  assert.match(sql, /approved_at/);
  assert.match(sql, /Asia\/Manila|AT TIME ZONE/);
});

test('parseReportPeriod rejects invalid period', () => {
  const r = parseReportPeriod({ period: 'yearly' });
  assert.ok(r.error);
});

test('parseReportPeriod custom requires YYYY-MM-DD bounds', () => {
  const bad = parseReportPeriod({ period: 'custom', from_date: '10/20/2026' });
  assert.ok(bad.error);
  const ok = parseReportPeriod({
    period: 'custom',
    from_date: '2026-10-01',
    to_date: '2026-10-20',
  });
  assert.equal(ok.period, 'custom');
  assert.equal(ok.fromDate, '2026-10-01');
  assert.equal(ok.toDateInclusive, '2026-10-20');
  assert.equal(ok.toDateExclusive, '2026-10-21');
  assert.equal(ok.includeTest, false);
});

test('parseReportPeriod daily/weekly/monthly presets', () => {
  for (const period of ['daily', 'weekly', 'monthly']) {
    const r = parseReportPeriod({ period });
    assert.equal(r.period, period);
    assert.equal(r.includeTest, false);
  }
  const withTest = parseReportPeriod({ period: 'weekly', include_test: '1' });
  assert.equal(withTest.includeTest, true);
});

test('Manila timezone constant', () => {
  assert.equal(MANILA_TZ, 'Asia/Manila');
});

test('meeting approval must not be treated as endorsement in counting rules', () => {
  // Documented contract: endorsement counts use status = endorsed + official date.
  // Meeting approval only affects meeting_request_status / appointment_status.
  const endorseSql = officialEndorsementDateSql('mer');
  assert.doesNotMatch(endorseSql, /meeting_decided_at/);
  assert.doesNotMatch(endorseSql, /meeting_request_status/);
});
