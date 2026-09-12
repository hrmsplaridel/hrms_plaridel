'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule } = require('./helpers/moduleMocks');
const { todayInHrmsTimezone } = require('../src/utils/dateRangeParser');
const {
  LEGACY_LOOKUP_LIMIT,
  MAX_PAGE_SIZE,
  parsePositionListFilters,
} = require('../src/services/positionListFilters');

const DEPARTMENT_ID = '33333333-3333-4333-8333-333333333333';

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

async function invokeListRoute(pool, query = {}) {
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = require.resolve('../src/routes/positions');
  delete require.cache[routePath];
  try {
    const router = require('../src/routes/positions');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/' && entry.route.methods.get
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const res = responseRecorder();
    await handler({ query, user: { role: 'admin' } }, res);
    return res;
  } finally {
    delete require.cache[routePath];
    restoreDb();
  }
}

function positionRow(overrides = {}) {
  return {
    id: '22222222-2222-4222-8222-222222222222',
    position_number: 12,
    name: 'HR Officer',
    description: 'Records support',
    department_id: DEPARTMENT_ID,
    department_name: 'Human Resources',
    is_department_head: false,
    is_active: true,
    department_head_periods: [],
    dependency_primary_assignments: 0,
    dependency_additional_positions: 0,
    deactivation_primary_assignments: 0,
    deactivation_additional_positions: 0,
    deactivation_department_head_periods: 0,
    ...overrides,
  };
}

test('position list filters keep legacy callers bounded', () => {
  const result = parsePositionListFilters({ status: 'All' });

  assert.equal(result.ok, true);
  assert.equal(result.paginated, false);
  assert.equal(result.responseLimit, LEGACY_LOOKUP_LIMIT);
});

test('position list filters parse bounded management pagination', () => {
  const result = parsePositionListFilters({
    paginated: 'true',
    status: 'inactive',
    department_id: DEPARTMENT_ID,
    page: '3',
    limit: '25',
    search: '  payroll  ',
  });

  assert.deepEqual(result, {
    ok: true,
    status: 'Inactive',
    departmentId: DEPARTMENT_ID,
    paginated: true,
    page: 3,
    limit: 25,
    search: 'payroll',
    responseLimit: 25,
  });
});

test('position list filters reject unsafe query values', () => {
  const invalidQueries = [
    { status: 'Deleted' },
    { department_id: 'not-a-uuid' },
    { paginated: 'true', page: '0' },
    { paginated: 'true', limit: String(MAX_PAGE_SIZE + 1) },
    { search: 'x'.repeat(201) },
  ];

  for (const query of invalidQueries) {
    assert.equal(parsePositionListFilters(query).ok, false);
  }
});

test('paginated position route returns total and stable requested page', async () => {
  const calls = [];
  const pool = {
    async query(sql, params) {
      const text = String(sql);
      calls.push({ text, params });
      if (text.includes('COUNT(*)::int AS total')) {
        return { rows: [{ total: 23 }] };
      }
      return { rows: [positionRow()] };
    },
  };

  const res = await invokeListRoute(pool, {
    paginated: 'true',
    status: 'All',
    search: 'Officer',
    page: '2',
    limit: '10',
  });

  assert.equal(res.statusCode, 200);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0].params, ['%Officer%']);
  assert.deepEqual(calls[1].params, [
    '%Officer%',
    todayInHrmsTimezone(),
    10,
    10,
  ]);
  assert.match(calls[1].text, /ILIKE \$1/);
  assert.match(
    calls[1].text,
    /ORDER BY LOWER\(BTRIM\(p\.name\)\), p\.position_number NULLS LAST, p\.id/
  );
  assert.deepEqual(res.body.pagination, {
    page: 2,
    limit: 10,
    page_size: 10,
    total: 23,
    page_count: 3,
  });
  assert.equal(res.body.items.length, 1);
  assert.equal(res.body.items[0].name, 'HR Officer');
});

test('legacy position route remains an array and applies its hard limit', async () => {
  const calls = [];
  const pool = {
    async query(sql, params) {
      calls.push({ text: String(sql), params });
      return { rows: [positionRow()] };
    },
  };

  const res = await invokeListRoute(pool, { status: 'Active' });

  assert.equal(res.statusCode, 200);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].params, [
    todayInHrmsTimezone(),
    LEGACY_LOOKUP_LIMIT,
    0,
  ]);
  assert.equal(Array.isArray(res.body), true);
  assert.equal(res.body.length, 1);
});

test('position route rejects an excessive page size before querying', async () => {
  const pool = {
    async query() {
      assert.fail('database must not be queried for invalid pagination');
    },
  };

  const res = await invokeListRoute(pool, {
    paginated: 'true',
    limit: String(MAX_PAGE_SIZE + 1),
  });

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /limit must be between/);
});
