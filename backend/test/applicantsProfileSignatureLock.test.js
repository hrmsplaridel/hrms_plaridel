const test = require('node:test');
const assert = require('node:assert/strict');
const {
  applicantsProfileSignatureState,
  shouldSendApplicantsProfileAssignmentNotice,
} = require('../src/services/applicantsProfileSignatureLock');

const prepared = {
  slot_key: 'prepared_by',
  assigned_signer_id: 'creator',
  signature_asset_id: null,
  signed_at: null,
};
const checked = {
  slot_key: 'checked_by',
  assigned_signer_id: 'hrmdo',
  signature_asset_id: null,
  signed_at: null,
};

test('a new or unassigned Applicants Profile stays editable', () => {
  assert.deepEqual(applicantsProfileSignatureState([]), {
    signature_status: 'needs_setup',
    locked: false,
  });
  assert.deepEqual(applicantsProfileSignatureState([prepared]), {
    signature_status: 'needs_setup',
    locked: false,
  });
});

test('only Prepared By signed does not lock the form', () => {
  const state = applicantsProfileSignatureState([
    { ...prepared, signature_asset_id: 'asset-1', signed_at: '2026-10-11T00:00:00Z' },
    checked,
  ]);
  assert.equal(state.signature_status, 'awaiting_signatures');
  assert.equal(state.locked, false);
});

test('both required signatures lock the form', () => {
  const state = applicantsProfileSignatureState([
    { ...prepared, signature_asset_id: 'asset-1', signed_at: '2026-10-11T00:00:00Z' },
    { ...checked, signature_asset_id: 'asset-2', signed_at: '2026-10-11T01:00:00Z' },
  ]);
  assert.equal(state.signature_status, 'completed');
  assert.equal(state.locked, true);
});

test('Checked By is notified only after Prepared By has signed', () => {
  assert.equal(
    shouldSendApplicantsProfileAssignmentNotice({
      sourceTable: 'applicants_profile_entries',
      slotKey: 'checked_by',
      preparedBySigned: false,
    }),
    false,
  );
  assert.equal(
    shouldSendApplicantsProfileAssignmentNotice({
      sourceTable: 'applicants_profile_entries',
      slotKey: 'checked_by',
      preparedBySigned: true,
    }),
    true,
  );
  assert.equal(
    shouldSendApplicantsProfileAssignmentNotice({
      sourceTable: 'idp_entries',
      slotKey: 'checked_by',
      preparedBySigned: false,
    }),
    true,
  );
  assert.equal(
    shouldSendApplicantsProfileAssignmentNotice({
      sourceTable: 'applicants_profile_entries',
      slotKey: 'prepared_by',
      preparedBySigned: false,
    }),
    true,
  );
});
