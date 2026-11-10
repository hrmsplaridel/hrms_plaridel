'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const engine = require('../src/services/approvalWorkflows');
const inbox = require('../src/services/sharedWorkflowInbox');
const {listDocuments} = require('../src/services/docutrackerWorkflowService');
const {getLocatorSourceWorkflow} = require('../src/services/docutrackerLocatorSourceWorkflowService');
const {getLocatorSourceSignatures} = require('../src/services/locatorSignatureService');

const id = n => `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
const owner = id(1), former = id(2), viewer = id(3), request = id(4), asset = id(5);

function row(status = 'approved') {
  const completed = status === 'approved';
  return {
    id: request, employee_id: owner, user_id: owner, employee_name: 'Applicant',
    status, slip_date_text: '2026-11-06', signature_revision: 1,
    final_review_route: 'hr', request_type_label_snapshot: 'Sample',
    hr_reviewer_id: former, is_reviewer: false,
    created_at: '2026-11-06T01:00:00Z', updated_at: '2026-11-06T02:00:00Z',
    print_signatories: {applicant: {id: owner, name: 'Applicant', position_title: ''}},
    workflow_snapshot: {name: 'Saved workflow', version: 1,
      steps: [{step_order: 1, label: 'Sample', assignee_source: 'specific_users', user_ids: [former]}],
      current_step: completed ? 1 : 0, outcome: completed ? 'approved' : null,
      decisions: completed ? [{step: 0, actor_id: former, action: 'approve',
        reviewer: {name: 'Original Approver', position_title: 'Former HR Officer'},
        signature: {revision: 1, signature_asset_id: asset, signer_name_snapshot: 'Original Approver'},
      }] : [],
    },
  };
}

for (const kind of ['leave', 'locator']) {
  test(`${kind}: completed workflow access does not resolve inactive current reviewers`, async () => {
    const db = {query: async () => { throw Error('Historical reads must not resolve live reviewers'); }};
    const saved = row();
    assert.equal(await inbox.canRead(db, kind, saved, {id: viewer, role: 'employee'}), false);
    assert.equal(await inbox.canRead(db, kind, saved, {id: former, role: 'employee'}), true);
    assert.equal(await inbox.canRead(db, kind, saved, {id: owner, role: 'employee'}), true);
  });

  test(`${kind}: unassigned pending workflow denies access without leaking a configuration error`, async () => {
    const db = {query: async () => ({rows: [], rowCount: 0})};
    assert.equal(await inbox.canRead(db, kind, row('pending_hr'), {id: viewer, role: 'admin'}), false);
    assert.equal(await inbox.pendingReadAccess(db, kind, row('pending_hr'), {id: viewer, role: 'admin'}), false);
  });

  test(`${kind}: unrelated storage failures still propagate`, async () => {
    const failure = Object.assign(Error('Database unavailable'), {code: '08006'});
    const db = {query: async () => {throw failure;}};
    await assert.rejects(inbox.canRead(db, kind, row('pending_hr'), {id: viewer}), error => error === failure);
  });

  test(`${kind}: recorded readers cannot approve in place of an inactive current reviewer`, async () => {
    const saved = row('pending_hr');
    saved.workflow_snapshot.steps.unshift({step_order: 1, label: 'Previous review', assignee_source: 'specific_users', user_ids: [viewer]});
    saved.workflow_snapshot.steps[1].step_order = 2;
    saved.workflow_snapshot.current_step = 1;
    saved.workflow_snapshot.decisions = [{step: 0, actor_id: viewer, action: 'approve'}];
    const db = {query: async sql => sql.startsWith('SELECT * FROM')
      ? {rows: [saved], rowCount: 1} : {rows: [], rowCount: 0}};
    assert.equal(await inbox.getRequest(db, kind, request, {id: viewer}), saved);
    await assert.rejects(inbox.getRequest(db, kind, request, {id: viewer}, {decision: true}),
      error => error.statusCode === 409 && error.message.includes('No active assignee'));
  });
}

test('one unassigned workflow does not break another reviewers approval queue', async () => {
  const broken = row('pending_hr');
  const assigned = {...row('pending_hr'), id: id(8)};
  assigned.workflow_snapshot.steps[0].user_ids = [viewer];
  const db = {query: async (sql, params = []) => {
    if (sql.includes('FROM locator_slips r JOIN users')) return {rows: [broken, assigned]};
    if (sql.includes('FROM users') && (params[0] === viewer || Array.isArray(params[0]) && params[0].includes(viewer))) {
      return {rows: [{id: viewer, name: 'Current Reviewer'}], rowCount: 1};
    }
    return {rows: [], rowCount: 0};
  }};
  const result = await inbox.listInbox(db, {id: viewer, role: 'employee'}, {kind: 'locator'});
  assert.deepEqual(result.map(item => item.id), [assigned.id]);
});

test('DocuTracker list survives completed and pending Locator workflows whose reviewer is inactive', async () => {
  const broken = row('pending_hr');
  const completed = row();
  const own = {...row(), id: id(6), employee_id: viewer, employee_name: 'Current Employee'};
  const db = {query: async sql => {
    if (sql.includes('FROM docutracker_permissions')) {
      return {rows: [{user_id: viewer, document_type: 'dtr', granted: true}]};
    }
    if (sql.includes('FROM locator_slips ls JOIN users')) return {rows: [completed, broken, own]};
    return {rows: [], rowCount: 0};
  }};
  const result = await listDocuments(db, {id: viewer, role: 'employee'}, {type: 'dtr'});
  assert.deepEqual(result.documents.map(document => document.source_record_id), [own.id]);
});

test('new admin can preview approved Locator with the original inactive approver and saved signature', async () => {
  const saved = row();
  const before = JSON.stringify(saved.workflow_snapshot);
  let reads = 0;
  const db = {query: async sql => {
    if (sql.includes('FROM locator_slips ls')) return {rows: [saved], rowCount: 1};
    if (sql.includes('FROM docutracker_locator_signatures')) return {rows: []};
    if (sql.includes('FROM docutracker_signature_assets')) {
      reads++;
      return {rows: [{id: asset, owner_user_id: former, mime_type: 'image/png', signature_image_base64: 'aW5r'}]};
    }
    throw Error(`Unexpected live reviewer query: ${sql}`);
  }};
  const result = await getLocatorSourceSignatures(db, {id: viewer, role: 'admin'}, 'dtr', 'locator_slips', request);
  assert.equal(result.print_signatories.hr_approver.name, 'Original Approver');
  assert.equal(result.print_signatories.hr_approver.position_title, 'Former HR Officer');
  assert.equal(result.print_signatories.hr_approver.signature_image_base64, 'aW5r');
  assert.equal(reads, 1);
  assert.equal(JSON.stringify(saved.workflow_snapshot), before, 'Read must not replace historical approval');
});

test('a recorded participant can read a pending Locator without becoming its replacement reviewer', async () => {
  const saved = row('pending_hr');
  saved.workflow_snapshot.steps.unshift({step_order: 1, label: 'Previous review', assignee_source: 'specific_users', user_ids: [viewer]});
  saved.workflow_snapshot.steps[1].step_order = 2;
  saved.workflow_snapshot.current_step = 1;
  saved.workflow_snapshot.decisions = [{step: 0, actor_id: viewer, action: 'approve'}];
  const db = {query: async sql => ({rows: sql.includes('FROM locator_slips ls JOIN users') ? [saved] : [], rowCount: 0})};
  const result = await getLocatorSourceWorkflow(db, {id: viewer, role: 'employee'}, request, {
    mayorRead: async () => false, history: async () => [],
  });
  assert.ok(result);
  assert.deepEqual(result.steps[1].reviewers, []);
  assert.equal(result.steps[1].indicator.kind, 'current');
});

test('approved workflow participants retain DocuTracker history without live reviewer lookup', async () => {
  const saved = row();
  const db = {query: async sql => {
    if (sql.includes('FROM docutracker_permissions')) return {rows: [{user_id: former, document_type: 'dtr', granted: true}]};
    if (sql.includes('FROM locator_slips ls JOIN users')) return {rows: [saved]};
    return {rows: [], rowCount: 0};
  }};
  const result = await listDocuments(db, {id: former, role: 'employee'}, {type: 'dtr'});
  assert.deepEqual(result.documents.map(document => document.source_record_id), [request]);
});
