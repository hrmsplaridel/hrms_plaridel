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

test('RSP application detail remains admin-only', async () => {
  const pool = {
    async query() {
      throw new Error('database must not be queried');
    },
  };
  await assert.rejects(
    getLinkedSourceDocument(
      pool,
      { id: '22222222-2222-4222-8222-222222222222', role: 'employee' },
      'rsp',
      'recruitment_applications',
      recordId
    ),
    (error) => error.code === 'FORBIDDEN'
  );
});

test('admin receives allowlisted RSP fields without source file paths', async () => {
  const pool = {
    async query() {
      return {
        rows: [{
          id: recordId,
          applicant_number: 'PLR-TEST1234',
          full_name: 'Juan Dela Cruz',
          position_applied_for: 'Administrative Aide',
          email: 'juan@example.test',
          status: 'submitted',
          final_requirements_approved: false,
          hr_account_setup_done: false,
          created_at: new Date('2026-09-14T01:00:00Z'),
          updated_at: new Date('2026-09-14T02:00:00Z'),
        }],
      };
    },
  };
  const result = await getLinkedSourceDocument(
    pool,
    { id: '22222222-2222-4222-8222-222222222222', role: 'admin' },
    'rsp',
    'recruitment_applications',
    recordId
  );

  assert.equal(result.source_module, 'rsp');
  assert.equal(result.title, 'Administrative Aide');
  assert.equal(result.attachments.length, 0);
  assert.equal(Object.hasOwn(result, 'attachment_path'), false);
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

test('RSP print payload keeps attachment names but hides storage paths', async () => {
  const previousSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = 'docutracker-source-test-secret';
  try {
    const pool = {
      async query() {
        return {
          rows: [{
            id: recordId,
            full_name: 'Juan Dela Cruz',
            email: 'juan@example.test',
            status: 'submitted',
            doc_resume_path: `${recordId}/private-resume.pdf`,
            doc_resume_name: 'Resume.pdf',
            final_requirements_approved: false,
            hr_account_setup_done: false,
          }],
        };
      },
    };
    const result = await getLinkedSourceDocument(
      pool,
      { id: '22222222-2222-4222-8222-222222222222', role: 'admin' },
      'rsp',
      'recruitment_applications',
      recordId
    );

    assert.equal(result.print_data.doc_resume_path, 'linked');
    assert.equal(result.print_data.doc_resume_name, 'Resume.pdf');
    assert.equal(result.attachments[0].name, 'Resume.pdf');
    assert.equal(JSON.stringify(result).includes('private-resume.pdf'), false);
  } finally {
    if (previousSecret == null) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = previousSecret;
  }
});
