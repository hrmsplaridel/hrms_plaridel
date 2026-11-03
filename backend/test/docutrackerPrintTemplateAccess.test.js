const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const documentId = '10000000-0000-4000-8000-000000000001';
const applicantId = '10000000-0000-4000-8000-000000000002';
const reviewerId = '10000000-0000-4000-8000-000000000003';

async function readPrintSettings({ document = {}, user = {}, permitted }) {
  const calls = [];
  const row = {
    id: documentId,
    document_id: documentId,
    document_type: 'memo',
    status: 'in_review',
    created_by: applicantId,
    current_holder_id: reviewerId,
    current_step: 2,
    workflow_version: 4,
    originating_department_id: 'department-a',
    source_module: null,
    release_required: false,
    ...document,
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { async query(sql) {
      // A real SELECT returns only its projected document columns. Preserve
      // that behavior so an abbreviated authorization row cannot pass here.
      const result = {};
      for (const [key, value] of Object.entries(row)) {
        if (key === 'document_id' || /\bd\.\*/.test(sql) ||
            new RegExp(`\\bd\\.${key}\\b`).test(sql)) result[key] = value;
      }
      return { rows: [result] };
    } },
  });
  const restoreWorkflow = withMockedModule('../src/services/docutrackerWorkflowService', {
    async canUserPerformDocumentAction(_, request) {
      calls.push(request.action);
      return permitted(request.document, request.action);
    },
  });
  const routePath = '../src/routes/docutrackerPrintTemplates';
  clearModule(routePath);
  try {
    const router = require(routePath);
    const handler = router.stack.find(entry => entry.route?.path === '/documents/:id' &&
      entry.route.methods.get).route.stack.at(-1).handle;
    const res = { code: 200, status(code) { this.code = code; return this; },
      json(body) { this.body = body; return this; } };
    await handler({ params: { id: documentId }, user: { id: reviewerId, role: 'employee', ...user } }, res);
    return { ...res, calls };
  } finally {
    clearModule(routePath);
    restoreWorkflow();
    restoreDb();
  }
}

test('print authorization receives the holder and saved workflow context', async () => {
  const result = await readPrintSettings({ permitted: (doc, action) => action === 'view' &&
    doc.id === documentId && doc.current_holder_id === reviewerId &&
    doc.current_step === 2 && doc.workflow_version === 4 });
  assert.equal(result.code, 200, JSON.stringify(result.body));
  assert.equal(result.body.document_id, documentId);
});

test('print authorization receives department, source and release context', async () => {
  const result = await readPrintSettings({
    document: { status: 'approved', release_required: true,
      released_at: '2026-11-03T00:00:00Z', released_to_department_id: 'department-b' },
    permitted: (doc, action) => action === 'view' &&
      doc.originating_department_id === 'department-a' && doc.source_module === null &&
      doc.release_required === true && doc.released_to_department_id === 'department-b' &&
      doc.released_at != null,
  });
  assert.equal(result.code, 200, JSON.stringify(result.body));
});

test('a type-wide download grant cannot bypass denied document access', async () => {
  const result = await readPrintSettings({ permitted: (_, action) => action === 'download' });
  assert.equal(result.code, 404);
  assert.deepEqual(result.calls, ['view']);
  assert.equal(result.body.print_layout, undefined);
});

test('document owners and administrators retain print access', async () => {
  for (const user of [{ id: applicantId, role: 'employee' }, { id: reviewerId, role: 'admin' }]) {
    const result = await readPrintSettings({ user, permitted: () => false });
    assert.equal(result.code, 200);
  }
});
