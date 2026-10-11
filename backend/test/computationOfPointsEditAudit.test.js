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
  COMPUTATION_OF_POINTS_TABLE,
  EDIT_EVENT,
  SCORE_MAX,
  SIGNED_EDIT_NOTE,
  diffComputationOfPoints,
  signatureStateFromSlot,
  shouldRecordContentEdit,
  formulaTotal,
  formulaRanks,
  buildContentEditAudit,
  serializeEditHistoryRow,
} = require('../src/services/computationOfPointsEditAudit');

const creator = '11111111-1111-4111-8111-111111111111';
const recordId = '22222222-2222-4222-8222-222222222222';

function candidate(name, education, total, rank, extra = {}) {
  return {
    name,
    education,
    total,
    rank,
    ...extra,
  };
}

test('computation of points has one prepared-by slot assigned to the creator', () => {
  const slots = RSP_SIGNATURE_SLOTS.computation_of_points_entries;
  assert.deepEqual(Object.keys(slots), ['prepared_by']);
  assert.equal(slots.prepared_by, 'Prepared by');
  assert.equal(
    AUTOMATIC_SOURCE_SLOT_RULES.computation_of_points_entries.prepared_by,
    'creator',
  );
  assert.deepEqual(creatorOwnedSlotKeys(COMPUTATION_OF_POINTS_TABLE), ['prepared_by']);
  assert.equal(signatureStateFromSlot(null).signature_status, 'needs_setup');
  assert.equal(
    signatureStateFromSlot({ assigned_signer_id: creator }).signature_status,
    'awaiting_signatures',
  );
});

test('signing is limited to the assigned active creator and one signature completes the slot', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '../src/services/docutrackerRspSignatureService.js'),
    'utf8',
  );
  const start = source.indexOf('async function signSourceSlot');
  const end = source.indexOf('async function', start + 1);
  const body = source.slice(start, end === -1 ? source.length : end);
  assert.match(body, /Only the assigned person can sign this field/);
  assert.match(body, /assigned_signer_id\) !== String\(user\.id\)/);
  assert.match(body, /owner_user_id = \$2::uuid/);
  assert.match(body, /is_active = true/);
  assert.match(body, /signer_name_snapshot/);
  assert.match(body, /signed_at = now\(\)/);
  assert.doesNotMatch(body, /isAdmin/);
  const signed = signatureStateFromSlot({
    assigned_signer_id: creator,
    signature_asset_id: '33333333-3333-4333-8333-333333333333',
    signed_at: '2026-10-11T01:00:00.000Z',
    signer_name_snapshot: 'Form Creator',
  });
  assert.equal(signed.signature_status, 'completed');
  assert.match(source, /return complete \? 'completed' : 'awaiting_signatures'/);
});

test('a no-op save, including a newer timestamp, does not create an audit diff', () => {
  const row = {
    position: 'Nurse I',
    candidates: [candidate('Ana Cruz', '20', '20.00', '1')],
    updated_at: '2026-01-01T00:00:00.000Z',
  };
  assert.equal(
    diffComputationOfPoints(row, {
      position: 'Nurse I',
      candidates: JSON.stringify([candidate('Ana Cruz', '20', '20.00', '1')]),
      updated_at: '2026-10-11T00:00:00.000Z',
    }),
    null,
  );
  assert.equal(shouldRecordContentEdit(null, 1), false);
});

test('failed or empty saves do not qualify for an audit record', () => {
  const diff = diffComputationOfPoints(
    { position: 'Nurse I' },
    { position: 'Nurse II' },
  );
  assert.equal(shouldRecordContentEdit(diff, 0), false);
  assert.equal(shouldRecordContentEdit(null, 0), false);
  assert.equal(shouldRecordContentEdit(diff, 1), true);
});

test('a score change is logged for that candidate and does not claim the signature approved it', () => {
  const diff = diffComputationOfPoints(
    { candidates: [candidate('Ana Cruz', '20', '20.00', '1'), candidate('Ben Santos', '10', '10.00', '2')] },
    { candidates: [candidate('Ana Cruz', '25', '25.00', '1'), candidate('Ben Santos', '10', '10.00', '2')] },
  );
  const education = diff.changes.find((change) => change.field === 'candidates.education');
  assert.equal(education.candidate, 'Ana Cruz');
  assert.equal(education.previous, '20');
  assert.equal(education.next, '25');
  assert.equal(education.value_kind, 'entered');
  assert.equal(
    diff.changes.some((change) => change.candidate === 'Ben Santos' && change.field === 'candidates.education'),
    false,
  );
  const signed = signatureStateFromSlot({
    assigned_signer_id: creator,
    signature_asset_id: 'asset',
    signed_at: '2026-10-11T01:00:00.000Z',
    signer_name_snapshot: 'Form Creator',
  });
  const audit = buildContentEditAudit({
    recordId,
    actorId: creator,
    actorName: 'Form Creator',
    diff,
    signature: signed,
  });
  assert.equal(audit.eventType, EDIT_EVENT);
  assert.equal(audit.actorId, creator);
  assert.equal(audit.afterState.actor_name, 'Form Creator');
  assert.equal(audit.afterState.signed_when_edited, true);
  assert.equal(audit.afterState.signature_status, 'completed');
  assert.equal(audit.afterState.signature_signed_at, '2026-10-11T01:00:00.000Z');
  assert.equal(audit.afterState.signer_name_snapshot, 'Form Creator');
  assert.equal(audit.reason, SIGNED_EDIT_NOTE);
  assert.equal(audit.beforeState.signature_asset_id, undefined);
  const history = serializeEditHistoryRow({
    id: 'audit-1',
    created_at: '2026-10-11T02:00:00.000Z',
    actor_id: creator,
    after_state: audit.afterState,
  });
  assert.equal(history.edited_by_name, 'Form Creator');
  assert.equal(history.signed_when_edited, true);
  assert.equal(history.changes[0].candidate, 'Ana Cruz');
});

test('total and rank changes are marked calculated when they match the screen formula', () => {
  const before = [
    candidate('Ana Cruz', '20', '20.00', '1'),
    candidate('Ben Santos', '20', '20.00', '1'),
  ];
  const after = [
    candidate('Ana Cruz', '25', '25.00', '1'),
    candidate('Ben Santos', '20', '20.00', '2'),
  ];
  assert.equal(formulaTotal(after[0]), '25.00');
  assert.equal(formulaRanks(after).get(0), '1');
  assert.equal(formulaRanks(after).get(1), '2');
  const diff = diffComputationOfPoints({ candidates: before }, { candidates: after });
  const total = diff.changes.find(
    (change) => change.candidate === 'Ana Cruz' && change.field === 'candidates.total',
  );
  const rank = diff.changes.find(
    (change) => change.candidate === 'Ben Santos' && change.field === 'candidates.rank',
  );
  assert.equal(total.previous, '20.00');
  assert.equal(total.next, '25.00');
  assert.equal(total.value_kind, 'calculated');
  assert.equal(rank.previous, '1');
  assert.equal(rank.next, '2');
  assert.equal(rank.value_kind, 'calculated');
  const mismatched = diffComputationOfPoints(
    { candidates: [candidate('Ana Cruz', '20', '20.00', '1')] },
    { candidates: [candidate('Ana Cruz', '20', '99.00', '9')] },
  );
  assert.equal(
    mismatched.changes.find((change) => change.field === 'candidates.total').value_kind,
    'stored',
  );
  assert.equal(
    mismatched.changes.find((change) => change.field === 'candidates.rank').value_kind,
    'stored',
  );
});

test('reordering keeps each candidate score with that candidate', () => {
  const ana = candidate('Ana Cruz', '20', '20.00', '2');
  const ben = candidate('Ben Santos', '25', '25.00', '1');
  const diff = diffComputationOfPoints(
    { candidates: [ana, ben] },
    { candidates: [ben, ana] },
  );
  assert.equal(
    diff.changes.some((change) => change.field === 'candidates.education'),
    false,
  );
  const order = diff.changes.find((change) => change.field === 'candidates.order');
  assert.deepEqual(order.previous, ['Ana Cruz', 'Ben Santos']);
  assert.deepEqual(order.next, ['Ben Santos', 'Ana Cruz']);
});

test('candidate additions and removals are logged without moving scores onto someone else', () => {
  const ana = candidate('Ana Cruz', '20', '20.00', '1');
  const ben = candidate('Ben Santos', '10', '10.00', '2');
  const added = diffComputationOfPoints(
    { candidates: [ana] },
    { candidates: [ana, ben] },
  );
  const addition = added.changes.find((change) => change.field === 'candidates.added');
  assert.equal(addition.candidate, 'Ben Santos');
  assert.equal(addition.previous, null);
  assert.equal(addition.next.education, '10');
  assert.equal(
    added.changes.some((change) => change.candidate === 'Ana Cruz' && change.field === 'candidates.education'),
    false,
  );
  const removed = diffComputationOfPoints(
    { candidates: [ana, ben] },
    { candidates: [ana] },
  );
  const removal = removed.changes.find((change) => change.field === 'candidates.removed');
  assert.equal(removal.candidate, 'Ben Santos');
  assert.equal(removal.previous.education, '10');
  assert.equal(removal.next, null);
});

test('an edit before signing is audited without the after-signing note', () => {
  const audit = buildContentEditAudit({
    recordId,
    actorId: creator,
    actorName: 'Form Creator',
    diff: diffComputationOfPoints({ position: 'Nurse I' }, { position: 'Nurse II' }),
    signature: signatureStateFromSlot({ assigned_signer_id: creator }),
  });
  assert.equal(audit.afterState.signed_when_edited, false);
  assert.equal(audit.afterState.signature_status, 'awaiting_signatures');
  assert.equal(audit.afterState.integrity_note, null);
  assert.equal(audit.beforeState.values.position, 'Nurse I');
  assert.equal(audit.afterState.values.position, 'Nurse II');
});

test('save and delete keep this form separate from Applicants Profile and Selection Line-Up', () => {
  const route = fs.readFileSync(
    path.join(__dirname, '../src/routes/rspLdSavedEntries.js'),
    'utf8',
  );
  const lineup = fs.readFileSync(
    path.join(__dirname, '../src/services/selectionLineupEditAudit.js'),
    'utf8',
  );
  const lock = fs.readFileSync(
    path.join(__dirname, '../src/services/applicantsProfileSignatureLock.js'),
    'utf8',
  );
  assert.match(lineup, /selection_lineup_content_edited/);
  assert.doesNotMatch(lineup, /computation_of_points/);
  assert.match(lock, /APPLICANTS_PROFILE_LOCKED/);
  assert.doesNotMatch(lock, /computation_of_points/);
  assert.match(route, /if \(table === APPLICANTS_PROFILE_TABLE\)/);
  assert.match(route, /if \(table === SELECTION_LINEUP_TABLE\)/);
  assert.match(route, /if \(table === COMPUTATION_OF_POINTS_TABLE\)/);
  const deleteStart = route.indexOf('router.delete');
  const deleteBody = route.slice(deleteStart);
  assert.match(deleteBody, /COMPUTATION_OF_POINTS_TABLE, id/);
  assert.doesNotMatch(deleteBody, /docutracker_governance_audit/);
  const putStart = route.indexOf("router.put('/:table/:id'");
  const putBody = route.slice(putStart, deleteStart);
  const computationStart = putBody.indexOf('if (table === COMPUTATION_OF_POINTS_TABLE)');
  const profileStart = putBody.indexOf('if (table === APPLICANTS_PROFILE_TABLE)');
  const computationPut = putBody.slice(computationStart, profileStart);
  assert.doesNotMatch(computationPut, /readApplicantsProfileSignatureLock/);
  assert.doesNotMatch(computationPut, /signed_at = null/);
  assert.match(putBody, /writeGovernanceAudit\(client, computationAudit\)/);
  assert.match(route, /router\.use\(authMiddleware, requireAdmin\)/);
});

test('the screen score caps are unchanged and the audit does not rewrite them', () => {
  const dart = fs.readFileSync(
    path.join(
      __dirname,
      '../../frontend/lib/features/recruitment/presentation/admin/sections/computation_of_points_section.dart',
    ),
    'utf8',
  );
  assert.match(dart, /_ScoreCriterion\('education', 'Education', 25\)/);
  assert.match(dart, /_ScoreCriterion\('eligibility', 'Eligibility', 20\)/);
  assert.match(dart, /_ScoreCriterion\('experience', 'Experience', 15\)/);
  assert.match(dart, /_ScoreCriterion\('training', 'Training', 10\)/);
  assert.match(dart, /_ScoreCriterion\('performance', 'Performance', 10\)/);
  assert.match(dart, /_ScoreCriterion\('potential', 'Potential', 10\)/);
  assert.match(dart, /_ScoreCriterion\('workAttitude', 'Work Attitude', 10\)/);
  assert.match(dart, /sum \+= v\.clamp\(0, c\.max\)/);
  assert.match(dart, /row\['total'\]!\.text = sum\.toStringAsFixed\(2\)/);
  assert.equal(SCORE_MAX.education, 25);
  assert.equal(SCORE_MAX.eligibility, 20);
  assert.equal(SCORE_MAX.experience, 15);
  assert.equal(SCORE_MAX.training, 10);
  assert.equal(SCORE_MAX.performance, 10);
  assert.equal(SCORE_MAX.potential, 10);
  assert.equal(SCORE_MAX.work_attitude, 10);
});
