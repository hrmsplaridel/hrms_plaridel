const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseLocatorAdminFilters,
  parseLocatorHistoryFilters,
  parseStatusFilter,
} = require('../src/services/locatorAdminFilters');

test('locator admin filters normalize queue status groups', () => {
  assert.deepEqual(parseStatusFilter('pending_hr'), ['pending_hr', 'pending']);
  assert.deepEqual(parseStatusFilter('rejected'), [
    'rejected_by_department_head',
    'rejected_by_hr',
  ]);
  assert.deepEqual(parseStatusFilter('approved'), ['approved']);
  assert.equal(parseStatusFilter('not-a-status'), undefined);
});

test('locator admin filters parse pagination, dates, and record IDs', () => {
  const result = parseLocatorAdminFilters({
    page: '3',
    page_size: '25',
    status: 'approved',
    department_id: '00000000-0000-4000-8000-000000000001',
    employee_id: '00000000-0000-4000-8000-000000000002',
    from: '2025-01-01',
    to: '2025-12-31',
  });

  assert.equal(result.ok, true);
  assert.equal(result.filters.page, 3);
  assert.equal(result.filters.pageSize, 25);
  assert.equal(result.filters.from, '2025-01-01');
  assert.equal(result.filters.employeeId.endsWith('2'), true);
});

test('locator admin filters reject invalid ranges and oversized pages', () => {
  assert.equal(
    parseLocatorAdminFilters({ from: '2026-02-30' }).ok,
    false
  );
  assert.equal(
    parseLocatorAdminFilters({ from: '2026-08-02', to: '2026-08-01' }).ok,
    false
  );
  assert.equal(parseLocatorAdminFilters({ page_size: '500' }).ok, false);
});

test('locator history filters group UI statuses and parse paging', () => {
  const pending = parseLocatorHistoryFilters({
    status: 'pending',
    page: '2',
    page_size: '50',
    search: 'field office',
    from: '2026-01-01',
    to: '2026-12-31',
  });
  assert.equal(pending.ok, true);
  assert.deepEqual(pending.filters.statuses, [
    'pending',
    'pending_department_head',
    'pending_hr',
  ]);
  assert.equal(pending.filters.page, 2);
  assert.equal(pending.filters.pageSize, 50);
  assert.deepEqual(
    parseLocatorHistoryFilters({ status: 'returned' }).filters.statuses,
    ['returned_for_correction']
  );
  assert.deepEqual(
    parseLocatorHistoryFilters({ status: 'forwarded' }).filters.statuses,
    ['pending', 'pending_hr']
  );
  assert.deepEqual(
    parseLocatorHistoryFilters(
      { status: 'pending' },
      { departmentHead: true }
    ).filters.statuses,
    ['pending_department_head']
  );
});

test('locator history filters reject invalid query values', () => {
  assert.equal(parseLocatorHistoryFilters({ page_size: '101' }).ok, false);
  assert.equal(parseLocatorHistoryFilters({ status: 'unknown' }).ok, false);
  assert.equal(
    parseLocatorHistoryFilters({ from: '2026-09-02', to: '2026-09-01' }).ok,
    false
  );
});
