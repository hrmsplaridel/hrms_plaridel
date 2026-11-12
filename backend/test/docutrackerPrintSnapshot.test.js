const test = require('node:test');
const assert = require('node:assert/strict');
const {
  snapshotFromTypeDefault,
  resolvedPrintVersionId,
  printSnapshotMeta,
  isBuiltinOfficialType,
  isDraftOrWipPrintDocument,
  adoptTypePrintSnapshotForDraft,
} = require('../src/services/docutrackerPrintSnapshot');

test('builtin memo and purchase request are official types', () => {
  assert.equal(isBuiltinOfficialType('memo'), true);
  assert.equal(isBuiltinOfficialType('purchaseRequest'), true);
  assert.equal(isBuiltinOfficialType('travel_order'), false);
});

test('snapshotFromTypeDefault returns official when type has no custom layout', async () => {
  const db = {
    async query() {
      return { rows: [{ version_id: null, print_layout: null }] };
    },
  };
  assert.deepEqual(await snapshotFromTypeDefault(db, 'memo'), {
    print_form_selection: 'official',
    print_template_version_id: null,
  });
});

test('snapshotFromTypeDefault returns custom when type points at a layout version', async () => {
  const versionId = '10000000-0000-4000-8000-000000000099';
  const db = {
    async query() {
      return {
        rows: [{ version_id: versionId, print_layout: { elements: [] } }],
      };
    },
  };
  assert.deepEqual(await snapshotFromTypeDefault(db, 'travel_order'), {
    print_form_selection: 'custom',
    print_template_version_id: versionId,
  });
});

test('resolvedPrintVersionId freezes custom and official snapshots', () => {
  const typeCurrent = '10000000-0000-4000-8000-000000000001';
  const frozen = '10000000-0000-4000-8000-000000000002';
  assert.equal(
    resolvedPrintVersionId(
      {
        print_form_selection: 'custom',
        print_template_version_id: frozen,
        document_type: 'travel_order',
      },
      typeCurrent,
    ),
    frozen,
  );
  assert.equal(
    resolvedPrintVersionId(
      {
        print_form_selection: 'official',
        print_template_version_id: null,
        document_type: 'memo',
      },
      typeCurrent,
    ),
    null,
  );
});

test('legacy unset memo ignores live type template; custom types may follow type', () => {
  const typeCurrent = '10000000-0000-4000-8000-000000000001';
  assert.equal(
    resolvedPrintVersionId(
      {
        print_form_selection: 'unset',
        print_template_version_id: null,
        document_type: 'memo',
      },
      typeCurrent,
    ),
    null,
  );
  assert.equal(
    resolvedPrintVersionId(
      {
        print_form_selection: 'unset',
        print_template_version_id: null,
        document_type: 'travel_order',
      },
      typeCurrent,
    ),
    typeCurrent,
  );
});

test('printSnapshotMeta marks unset as legacy', () => {
  assert.deepEqual(printSnapshotMeta({ print_form_selection: 'custom' }), {
    print_form_selection: 'custom',
    print_snapshot_legacy: false,
  });
  assert.deepEqual(printSnapshotMeta({ print_form_selection: 'unset' }), {
    print_form_selection: 'unset',
    print_snapshot_legacy: true,
  });
});

test('isDraftOrWipPrintDocument matches pending unsent drafts', () => {
  assert.equal(
    isDraftOrWipPrintDocument({
      status: 'pending',
      current_holder_id: null,
      current_step: null,
      sent_time: null,
    }),
    true,
  );
  assert.equal(
    isDraftOrWipPrintDocument({
      status: 'in_review',
      current_holder_id: null,
      current_step: 1,
      sent_time: '2026-11-12T00:00:00Z',
    }),
    false,
  );
});

test('adoptTypePrintSnapshotForDraft stamps custom layout onto unset drafts', async () => {
  const versionId = '10000000-0000-4000-8000-000000000077';
  const calls = [];
  const db = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (/FROM docutracker_document_types/i.test(sql)) {
        return {
          rows: [{ version_id: versionId, print_layout: { elements: [] } }],
        };
      }
      return { rows: [] };
    },
  };
  const doc = {
    id: '10000000-0000-4000-8000-000000000088',
    document_type: 'memo',
    status: 'pending',
    current_holder_id: null,
    current_step: null,
    sent_time: null,
    print_form_selection: 'unset',
    print_template_version_id: null,
  };
  assert.equal(await adoptTypePrintSnapshotForDraft(db, doc), true);
  assert.equal(doc.print_form_selection, 'custom');
  assert.equal(doc.print_template_version_id, versionId);
  assert.equal(calls.length, 2);
});

test('adoptTypePrintSnapshotForDraft leaves submitted documents alone', async () => {
  const db = {
    async query() {
      throw new Error('should not query');
    },
  };
  assert.equal(
    await adoptTypePrintSnapshotForDraft(db, {
      id: '10000000-0000-4000-8000-000000000088',
      document_type: 'memo',
      status: 'in_review',
      current_holder_id: 'u1',
      current_step: 1,
      sent_time: '2026-11-12T00:00:00Z',
      print_form_selection: 'unset',
      print_template_version_id: null,
    }),
    false,
  );
});
