'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  canSign, printableSignature, getLocatorSourceSignatures, signLocatorSourceSlot,
  snapshotLocatorReviewers, persistLocatorSignature,
} = require('../src/services/locatorSignatureService');

const requestId = '11111111-1111-4111-8111-111111111111';
const employee = '22222222-2222-4222-8222-222222222222';
const head = '33333333-3333-4333-8333-333333333333';
const final = '44444444-4444-4444-8444-444444444444';
const backup = '55555555-5555-4555-8555-555555555555';
const asset = '66666666-6666-4666-8666-666666666666';
const officials = {
  applicant: { id: employee, name: 'Applicant' },
  department_head: { id: head, name: 'Official Head' },
  hr_approver: { id: final, name: 'Official Final Approver', position_title: 'Municipal HR Officer' },
};
const context = {
  id: requestId, employee_id: employee, employee_name: 'Applicant',
  slip_date_text: '2026-10-01', department_id: requestId,
  signature_revision: 2, status: 'approved', print_signatories: officials, officials,
  dept_head_reviewer_id: head, hr_reviewer_id: final,
};
function ink(signedBy, slot = 'department_head') {
  return { slot_key: slot, signed_by: signedBy, revision: 2,
    signature_asset_id: asset, signature_image_base64: 'aW5r', signed_at: new Date().toISOString() };
}

test('PDF ink requires the named official to be the actual approving actor', () => {
  for (const [slot, actorKey, id] of [
    ['department_head', 'dept_head_reviewer_id', head],
    ['hr_approver', 'hr_reviewer_id', final],
  ]) {
    const signature = ink(id, slot);
    assert.equal(printableSignature(context, slot, signature), signature);
    assert.equal(printableSignature({ ...context, [actorKey]: backup }, slot, signature), null);
    assert.equal(printableSignature(context, slot, ink(backup, slot)), null);
    assert.equal(printableSignature(context, slot, undefined), null);
    assert.equal(printableSignature(context, slot, { ...signature, revision: 1 }), null);
  }
});

test('unsigned decisions and inactive request states never acquire ink', () => {
  for (const status of ['returned_for_correction', 'revoked', 'cancelled', 'rejected_by_hr', 'rejected_by_department_head']) {
    for (const [slot, person] of Object.entries(officials)) {
      assert.equal(printableSignature({ ...context, status }, slot, ink(person.id, slot)), null);
    }
  }
  assert.equal(printableSignature({ ...context, status: 'pending_department_head' }, 'department_head', ink(head)), null);
  assert.equal(printableSignature({ ...context, status: 'pending_hr' }, 'hr_approver', ink(final)), null);
  assert.ok(printableSignature(context, 'applicant', ink(employee, 'applicant')));
  assert.equal(printableSignature(context, 'applicant', ink(backup, 'applicant')), null);
});

test('eligible primary and backup reviewers sign only during their review stage', () => {
  const pending = { ...context, status: 'pending_department_head', reviewer: true };
  assert.equal(canSign(pending, { id: head }, 'department_head'), true);
  assert.equal(canSign(pending, { id: backup }, 'department_head'), true);
  assert.equal(canSign({ ...pending, owner: true }, { id: head }, 'department_head'), false);
  assert.equal(canSign({ ...context, hr: true }, { id: final }, 'hr_approver'), false);
  assert.equal(canSign({ ...context, status: 'pending_hr', canFinalReview: true }, { id: backup }, 'hr_approver'), true);
  assert.equal(canSign({ ...context, hr: true, hr_reviewer_id: backup }, { id: final }, 'hr_approver'), false);
  assert.equal(canSign({ ...context, dept_head_reviewer_id: backup }, { id: head }, 'department_head'), false);
  assert.equal(canSign({ ...context, owner: true, status: 'pending_hr' }, { id: employee }, 'applicant'), true);
  assert.equal(canSign({ ...context, owner: true }, { id: employee }, 'applicant'), false);
});

function mockDb(row, signatures = []) {
  const calls = [];
  let stored = signatures;
  const db = {
    calls,
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql.includes('FROM locator_slips ls')) return { rowCount: 1, rows: [row] };
      if (sql.includes('FROM assignments a JOIN positions p')) {
        return { rows: [{ position_title: 'Historical Position' }] };
      }
      if (sql.includes('FROM docutracker_locator_signatures s')) return { rows: stored };
      if (sql.includes('FROM docutracker_locator_signatures')) {
        const matches = stored.filter((s) => s.revision === params[1] && s.slot_key === params[2] && s.signed_by === params[3]);
        return { rows: matches, rowCount: matches.length };
      }
      if (sql.includes('SELECT full_name FROM users')) return { rowCount: 1, rows: [{ full_name: 'Official Head' }] };
      if (sql.includes('FROM docutracker_signature_assets')) return { rowCount: db.assetOwned ? 1 : 0, rows: [] };
      if (sql.includes('INSERT INTO docutracker_locator_signatures')) {
        stored = [ink(params[4], params[2])];
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO locator_slip_history') || ['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)) return { rows: [] };
      throw new Error(`Unexpected query: ${sql}`);
    },
    release() { calls.push({ sql: 'RELEASE' }); },
    assetOwned: true,
  };
  db.connect = async () => db;
  return db;
}

test('backup approvals keep official names but suppress both official signatures', async () => {
  const db = mockDb({ ...context, dept_head_reviewer_id: backup, hr_reviewer_id: backup }, [ink(head), ink(final, 'hr_approver')]);
  const result = await getLocatorSourceSignatures(db, { id: employee, role: 'employee' }, 'dtr', 'locator_slips', requestId);
  assert.equal(result.print_signatories.department_head.name, 'Official Head');
  assert.equal(result.print_signatories.hr_approver.name, 'Official Final Approver');
  assert.equal(result.print_signatories.hr_approver.position_title, 'Municipal HR Officer');
  assert.equal(result.print_signatories.department_head.signature_image_base64, null);
  assert.equal(result.print_signatories.hr_approver.signature_image_base64, null);
  assert.equal(result.print_form.employee_name, 'Applicant');
});

test('legacy titles resolve for the snapshotted official without replacing their name', async () => {
  const db = mockDb({ ...context, print_signatories: {
    ...officials, hr_approver: { id: final, name: 'Historical Official' },
  } });
  const result = await getLocatorSourceSignatures(db, { id: employee, role: 'employee' }, 'dtr', 'locator_slips', requestId);
  assert.equal(result.print_signatories.hr_approver.name, 'Historical Official');
  assert.equal(result.print_signatories.hr_approver.position_title, 'Historical Position');
  const lookup = db.calls.find((call) => call.sql.includes('FROM assignments a JOIN positions p'));
  assert.deepEqual(lookup.params, [final, context.slip_date_text]);
});

test('unrelated employees cannot read signatures and unsupported sources are rejected', async () => {
  const db = mockDb(context);
  await assert.rejects(getLocatorSourceSignatures(db, { id: backup, role: 'employee' }, 'dtr', 'locator_slips', requestId), { code: 'NOT_FOUND' });
  assert.equal(db.calls.length, 1);
  await assert.rejects(getLocatorSourceSignatures(db, { id: employee }, 'dtr', 'leave_requests', requestId), { code: 'NOT_FOUND' });
});

test('signing locks the request, checks asset ownership, and audits before commit', async () => {
  const db = mockDb({ ...context, status: 'pending_department_head', assigned_department_head_id: head });
  const result = await signLocatorSourceSlot(db, { id: head, role: 'employee' }, 'dtr', 'locator_slips', requestId, 'department_head', { signature_asset_id: asset });
  assert.equal(db.calls[0].sql, 'BEGIN');
  assert.match(db.calls[1].sql, /FOR UPDATE OF ls/);
  const audit = db.calls.find((call) => call.sql.includes('INSERT INTO locator_slip_history'));
  assert.equal(audit.params[4], head);
  assert.equal(JSON.parse(audit.params[8]).signature_asset_id, asset);
  assert.ok(db.calls.findIndex((call) => call === audit) < db.calls.findIndex((call) => call.sql === 'COMMIT'));
  assert.equal(result.signatures[1].signed_by, head);
  assert.equal(result.print_signatories.department_head.signature_image_base64, null);
});

test('foreign assets roll back for both primary and backup reviewers', async () => {
  for (const [actor, assetOwned] of [[head, false], [backup, false]]) {
    const db = mockDb({ ...context, status: 'pending_department_head', is_reviewer: true });
    db.assetOwned = assetOwned;
    await assert.rejects(signLocatorSourceSlot(db, { id: actor, role: 'employee' }, 'dtr', 'locator_slips', requestId, 'department_head', { signature_asset_id: asset }), { code: 'FORBIDDEN' });
    assert.equal(db.calls.some((call) => call.sql.includes('INSERT INTO docutracker_locator_signatures')), false);
    assert.ok(db.calls.some((call) => call.sql === 'ROLLBACK'));
    assert.equal(db.calls.at(-1).sql, 'RELEASE');
  }
});

test('approval requires a signature by this actor on the current revision', async () => {
  const row = { ...context, status: 'pending_department_head', is_reviewer: true };
  for (const signatures of [[], [ink(backup)], [{ ...ink(head), revision: 1 }]]) {
    const db = mockDb(row, signatures);
    await assert.rejects(persistLocatorSignature(db, { id: head, role: 'employee' }, requestId, 'department_head', null), { code: 'CONFLICT' });
  }
  const db = mockDb(row, [ink(head)]);
  await persistLocatorSignature(db, { id: head, role: 'employee' }, requestId, 'department_head', null);
  assert.equal(db.calls.some((call) => call.sql.includes('INSERT INTO')), false);
});

test('backup signature records the backup identity and remains absent from the official PDF block', async () => {
  const db = mockDb({ ...context, status: 'pending_department_head', is_reviewer: true });
  const result = await signLocatorSourceSlot(db, { id: backup, role: 'employee' }, 'dtr', 'locator_slips', requestId, 'department_head', { signature_asset_id: asset });
  assert.equal(result.signatures[1].signed_by, backup);
  assert.equal(result.print_signatories.department_head.name, 'Official Head');
  assert.equal(result.print_signatories.department_head.signature_image_base64, null);
});

test('resubmission requires fresh signature confirmation even if an old signature exists', async () => {
  const db = mockDb({ ...context, status: 'pending_department_head' }, [ink(employee, 'applicant')]);
  await assert.rejects(persistLocatorSignature(db, { id: employee, role: 'employee' }, requestId, 'applicant', null, { requireInput: true }), { code: 'CONFLICT' });
});

test('a missing primary never snapshots the routing backup as the printed head', async () => {
  let captured;
  const db = { async query(sql, params) {
    if (sql.includes('FROM locator_slips ls')) return { rows: [context] };
    if (sql.includes('FROM department_reviewer_backups')) return { rows: [{ reviewer_id: backup, reviewer_name: 'Backup', backup_rank: 1 }] };
    if (sql.includes('FROM leave_final_reviewer_backups')) return { rows: [{ id: backup, name: 'Backup' }] };
    if (sql.includes('SET print_signatories')) captured = JSON.parse(params[1]);
    return { rows: [] };
  } };
  await snapshotLocatorReviewers(db, { requestType: 'locator', requestId, departmentId: requestId, reviewers: [] });
  assert.equal(captured.department_head.id, null);
  assert.equal(captured.department_head.name, '');
  assert.equal(captured.hr_approver.id, null);
});
