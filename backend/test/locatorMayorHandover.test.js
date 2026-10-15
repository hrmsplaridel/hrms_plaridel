'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { getLocatorSourceSignatures, signLocatorSourceSlot, persistLocatorSignature } = require('../src/services/locatorSignatureService');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const id = '11111111-1111-4111-8111-111111111111';
const employee = '22222222-2222-4222-8222-222222222222';
const former = '33333333-3333-4333-8333-333333333333';
const current = '44444444-4444-4444-8444-444444444444';
const asset = '55555555-5555-4555-8555-555555555555';
const foreignAsset = '66666666-6666-4666-8666-666666666666';
const user = { id: current, role: 'mayor' };
const officials = {
  applicant: { id: employee, name: 'Employee', position_title: 'Administrative Aide' },
  department_head: { id: null, name: '', position_title: '' },
  hr_approver: { id: former, name: 'Former Mayor', position_title: 'Municipal Mayor' },
};
const signature = signedBy => ({ slot_key: 'hr_approver', revision: 2, signed_by: signedBy,
  signature_asset_id: asset, signature_image_base64: 'aW5r' });

function fixture(overrides = {}, signatures = []) {
  let state = { row: { id, employee_id: employee, employee_name: 'Employee', slip_date: '2026-10-15',
    slip_date_text: '2026-10-15', status: 'pending_mayor', final_review_route: 'mayor_direct',
    final_reviewer_user_id: former, print_signatories: structuredClone(officials), signature_revision: 2,
    request_type: 'locator', request_type_requires_attachment_snapshot: false, am_in: true,
    ...overrides }, signatures: structuredClone(signatures), history: [] };
  let before;
  const calls = [];
  const db = {
    calls, activeMayor: current, failSignatureWrite: false,
    get state() { return state; },
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (sql === 'BEGIN') { before = structuredClone(state); return { rows: [] }; }
      if (sql === 'ROLLBACK') { if (before) state = before; return { rows: [] }; }
      if (sql === 'COMMIT' || /^CREATE /.test(sql.trim()) || sql.includes('INSERT INTO locator_request_types') ||
          sql.trim().startsWith('UPDATE locator_slips AS slip')) return { rows: [] };
      if (sql.includes("= 'mayor'")) return { rows: db.activeMayor ? [{ employee_id: db.activeMayor,
        name: 'Replacement Mayor', position_title: 'Municipal Mayor' }] : [] };
      if (sql.includes('FROM users') && sql.includes('FOR SHARE')) {
        if (db.beforeAuthorityLock) db.beforeAuthorityLock();
        return { rows: params[0] === db.activeMayor ? [{ id: params[0] }] : [], rowCount: params[0] === db.activeMayor ? 1 : 0 };
      }
      if (sql.includes('FROM locator_slips ls')) return { rows: [structuredClone(state.row)], rowCount: 1 };
      if (sql.startsWith('SELECT final_review_route')) return { rows: [{ final_review_route: state.row.final_review_route }] };
      if (sql.includes('AS department_approver_id')) return { rows: [{ department_approver_id: null }] };
      if (sql.startsWith('SELECT full_name FROM users')) return { rows: [{ full_name: 'Replacement Mayor' }], rowCount: 1 };
      if (sql.includes('FROM docutracker_signature_assets')) return { rows: [], rowCount: params[0] === asset ? 1 : 0 };
      if (sql.includes('INSERT INTO docutracker_locator_signatures')) {
        if (db.failSignatureWrite) throw new Error('Simulated signature storage failure');
        state.signatures = state.signatures.filter(s => s.slot_key !== params[2]);
        state.signatures.push({ ...signature(params[4]), slot_key: params[2], revision: params[1] });
        return { rows: [] };
      }
      if (sql.includes('FROM docutracker_locator_signatures s')) return { rows: structuredClone(state.signatures) };
      if (sql.includes('FROM docutracker_locator_signatures')) {
        const matches = state.signatures.filter(s => s.revision === params[1] && s.slot_key === params[2] && s.signed_by === params[3]);
        return { rows: matches, rowCount: matches.length };
      }
      if (sql.includes('UPDATE locator_slips') && sql.includes('final_reviewer_user_id')) {
        state.row.final_reviewer_user_id = params[1];
        state.row.print_signatories = JSON.parse(params[2]);
        return { rows: [structuredClone(state.row)], rowCount: 1 };
      }
      if (sql.includes('UPDATE locator_slips') && sql.includes("status = 'approved'")) {
        Object.assign(state.row, { status: 'approved', hr_reviewer_id: params[1] });
        return { rows: [structuredClone(state.row)], rowCount: 1 };
      }
      if (sql.includes('INSERT INTO locator_slip_history')) {
        state.history.push({ action: params[1], from_status: params[2], to_status: params[3], actor_id: params[4], metadata: JSON.parse(params[8]) });
        return { rows: [] };
      }
      if (sql.includes('UPDATE user_notifications')) return { rows: [] };
      throw new Error(`Unexpected query: ${sql}`);
    },
    release() {},
  };
  db.connect = async () => db;
  return db;
}

test('replacement Mayor signing reassigns pending authority and printed identity with an audit event', async () => {
  const db = fixture();
  const result = await signLocatorSourceSlot(db, user, 'dtr', 'locator_slips', id, 'hr_approver', { signature_asset_id: asset });
  assert.equal(db.state.row.final_reviewer_user_id, current);
  assert.deepEqual(db.state.row.print_signatories.hr_approver, { id: current, name: 'Replacement Mayor', position_title: 'Municipal Mayor' });
  assert.deepEqual(db.state.row.print_signatories.applicant, officials.applicant);
  assert.deepEqual(db.state.row.print_signatories.department_head, officials.department_head);
  assert.equal(db.state.row.signature_revision, 2);
  assert.equal(result.signatures[2].assigned_signer_id, current);
  const handover = db.state.history.find(e => e.action === 'mayor_reassigned');
  assert.ok(handover);
  assert.equal(handover.actor_id, current);
  assert.equal(handover.from_status, 'pending_mayor');
  assert.equal(handover.to_status, 'pending_mayor');
  assert.equal(handover.metadata.previous_final_reviewer_user_id, former);
  assert.deepEqual(handover.metadata.previous_printed_approver, officials.hr_approver);
  assert.equal(handover.metadata.new_final_reviewer_user_id, current);
  assert.deepEqual(handover.metadata.new_printed_approver, db.state.row.print_signatories.hr_approver);
  assert.equal(db.state.history.at(-1).action, 'signed');
  assert.ok(db.calls.some(c => /FOR UPDATE OF ls/.test(c.sql)));
  assert.ok(db.calls.some(c => /FROM users/.test(c.sql) && /FOR SHARE/.test(c.sql)));
});

test('an existing current-Mayor signature repairs a pending legacy mismatch before approval', async () => {
  const db = fixture({}, [signature(current)]);
  await persistLocatorSignature(db, user, id, 'hr_approver', null);
  assert.equal(db.state.row.final_reviewer_user_id, current);
  assert.equal(db.state.row.print_signatories.hr_approver.id, current);
  assert.equal(db.state.history.filter(e => e.action === 'mayor_reassigned').length, 1);
  await persistLocatorSignature(db, user, id, 'hr_approver', null);
  assert.equal(db.state.history.filter(e => e.action === 'mayor_reassigned').length, 1);
});

test('a pending legacy request with missing final identity is snapshotted when validly signed', async () => {
  const db = fixture({ final_reviewer_user_id: null, print_signatories: {
    applicant: officials.applicant, department_head: officials.department_head,
  } });
  const result = await signLocatorSourceSlot(db, user, 'dtr', 'locator_slips', id, 'hr_approver', { signature_asset_id: asset });
  assert.equal(db.state.row.final_reviewer_user_id, current);
  assert.equal(result.signatures[2].assigned_signer_id, current);
  const event = db.state.history.find(e => e.action === 'mayor_reassigned');
  assert.equal(event.metadata.previous_final_reviewer_user_id, null);
  assert.equal(event.metadata.previous_printed_approver, null);
});

test('a valid read never reassigns pending or approved Mayor snapshots', async () => {
  for (const status of ['pending_mayor', 'approved']) {
    const db = fixture({ status, hr_reviewer_id: former }, [signature(former)]);
    const result = await getLocatorSourceSignatures(db, { id: employee, role: 'employee' }, 'dtr', 'locator_slips', id);
    assert.equal(result.print_signatories.hr_approver.name, 'Former Mayor');
    assert.equal(result.print_signatories.hr_approver.signature_image_base64, status === 'approved' ? 'aW5r' : null);
    assert.equal(db.state.row.final_reviewer_user_id, former);
    assert.equal(db.state.history.length, 0);
    assert.equal(db.calls.some(c => c.sql.includes('UPDATE locator_slips')), false);
  }
});

test('approved forms cannot be reassigned or signed by the replacement Mayor', async () => {
  const db = fixture({ status: 'approved', hr_reviewer_id: former }, [signature(former)]);
  await assert.rejects(signLocatorSourceSlot(db, user, 'dtr', 'locator_slips', id, 'hr_approver', { signature_asset_id: asset }), { code: 'FORBIDDEN' });
  assert.equal(db.state.row.final_reviewer_user_id, former);
  assert.equal(db.state.row.print_signatories.hr_approver.id, former);
});

test('missing, foreign, or former-Mayor signatures cannot trigger a handover', async () => {
  for (const [actor, input, code] of [[user, null, 'CONFLICT'], [user, { signature_asset_id: foreignAsset }, 'FORBIDDEN'],
    [{ id: former, role: 'mayor' }, { signature_asset_id: asset }, 'NOT_FOUND']]) {
    const db = fixture({}, [signature(former)]);
    await assert.rejects(signLocatorSourceSlot(db, actor, 'dtr', 'locator_slips', id, 'hr_approver', input), { code });
    assert.equal(db.state.row.final_reviewer_user_id, former);
    assert.equal(db.state.row.print_signatories.hr_approver.id, former);
    assert.equal(db.state.history.length, 0);
  }
});

test('signature persistence failure rolls back both reassignment and its audit event', async () => {
  const db = fixture();
  db.failSignatureWrite = true;
  await assert.rejects(signLocatorSourceSlot(db, user, 'dtr', 'locator_slips', id, 'hr_approver', { signature_asset_id: asset }), /Simulated signature storage failure/);
  assert.equal(db.state.row.final_reviewer_user_id, former);
  assert.equal(db.state.row.print_signatories.hr_approver.id, former);
  assert.equal(db.state.history.length, 0);
  assert.ok(db.calls.some(c => c.sql === 'ROLLBACK'));
});

test('Mayor authority is rechecked while locking the signer before reassignment', async () => {
  const db = fixture();
  db.beforeAuthorityLock = () => { db.activeMayor = null; };
  await assert.rejects(signLocatorSourceSlot(db, user, 'dtr', 'locator_slips', id, 'hr_approver', { signature_asset_id: asset }), { code: 'FORBIDDEN' });
  assert.equal(db.state.row.print_signatories.hr_approver.id, former);
  assert.equal(db.state.history.length, 0);
});

test('direct-Mayor approval prints the replacement Mayor and their own ink', async () => {
  const db = fixture();
  const notifications = require('../src/services/locatorNotifications');
  const conflicts = require('../src/services/locatorConflictPolicy');
  const restores = [withMockedModule('../src/config/db', { pool: db }),
    withMockedModule('../src/services/locatorNotifications', { ...notifications, notifyEmployee: async () => {} }),
    withMockedModule('../src/services/locatorConflictPolicy', { ...conflicts, findLocatorRequestConflicts: async () => ({ ok: true }) })];
  clearModule('../src/routes/locatorSlips');
  try {
    const router = require('../src/routes/locatorSlips');
    const handler = router.stack.find(e => e.route?.path === '/:id/approve').route.stack.at(-1).handle;
    const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
    await handler({ params: { id }, user, body: { signature: { signature_asset_id: asset } } }, res);
    assert.equal(res.code, 200);
    assert.equal(res.body.status, 'approved');
    assert.equal(db.state.row.final_reviewer_user_id, current);
    const print = await getLocatorSourceSignatures(db, { id: employee, role: 'employee' }, 'dtr', 'locator_slips', id);
    assert.deepEqual(print.print_signatories.hr_approver, { name: 'Replacement Mayor', position_title: 'Municipal Mayor', signature_image_base64: 'aW5r' });
    assert.deepEqual(db.state.history.map(e => e.action), ['mayor_reassigned', 'signed', 'mayor_approved']);
  } finally {
    clearModule('../src/routes/locatorSlips');
    restores.reverse().forEach(restore => restore());
  }
});
