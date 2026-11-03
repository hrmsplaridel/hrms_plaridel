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
    'pending_mayor',
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

test('department approval pages order by filing time with a stable ID tie-breaker', async () => {
  const create = require('../src/modules/locator/controllers/departmentQueue.controller');
  for (const page of [1, 2]) {
    let released = false;
    const client = {
      async query(sql, params) {
        if (sql.includes('COUNT(*)')) return { rows: [{ total: 4 }] };
        assert.match(sql, /ORDER BY ls\.created_at DESC, ls\.id DESC\s+LIMIT/);
        assert.doesNotMatch(sql, /ORDER BY ls\.updated_at/);
        assert.deepEqual(params.slice(-2), [2, (page - 1) * 2]);
        return { rows: [{ id: `page-${page}` }] };
      },
      release() { released = true; },
    };
    const controller = create({
      pool: { connect: async () => client },
      isDepartmentHead: async () => ({ departmentId: 'department' }),
      parseLocatorHistoryFilters, mapLocatorRow: row => row,
    });
    const response = { status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
    await controller.listDepartmentRequests({ user: { id: 'reviewer' }, query: { page: String(page), page_size: '2' } }, response);
    assert.equal(response.code, undefined);
    assert.equal(response.body.pagination.page, page);
    assert.equal(response.body.pagination.total, 4);
    assert.equal(released, true);
  }
});
