const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getLinkedSourceDocument,
} = require('../src/services/docutrackerSourceDocumentService');

const recordId = '11111111-1111-4111-8111-111111111111';

test('employee can load only an owned L&D report with view permission', async () => {
  let queryParams;
  const pool = {
    async query(_sql, params) {
      queryParams = params;
      return {
        rows: [{
          id: recordId,
          employee_id: '22222222-2222-4222-8222-222222222222',
          employee_name: 'Maria Santos',
          title: 'Day 1 report',
          description: 'Training activities',
          submitted_at: new Date('2026-09-14T01:00:00Z'),
          updated_at: new Date('2026-09-14T02:00:00Z'),
          status: 'submitted',
        }],
      };
    },
  };
  const result = await getLinkedSourceDocument(
    pool,
    { id: '22222222-2222-4222-8222-222222222222', role: 'employee' },
    'ld',
    'training_daily_reports',
    recordId,
    { canViewType: async () => true }
  );

  assert.deepEqual(queryParams, [
    recordId,
    '22222222-2222-4222-8222-222222222222',
  ]);
  assert.equal(result.source_module, 'ld');
  assert.equal(result.title, 'Day 1 report');
  assert.equal(result.fields[0].value, 'Maria Santos');
});

test('L&D source detail describes review progress with readable dates', async () => {
  const pool = {
    async query() {
      return {
        rows: [{
          id: recordId,
          employee_id: '22222222-2222-4222-8222-222222222222',
          employee_name: 'Maria Santos',
          title: 'Day 1 report',
          submitted_at: new Date('2026-09-14T01:00:00Z'),
          seen_at: new Date('2026-09-15T02:30:00Z'),
          seen_by_name: 'L&D Admin',
          reviewed_by_name: 'L&D Reviewer',
          status: 'reviewed',
        }],
      };
    },
  };
  const result = await getLinkedSourceDocument(
    pool,
    { id: '33333333-3333-4333-8333-333333333333', role: 'admin' },
    'ld',
    'training_daily_reports',
    recordId
  );
  const byLabel = Object.fromEntries(
    result.fields.map((item) => [item.label, item.value])
  );

  assert.equal(result.status, 'reviewed');
  assert.equal(byLabel['Seen by'], 'L&D Admin');
  assert.equal(byLabel['Reviewed by'], 'L&D Reviewer');
  assert.match(byLabel.Submitted, /^Sep 14, 2026/);
  assert.match(byLabel['Seen on'], /^Sep 15, 2026/);
  assert.equal(Object.hasOwn(byLabel, 'Status'), false);
});

test('L&D source detail rejects a user without module view access', async () => {
  const pool = {
    async query() {
      throw new Error('database must not be queried');
    },
  };
  await assert.rejects(
    getLinkedSourceDocument(
      pool,
      { id: '22222222-2222-4222-8222-222222222222', role: 'employee' },
      'ld',
      'training_daily_reports',
      recordId,
      { canViewType: async () => false }
    ),
    (error) => error.code === 'FORBIDDEN'
  );
});

test('recruitment applications are not exposed through DocuTracker, even to admins', async () => {
  const pool = {
    async query() {
      throw new Error('database must not be queried');
    },
  };
  for (const role of ['admin', 'hr', 'employee']) {
    await assert.rejects(
      getLinkedSourceDocument(
        pool,
        { id: '22222222-2222-4222-8222-222222222222', role },
        'rsp',
        'recruitment_applications',
        recordId
      ),
      (error) => error.code === 'NOT_FOUND',
      role
    );
  }
});

test('unsupported source types are not exposed', async () => {
  await assert.rejects(
    getLinkedSourceDocument(
      { query: async () => ({ rows: [] }) },
      { id: '22222222-2222-4222-8222-222222222222', role: 'admin' },
      'rsp',
      'secret_table',
      recordId
    ),
    (error) => error.code === 'NOT_FOUND'
  );
});
