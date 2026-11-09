'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createManualImportConflictChecker } = require('../src/services/manualImportConflicts');

function fixture({ holidays = [], leaves = [], locators = [] } = {}) {
  const queries = [];
  const client = { async query(sql, params) {
    queries.push({ sql, params });
    if (sql.includes('FROM holidays')) return { rows: holidays };
    if (sql.includes('FROM leave_requests')) {
      assert.match(sql, /status = 'approved'/);
      assert.match(sql, /affects_dtr_normally/);
      assert.match(sql, /dtr_leave_coverage/);
      return { rows: leaves };
    }
    if (sql.includes('FROM locator_slips')) {
      assert.match(sql, /status = 'approved'/);
      return { rows: locators };
    }
    throw new Error(`Unexpected query ${sql}`);
  } };
  const checker = createManualImportConflictChecker(client);
  const check = (time = '08:00:00', date = '2026-09-08') => checker({
    employeeId: '11111111-1111-4111-8111-111111111111', date,
    loggedAt: `2026-09-08T${time}+08:00`,
  });
  return { check, queries };
}

test('ordinary attendance is allowed and day coverage queries are cached per batch', async () => {
  const { check, queries } = fixture();
  assert.deepEqual(await check(), { exclusion: null, warnings: [] });
  await check('12:00:00'); await check('13:00:00'); await check('17:00:00');
  assert.equal(queries.length, 3);
});

test('full-day leave excludes manually supplied punches', async () => {
  const { check } = fixture({ leaves: [{ sd: '2026-09-08', ed: '2026-09-08', number_of_days: '1' }] });
  assert.equal((await check()).exclusion.code, 'approved_leave');
});

test('multi-day leave excludes the covered attendance date', async () => {
  const { check } = fixture({ leaves: [{ sd: '2026-09-01', ed: '2026-09-10', number_of_days: '8' }] });
  assert.equal((await check()).exclusion.code, 'approved_leave');
});

test('legacy half-day leave warns instead of guessing which session was approved', async () => {
  const { check } = fixture({ leaves: [{ sd: '2026-09-08', ed: '2026-09-08', number_of_days: '0.5' }] });
  const result = await check();
  assert.equal(result.exclusion, null);
  assert.equal(result.warnings[0].code, 'partial_leave_review');
});

function holiday(coverage, extra = {}) {
  return { id: 'holiday', name: 'Test holiday', coverage,
    date_from: '2026-09-08', date_to: '2026-09-08', recurring: false, ...extra };
}

test('whole-day holiday excludes every punch', async () => {
  const { check } = fixture({ holidays: [holiday('whole_day')] });
  assert.equal((await check()).exclusion.code, 'holiday');
  assert.equal((await check('17:00:00')).exclusion.code, 'holiday');
});

test('AM holiday excludes the morning session including noon out, not the afternoon', async () => {
  const { check } = fixture({ holidays: [holiday('am_only')] });
  assert.equal((await check()).exclusion.code, 'holiday');
  assert.equal((await check('12:00:00')).exclusion.code, 'holiday');
  assert.equal((await check('12:55:00')).exclusion, null);
  assert.equal((await check('17:00:00')).exclusion, null);
});

test('PM holiday preserves morning and noon out but excludes afternoon punches', async () => {
  const { check } = fixture({ holidays: [holiday('pm_only')] });
  assert.equal((await check()).exclusion, null);
  assert.equal((await check('12:00:00')).exclusion, null);
  assert.equal((await check('12:55:00')).exclusion.code, 'holiday');
  assert.equal((await check('17:00:00')).exclusion.code, 'holiday');
});

test('complementary half-day holidays exclude the whole day', async () => {
  const { check } = fixture({ holidays: [holiday('am_only'), holiday('pm_only')] });
  assert.equal((await check()).exclusion.code, 'holiday');
  assert.equal((await check('17:00:00')).exclusion.code, 'holiday');
});

test('recurring holidays use the imported year', async () => {
  const { check } = fixture({ holidays: [holiday('whole_day', {
    date_from: '2025-09-08', date_to: '2025-09-08', recurring: true,
  })] });
  assert.equal((await check()).exclusion.code, 'holiday');
});

test('approved locator coverage warns without rejecting actual punches', async () => {
  const { check } = fixture({ locators: [{ am_in: true, am_out: true }] });
  const result = await check();
  assert.equal(result.exclusion, null);
  assert.equal(result.warnings[0].code, 'locator_review');
  assert.match(result.warnings[0].message, /AM in/);
  assert.match(result.warnings[0].message, /AM out/);
});

test('overnight leave conflicts are checked against the resolved attendance date', async () => {
  const { check, queries } = fixture({ leaves: [{ sd: '2026-09-07', ed: '2026-09-07', number_of_days: '1' }] });
  assert.equal((await check('06:00:00', '2026-09-07')).exclusion.code, 'approved_leave');
  assert.equal(queries.find(q => q.sql.includes('FROM leave_requests')).params[1], '2026-09-07');
});

test('coverage lookup failure fails closed', async () => {
  const check = createManualImportConflictChecker({ async query() { throw new Error('database unavailable'); } });
  await assert.rejects(check({ employeeId: 'employee', date: '2026-09-08', loggedAt: '2026-09-08T08:00:00+08:00' }),
    /database unavailable/);
});
