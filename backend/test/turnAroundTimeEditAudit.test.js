const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  RSP_SIGNATURE_SLOTS,
  AUTOMATIC_SOURCE_SLOT_RULES,
  creatorOwnedSlotKeys,
} = require('../src/services/docutrackerRspSignatureService');
const {
  TURN_AROUND_TIME_TABLE,
  EDIT_EVENT,
  EDIT_ENTITY,
  SLOT_ORDER,
  RENEWAL_NOTE,
  diffTurnAroundTime,
  signatureStatusFromRows,
  planTatRevision,
  shouldRecordTatEdit,
  shouldSendTatNotedByAssignmentNotice,
  buildContentEditAudit,
  serializeEditHistoryRow,
  renewalStillPending,
} = require('../src/services/turnAroundTimeEditAudit');

const creator = '11111111-1111-4111-8111-111111111111';
const hrmdo = '44444444-4444-4444-8444-444444444444';
const recordId = '22222222-2222-4222-8222-222222222222';
const preparedAsset = '33333333-3333-4333-8333-333333333333';
const notedAsset = '55555555-5555-4555-8555-555555555555';

function baseRow(extra = {}) {
  return {
    id: recordId,
    created_by: creator,
    created_at: '2026-10-01T00:00:00.000Z',
    updated_at: '2026-10-01T00:00:00.000Z',
    position: 'Nurse I',
    office: 'Health Office',
    no_of_vacant_position: '1',
    date_of_publication: '2026-09-01',
    end_search: '2026-09-15',
    qs: 'Bachelor degree',
    prepared_by_name: 'Form Creator',
    prepared_by_title: 'HR Staff',
    noted_by_name: 'HRMDO Official',
    noted_by_title: 'HRMO',
    applicants: [
      {
        application_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        name: 'Ana Cruz',
        date_initial_assessment: '2026-09-02',
        date_contract_exam: '2026-09-03',
        skills_trade_exam_result: 'Passed',
        date_deliberation: '2026-09-04',
        date_job_offer: '2026-09-05',
        acceptance_date: '2026-09-06',
        date_assumption_to_duty: '2026-09-20',
        no_of_days_to_fill_up: '18',
        overall_cost_per_hire: '1500',
      },
    ],
    ...extra,
  };
}

function signedSlot(slotKey, userId, assetId, name) {
  return {
    slot_key: slotKey,
    assigned_signer_id: userId,
    signed_by: userId,
    signer_name_snapshot: name,
    signed_at: '2026-10-02T01:00:00.000Z',
    signature_asset_id: assetId,
  };
}

function assignedSlot(slotKey, userId) {
  return {
    slot_key: slotKey,
    assigned_signer_id: userId,
    signed_by: null,
    signer_name_snapshot: null,
    signed_at: null,
    signature_asset_id: null,
  };
}

test('Prepared By is the creator and Noted By is the active HRMDO official', () => {
  const slots = RSP_SIGNATURE_SLOTS.turn_around_time_entries;
  assert.deepEqual(Object.keys(slots), ['prepared_by', 'noted_by']);
  assert.deepEqual(SLOT_ORDER, ['prepared_by', 'noted_by']);
  assert.equal(AUTOMATIC_SOURCE_SLOT_RULES.turn_around_time_entries.prepared_by, 'creator');
  assert.equal(AUTOMATIC_SOURCE_SLOT_RULES.turn_around_time_entries.noted_by, 'hrmdo');
  assert.deepEqual(creatorOwnedSlotKeys(TURN_AROUND_TIME_TABLE), ['prepared_by']);
  assert.equal(signatureStatusFromRows([]), 'needs_setup');
  assert.equal(
    signatureStatusFromRows([assignedSlot('prepared_by', creator)]),
    'needs_setup',
  );
});

test('Noted By cannot sign until Prepared By has signed', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '../src/services/docutrackerRspSignatureService.js'),
    'utf8',
  );
  const start = source.indexOf('async function signSourceSlot');
  const end = source.indexOf('\nasync function', start + 1);
  const body = source.slice(start, end === -1 ? source.length : end);
  const orderCheck = body.indexOf('earlierUnsignedSlot');
  const signatureWrite = body.indexOf('signature_asset_id = $1');
  assert.ok(orderCheck > 0 && orderCheck < signatureWrite);
  assert.match(body, /must sign before/);
  assert.match(body, /forUpdate: true/);
  assert.match(body, /BEGIN/);
  const rows = [
    assignedSlot('prepared_by', creator),
    assignedSlot('noted_by', hrmdo),
  ];
  assert.equal(signatureStatusFromRows(rows), 'awaiting_signatures');
  const both = [
    signedSlot('prepared_by', creator, preparedAsset, 'Form Creator'),
    signedSlot('noted_by', hrmdo, notedAsset, 'HRMDO Official'),
  ];
  assert.equal(signatureStatusFromRows(both), 'completed');
});

test('editing before any signature records the change and does not clear signatures', () => {
  const before = baseRow();
  const diff = diffTurnAroundTime(before, { ...before, position: 'Nurse II' });
  const plan = planTatRevision({ diff, signatureRows: [
    assignedSlot('prepared_by', creator),
    assignedSlot('noted_by', hrmdo),
  ] });
  assert.equal(plan.record, true);
  assert.deepEqual(plan.clearSlotKeys, []);
  assert.equal(plan.renewalRequired, false);
  assert.equal(plan.signatureStatusBefore, 'awaiting_signatures');
  const audit = buildContentEditAudit({
    recordId,
    actorId: creator,
    actorName: 'Form Creator',
    diff,
    plan,
  });
  assert.equal(audit.eventType, EDIT_EVENT);
  assert.equal(audit.entityType, EDIT_ENTITY);
  assert.equal(audit.afterState.renewal_required, false);
  assert.deepEqual(audit.afterState.signatures_cleared, []);
  assert.equal(shouldRecordTatEdit(audit, 1), true);
  assert.equal(shouldRecordTatEdit(null, 1), false);
});

test('editing after only Prepared By signed clears that signature and keeps both assignments', () => {
  const before = baseRow();
  const diff = diffTurnAroundTime(before, { ...before, office: 'Budget Office' });
  const rows = [
    signedSlot('prepared_by', creator, preparedAsset, 'Form Creator'),
    assignedSlot('noted_by', hrmdo),
  ];
  const plan = planTatRevision({ diff, signatureRows: rows });
  assert.deepEqual(plan.clearSlotKeys, ['prepared_by']);
  assert.equal(plan.renewalRequired, true);
  assert.equal(plan.signaturesCleared[0].assigned_signer_id, creator);
  assert.equal(plan.signaturesCleared[0].signed_by, creator);
  assert.equal(plan.signaturesCleared[0].signature_asset_id, preparedAsset);
  assert.equal(plan.signatureStatusBefore, 'awaiting_signatures');
  const cleared = rows.map((row) => (
    plan.clearSlotKeys.includes(row.slot_key)
      ? { ...row, signature_asset_id: null, signed_by: null, signer_name_snapshot: null, signed_at: null }
      : row
  ));
  assert.equal(cleared[0].assigned_signer_id, creator);
  assert.equal(cleared[1].assigned_signer_id, hrmdo);
  assert.equal(signatureStatusFromRows(cleared), 'awaiting_signatures');
});

test('editing after both sign clears both active signatures and keeps the same people', () => {
  const before = baseRow();
  const diff = diffTurnAroundTime(before, { ...before, qs: 'Licensed nurse' });
  const rows = [
    signedSlot('prepared_by', creator, preparedAsset, 'Form Creator'),
    signedSlot('noted_by', hrmdo, notedAsset, 'HRMDO Official'),
  ];
  const plan = planTatRevision({ diff, signatureRows: rows });
  assert.deepEqual(plan.clearSlotKeys, ['prepared_by', 'noted_by']);
  assert.equal(plan.signatureStatusBefore, 'completed');
  assert.equal(plan.renewalRequired, true);
  const audit = buildContentEditAudit({
    recordId,
    actorId: creator,
    actorName: 'Form Creator',
    diff,
    plan,
  });
  assert.equal(audit.reason, RENEWAL_NOTE);
  assert.equal(audit.beforeState.signatures.length, 2);
  assert.equal(audit.afterState.signed_before_edit, true);
  const payload = JSON.stringify(audit);
  assert.equal(payload.includes('signature_image'), false);
  assert.equal(payload.includes(preparedAsset), true);
  assert.equal(payload.includes(notedAsset), true);
  const history = serializeEditHistoryRow({
    id: 'audit-1',
    created_at: '2026-10-11T04:00:00.000Z',
    actor_id: creator,
    after_state: audit.afterState,
  });
  assert.equal(history.edited_by_name, 'Form Creator');
  assert.equal(history.renewal_required, true);
  assert.equal(history.signatures_cleared[1].signer_name_snapshot, 'HRMDO Official');
  const cleared = rows.map((row) => ({
    ...row,
    signature_asset_id: null,
    signed_by: null,
    signer_name_snapshot: null,
    signed_at: null,
  }));
  assert.equal(signatureStatusFromRows(cleared), 'awaiting_signatures');
  assert.equal(renewalStillPending([history], 'awaiting_signatures'), true);
  assert.equal(renewalStillPending([history], 'completed'), false);
});

test('a no-op save does not clear signatures or write history', () => {
  const before = baseRow();
  const same = diffTurnAroundTime(before, {
    ...before,
    updated_at: '2026-10-11T08:00:00.000Z',
    created_at: '2026-10-11T08:00:00.000Z',
    created_by: '99999999-9999-4999-8999-999999999999',
    position: '  Nurse I  ',
  });
  assert.equal(same, null);
  const plan = planTatRevision({
    diff: same,
    signatureRows: [
      signedSlot('prepared_by', creator, preparedAsset, 'Form Creator'),
      signedSlot('noted_by', hrmdo, notedAsset, 'HRMDO Official'),
    ],
  });
  assert.equal(plan.record, false);
  assert.deepEqual(plan.clearSlotKeys, []);
  assert.equal(shouldRecordTatEdit(null, 1), false);
});

test('material fields include applicants, milestones, costs, and printed names', () => {
  const before = baseRow();
  const position = diffTurnAroundTime(before, { position: 'Midwife I' });
  assert.equal(position.changes[0].field, 'position');
  const vacant = diffTurnAroundTime(before, { no_of_vacant_position: '2' });
  assert.equal(vacant.changes[0].field, 'no_of_vacant_position');
  const published = diffTurnAroundTime(before, { date_of_publication: '2026-09-02' });
  assert.equal(published.changes[0].field, 'date_of_publication');
  const search = diffTurnAroundTime(before, { end_search: '2026-09-16' });
  assert.equal(search.changes[0].field, 'end_search');
  const title = diffTurnAroundTime(before, { noted_by_title: 'HRMO III' });
  assert.equal(title.changes[0].field, 'noted_by_title');
  const applicants = JSON.parse(JSON.stringify(before.applicants));
  applicants[0].skills_trade_exam_result = 'Failed';
  applicants[0].date_assumption_to_duty = '2026-09-21';
  applicants[0].no_of_days_to_fill_up = '19';
  applicants[0].overall_cost_per_hire = '1800';
  applicants[0].application_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const milestone = diffTurnAroundTime(before, { applicants });
  const fields = milestone.changes.map((change) => change.field);
  assert.ok(fields.includes('applicants.skills_trade_exam_result'));
  assert.ok(fields.includes('applicants.date_assumption_to_duty'));
  assert.ok(fields.includes('applicants.no_of_days_to_fill_up'));
  assert.ok(fields.includes('applicants.overall_cost_per_hire'));
  assert.ok(fields.includes('applicants.application_id'));
  const added = diffTurnAroundTime(before, {
    applicants: [
      ...before.applicants,
      { name: 'Ben Santos', application_id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' },
    ],
  });
  assert.ok(added.changes.some((change) => change.field === 'applicants.added'));
  const removed = diffTurnAroundTime(before, { applicants: [] });
  assert.ok(removed.changes.some((change) => change.field === 'applicants.removed'));
  const second = {
    application_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    name: 'Ben Santos',
  };
  const reordered = diffTurnAroundTime(
    { applicants: [before.applicants[0], second] },
    { applicants: [second, before.applicants[0]] },
  );
  assert.ok(reordered.changes.some((change) => change.field === 'applicants.order'));
});

test('Noted By is notified only after Prepared By has signed, including after renewal', () => {
  assert.equal(shouldSendTatNotedByAssignmentNotice({
    sourceTable: TURN_AROUND_TIME_TABLE,
    slotKey: 'noted_by',
    preparedBySigned: false,
  }), false);
  assert.equal(shouldSendTatNotedByAssignmentNotice({
    sourceTable: TURN_AROUND_TIME_TABLE,
    slotKey: 'noted_by',
    preparedBySigned: true,
  }), true);
  assert.equal(shouldSendTatNotedByAssignmentNotice({
    sourceTable: TURN_AROUND_TIME_TABLE,
    slotKey: 'prepared_by',
    preparedBySigned: false,
  }), true);
  assert.equal(shouldSendTatNotedByAssignmentNotice({
    sourceTable: 'applicants_profile_entries',
    slotKey: 'checked_by',
    preparedBySigned: false,
  }), true);
  assert.equal(shouldSendTatNotedByAssignmentNotice({
    sourceTable: 'selection_lineup_entries',
    slotKey: 'prepared_by',
    preparedBySigned: false,
  }), true);
  const source = fs.readFileSync(
    path.join(__dirname, '../src/services/docutrackerRspSignatureService.js'),
    'utf8',
  );
  const progress = source.slice(
    source.indexOf('async function notifySignatureProgress'),
    source.indexOf('async function insertSourceSignatureAssignment'),
  );
  assert.match(progress, /source_signature_turn/);
  assert.match(progress, /source_signature_completed/);
  assert.match(progress, /insertNotification/);
  assert.doesNotMatch(progress, /email/i);
  const sign = source.slice(source.indexOf('async function signSourceSlot'));
  assert.match(sign, /if \(!current\.signature_asset_id\)/);
  const gate = source.slice(
    source.indexOf('async function notifySourceAssignmentIfDue'),
    source.indexOf('async function readApplicantsProfileSignatureLock'),
  );
  assert.match(gate, /APPLICANTS_PROFILE_TABLE && notice\.slotKey === 'checked_by'/);
  assert.match(gate, /TURN_AROUND_TIME_TABLE && notice\.slotKey === 'noted_by'/);
  assert.match(gate, /tatPreparedByHasSigned/);
});

test('the save transaction locks the form, clears signatures, then writes the audit', () => {
  const route = fs.readFileSync(
    path.join(__dirname, '../src/routes/rspLdSavedEntries.js'),
    'utf8',
  );
  const start = route.indexOf('let tatAudit = null');
  const commit = route.indexOf("await client.query('COMMIT')", start);
  const region = route.slice(start, commit);
  const formLock = region.indexOf('FOR UPDATE');
  const clear = region.indexOf('signature_asset_id = NULL');
  const contentUpdate = region.indexOf('const q = `UPDATE');
  const auditWrite = region.indexOf('writeGovernanceAudit(client, tatAudit)');
  assert.ok(formLock >= 0 && formLock < clear);
  assert.ok(clear < contentUpdate);
  assert.ok(contentUpdate < auditWrite);
  assert.match(region, /slot_key = ANY\(\$3::text\[\]\)/);
  assert.doesNotMatch(region.slice(region.indexOf('UPDATE docutracker_rsp_source_signatures'), region.indexOf('const actor')), /assigned_signer_id = NULL/);
  const sign = fs.readFileSync(
    path.join(__dirname, '../src/services/docutrackerRspSignatureService.js'),
    'utf8',
  );
  const signBody = sign.slice(sign.indexOf('async function signSourceSlot'));
  const signLock = signBody.indexOf('forUpdate: true');
  const signWrite = signBody.indexOf('signature_asset_id = $1');
  assert.ok(signLock > 0 && signLock < signWrite);
  assert.doesNotMatch(
    fs.readFileSync(path.join(__dirname, '../src/services/turnAroundTimeEditAudit.js'), 'utf8'),
    /ALTER TABLE|CREATE TABLE/i,
  );
});

test('authorized delete removes only that form’s signature rows and keeps the audit', () => {
  const route = fs.readFileSync(
    path.join(__dirname, '../src/routes/rspLdSavedEntries.js'),
    'utf8',
  );
  const first = route.indexOf('if (table === TURN_AROUND_TIME_TABLE)');
  const second = route.indexOf('if (table === TURN_AROUND_TIME_TABLE)', first + 1);
  const block = route.slice(second, route.indexOf('const q = `DELETE FROM', second));
  assert.match(block, /BEGIN/);
  assert.match(block, /FOR UPDATE/);
  assert.match(block, /DELETE FROM docutracker_rsp_source_signatures/);
  assert.match(block, /TURN_AROUND_TIME_TABLE, id/);
  assert.match(block, /COMMIT/);
  assert.doesNotMatch(block, /docutracker_governance_audit/);
  assert.doesNotMatch(block, /recruitment_applications/);
  assert.doesNotMatch(block, /tat_status/);
});

test('other RSP and L&D workflows stay on their own rules', () => {
  const lock = fs.readFileSync(
    path.join(__dirname, '../src/services/applicantsProfileSignatureLock.js'),
    'utf8',
  );
  assert.match(lock, /APPLICANTS_PROFILE_LOCKED/);
  assert.doesNotMatch(lock, /turn_around_time/);
  const lineup = fs.readFileSync(
    path.join(__dirname, '../src/services/selectionLineupEditAudit.js'),
    'utf8',
  );
  assert.match(lineup, /selection_lineup_content_edited/);
  assert.doesNotMatch(lineup, /turn_around_time/);
  const scoring = fs.readFileSync(
    path.join(__dirname, '../src/services/computationOfPointsEditAudit.js'),
    'utf8',
  );
  assert.match(scoring, /computation_of_points_content_edited/);
  assert.doesNotMatch(scoring, /signature_asset_id = NULL/);
  assert.doesNotMatch(scoring, /turn_around_time/);
  const hiring = fs.readFileSync(
    path.join(__dirname, '../src/services/rspFinalHiring.js'),
    'utf8',
  );
  const complete = hiring.slice(
    hiring.indexOf('async function completeTurnAroundTime'),
    hiring.indexOf('async function', hiring.indexOf('async function completeTurnAroundTime') + 1),
  );
  assert.match(complete, /tat_status = 'completed'/);
  assert.doesNotMatch(complete, /docutracker_rsp_source_signatures/);
  assert.doesNotMatch(complete, /turn_around_time_entries/);
  const profileSlots = RSP_SIGNATURE_SLOTS.applicants_profile_entries;
  assert.deepEqual(Object.keys(profileSlots), ['prepared_by', 'checked_by']);
  const lineupSlots = RSP_SIGNATURE_SLOTS.selection_lineup_entries;
  assert.deepEqual(Object.keys(lineupSlots), ['prepared_by']);
  const scoreSlots = RSP_SIGNATURE_SLOTS.computation_of_points_entries;
  assert.deepEqual(Object.keys(scoreSlots), ['prepared_by']);
});
