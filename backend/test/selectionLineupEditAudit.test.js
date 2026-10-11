const test = require('node:test');
const assert = require('node:assert/strict');
const {
  SELECTION_LINEUP_TABLE,
  diffSelectionLineup,
  signatureStateFromSlot,
  resolveLineupCreatorId,
  buildContentEditAudit,
  SIGNED_EDIT_NOTE,
} = require('../src/services/selectionLineupEditAudit');

const creator = '11111111-1111-4111-8111-111111111111';

test('a lineup has one prepared-by slot and the creator id is the server user', () => {
  assert.equal(SELECTION_LINEUP_TABLE, 'selection_lineup_entries');
  assert.equal(resolveLineupCreatorId(creator), creator);
  assert.throws(() => resolveLineupCreatorId('someone-else'), /authenticated creator/);
  assert.throws(() => resolveLineupCreatorId(''), /authenticated creator/);
});

test('unchanged content and timestamps do not create an audit diff', () => {
  const row = {
    vacant_position: 'Nurse I',
    applicants: [{ name: 'Ana Cruz' }],
    updated_at: '2026-01-01',
  };
  assert.equal(
    diffSelectionLineup(row, {
      vacant_position: 'Nurse I',
      applicants: JSON.stringify([{ name: 'Ana Cruz' }]),
      updated_at: '2026-10-11',
    }),
    null,
  );
});

test('a real field change is recorded with previous and next values', () => {
  const diff = diffSelectionLineup(
    { vacant_position: 'Nurse I', item_no: '1' },
    { vacant_position: 'Nurse II', item_no: '1' },
  );
  assert.equal(diff.changes.length, 1);
  assert.equal(diff.changes[0].field, 'vacant_position');
  assert.equal(diff.previous.vacant_position, 'Nurse I');
  assert.equal(diff.next.vacant_position, 'Nurse II');
});

test('one prepared-by signature completes the status and stays completed in the audit', () => {
  assert.equal(signatureStateFromSlot(null).signature_status, 'needs_setup');
  assert.equal(
    signatureStateFromSlot({ assigned_signer_id: creator }).signature_status,
    'awaiting_signatures',
  );
  const signed = signatureStateFromSlot({
    assigned_signer_id: creator,
    signature_asset_id: 'asset',
    signed_at: '2026-10-11T01:00:00.000Z',
    signer_name_snapshot: 'Form Creator',
  });
  assert.equal(signed.signature_status, 'completed');
  const audit = buildContentEditAudit({
    recordId: '22222222-2222-4222-8222-222222222222',
    actorId: creator,
    actorName: 'Form Creator',
    diff: diffSelectionLineup({ item_no: '1' }, { item_no: '2' }),
    signature: signed,
  });
  assert.equal(audit.eventType, 'selection_lineup_content_edited');
  assert.equal(audit.afterState.signed_when_edited, true);
  assert.equal(audit.afterState.signature_status, 'completed');
  assert.equal(audit.afterState.signature_signed_at, '2026-10-11T01:00:00.000Z');
  assert.equal(audit.reason, SIGNED_EDIT_NOTE);
  assert.equal(audit.beforeState.values.item_no, '1');
  assert.equal(audit.afterState.values.item_no, '2');
});

test('an edit before signing is audited without the after-signing note', () => {
  const audit = buildContentEditAudit({
    recordId: '22222222-2222-4222-8222-222222222222',
    actorId: creator,
    actorName: 'Form Creator',
    diff: diffSelectionLineup({ date: '2026-01-01' }, { date: '2026-02-01' }),
    signature: signatureStateFromSlot({ assigned_signer_id: creator }),
  });
  assert.equal(audit.afterState.signed_when_edited, false);
  assert.equal(audit.afterState.integrity_note, null);
});
