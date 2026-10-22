'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const engine = require('../src/services/approvalWorkflows');
const id = n => `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
const applicant = id(1), head = id(2), hr = id(3), mayor = id(4);
const person = (id, name) => ({ id, employee_id: id, name, position_title: name });
const sources = ['submitter_department_reviewers', 'final_hr_reviewers', 'active_mayor'];
const policies = ['mayor', 'blank', 'actual_reviewer'];

test('workflow print policy defaults to Mayor and rejects unsupported choices', () => {
  assert.equal(engine.normalizeWorkflow({ name: 'Default', steps: ['hr'] }).self_filing_signatory_policy, 'mayor');
  for (const policy of policies) assert.equal(engine.normalizeWorkflow({ name: 'Valid', steps: ['hr'], self_filing_signatory_policy: policy }).self_filing_signatory_policy, policy);
  for (const policy of ['', null, 'backup', [], {}]) assert.throws(() => engine.normalizeWorkflow({ name: 'Invalid', steps: ['hr'], self_filing_signatory_policy: policy }), { statusCode: 400 });
});

for (const policy of policies) {
  test(`catalog and workflow creation/update persist versioned print policy: ${policy}`, async () => {
    const calls = [];
    const query = async (sql, params = []) => {
      calls.push({ sql, params });
      if (sql.startsWith('SELECT w.*')) return { rows: [{ id: id(10), self_filing_signatory_policy: policy }] };
      if (sql.startsWith('SELECT * FROM approval_workflows')) return { rows: [{ id: id(10), current_version: 1 }] };
      if (/^(INSERT INTO|UPDATE) approval_workflows/.test(sql)) return { rows: [{ id: id(10), current_version: 2 }] };
      return { rows: [] };
    };
    const restores = [withMockedModule('../src/config/db', { pool: { query, connect: async () => ({ query, release() {} }) } }),
      withMockedModule('../src/services/sharedDocumentWorkflows', { syncLinkedDocumentWorkflows: async () => {} })];
    clearModule('../src/routes/approvalWorkflows');
    try {
      const router = require('../src/routes/approvalWorkflows');
      const response = () => ({ code: 200, status(c) { this.code = c; return this; }, json(data) { this.data = data; } });
      const catalog = response();
      await router.stack.find(s => s.route?.path === '/' && s.route.methods.get).route.stack.at(-1).handle({}, catalog);
      assert.match(calls.at(-1).sql, /v\.self_filing_signatory_policy/);
      assert.equal(catalog.data[0].self_filing_signatory_policy, policy);
      for (const edit of [false, true]) {
        const res = response();
        await router.stack.find(s => s.route?.path === (edit ? '/:id' : '/') && s.route.methods[edit ? 'put' : 'post']).route.stack.at(-1).handle({
          user: { id: applicant }, params: edit ? { id: id(10) } : {},
          body: { name: 'Policy', steps: ['department', 'hr'], current_version: 1, self_filing_signatory_policy: policy },
        }, res);
        assert.equal(res.code, edit ? 200 : 201);
        const insert = calls.filter(c => c.sql.startsWith('INSERT INTO approval_workflow_versions')).at(-1);
        assert.match(insert.sql, /self_filing_signatory_policy/);
        assert.equal(insert.params[5], policy);
        assert.equal(res.data.self_filing_signatory_policy, policy);
      }
    } finally { clearModule('../src/routes/approvalWorkflows'); restores.reverse().forEach(r => r()); }
  });
  for (const kind of ['leave', 'locator']) test(`${kind} captures ${policy} and preserves it on resubmission`, async () => {
    let reads = 0;
    const db = { query: async sql => { assert.match(sql, /v\.self_filing_signatory_policy/); reads++; return { rows: [{ id: id(10), version: 1, name: 'Policy', is_active: true, steps: ['department'], self_filing_signatory_policy: policy }] }; } };
    const rule = { approval_workflow_id: id(10) };
    const reviewers = { departmentHeadUserId: head, reviewerUserIds: [head] };
    const snapshot = await engine.prepareWorkflow(db, kind, rule, applicant, reviewers);
    assert.equal(snapshot.self_filing_signatory_policy, policy);
    snapshot.outcome = 'returned';
    const again = await engine.prepareWorkflow(db, kind, { ...rule, approval_workflow_snapshot: snapshot }, applicant, reviewers);
    assert.equal(reads, 1);
    assert.equal(again.self_filing_signatory_policy, policy);
    assert.equal(engine.workflowStatus(again), 'pending_department_head');
  });
}

for (const shared of [false, true]) for (const policy of ['blank', 'actual_reviewer']) for (const approved of [false, true]) {
  const steps = shared ? sources.map(assignee_source => ({ assignee_source })) : ['department', 'hr', 'mayor'];
  const snapshot = { steps, self_filing_signatory_policy: policy, current_step: approved ? 3 : 0, decisions: approved ? [
    { step: 0, actor_id: head, action: 'approve', reviewer: person(head, 'Acting Department') },
    { step: 1, actor_id: hr, action: 'approve', reviewer: person(hr, 'Acting HR') },
    { step: 2, actor_id: mayor, action: 'approve', reviewer: person(mayor, 'Mayor') },
  ] : [] };
  test(`leave ${policy}, shared=${shared}, approved=${approved}: own roles only use policy and final Mayor stays intact`, async () => {
    const row = { id: id(10), employee_id: applicant, status: approved ? 'approved' : 'pending_department_head',
      submitted_on: '2026-10-18', review_department_id: id(20), assigned_department_head_id: head,
      approving_authority_snapshot: person(mayor, 'Mayor'), workflow_snapshot: snapshot };
    const restore = withMockedModule('../src/services/sharedWorkflowInbox', { pendingReadAccess: async () => true, canRead: async () => true });
    try {
      const controller = require('../src/modules/leave/controllers/signatories.controller')({
        pool: { query: async () => ({ rows: [row] }) },
        ...require('../src/modules/leave/services/signatories')({}),
        resolveFinalLeaveReviewerConfiguration: async () => ({ primary: person(applicant, 'Applicant') }),
        resolveDepartmentReviewers: async () => ({ primary: { reviewerId: applicant } }),
        resolveActiveMayor: async () => person(mayor, 'Mayor'),
        findAssignmentProfileByUserIdAtDate: async () => ({ user_id: head, full_name: 'Acting Department' }),
        todayInHrmsTimezone: () => '2026-10-18',
        workflowEngine: { ...engine, printOfficials: async () => ({ department_head: person(head, 'Acting Department'), hr_approver: person(mayor, 'Mayor') }) },
      });
      const res = { code: 200, status(code) { this.code = code; return this; }, json(data) { this.data = data; } };
      await controller.getSignatories({ user: { id: applicant, role: 'admin' }, query: { employee_id: applicant, leave_request_id: row.id } }, res);
      assert.equal(res.code, 200);
      const actual = policy === 'actual_reviewer' && approved;
      assert.equal(res.data.recommendation_officer?.user_id ?? null, actual ? head : null);
      assert.equal(res.data.hr_certification_officer?.user_id ?? null, actual ? hr : null);
      assert.equal(res.data.approving_authority.user_id, mayor);
    } finally { restore(); }
  });
  test(`locator ${policy}, shared=${shared}, approved=${approved}: own official blocks never borrow applicant or Mayor ink`, async () => {
    const row = { id: id(10), employee_id: applicant, employee_name: 'Applicant', department_id: id(20),
      slip_date_text: '2026-10-18', signature_revision: 1, status: approved ? 'approved' : 'pending_hr',
      dept_head_reviewer_id: head, hr_reviewer_id: hr, final_review_route: 'hr',
      workflow_snapshot: { ...snapshot, steps: steps.slice(0, 2), current_step: approved ? 2 : 0, decisions: snapshot.decisions.filter(d => d.step < 2) },
      // Before a backup approves, the saved actual-reviewer fields are empty.
      print_signatories: { applicant: person(applicant, 'Applicant'),
        department_head: { id: null, name: '', position_title: '' }, hr_approver: { id: null, name: '', position_title: '' } } };
    const db = { query: async sql => {
      if (sql.includes('FROM locator_slips ls')) return { rows: [row] };
      if (sql.includes('FROM docutracker_locator_signatures')) return { rows: [] };
      throw Error('Unexpected query ' + sql);
    } };
    const restores = [
      withMockedModule('../src/services/departmentReviewerService', { resolveDepartmentReviewers: async () => ({ primary: { reviewerId: applicant } }) }),
      withMockedModule('../src/services/leaveFinalReviewerService', { resolveFinalLeaveReviewerConfiguration: async () => ({ primary: person(applicant, 'Applicant') }) }),
      withMockedModule('../src/services/sharedWorkflowInbox', { canRead: async () => true }),
      withMockedModule('../src/services/officialSignatoryService', { resolveActiveMayor: async () => person(mayor, 'Mayor') }),
      withMockedModule('../src/services/approvalWorkflows', { ...engine, printOfficials: async () => shared ? { department_head: person(head, 'Acting Department'), hr_approver: person(hr, 'Acting HR') } : null }),
    ];
    clearModule('../src/services/locatorSignatureService');
    try {
      const result = await require('../src/services/locatorSignatureService').getLocatorSourceSignatures(db, { id: applicant, role: 'admin' }, 'dtr', 'locator_slips', row.id);
      const actual = policy === 'actual_reviewer' && approved;
      assert.equal(result.print_signatories.department_head.name, actual ? 'Acting Department' : '');
      assert.equal(result.print_signatories.hr_approver.name, actual ? 'Acting HR' : '');
      assert.equal(result.print_signatories.applicant.name, 'Applicant');
      assert.equal(result.print_signatories.department_head.signature_image_base64, null);
      assert.equal(result.print_signatories.hr_approver.signature_image_base64, null);
    } finally { clearModule('../src/services/locatorSignatureService'); restores.reverse().forEach(r => r()); }
  });
}

test('fresh schema declares a constrained, versioned print policy', () => {
  const schema = fs.readFileSync(path.join(__dirname, '../scripts/init-schema.sql'), 'utf8');
  const table = schema.match(/CREATE TABLE IF NOT EXISTS approval_workflow_versions\s*\(([\s\S]*?)\n\);/)[1];
  assert.match(table, /self_filing_signatory_policy TEXT NOT NULL DEFAULT 'mayor'/);
  assert.match(table, /'mayor',\s*'blank',\s*'actual_reviewer'/);
});

test('actual-reviewer policy freezes legacy approving names and titles with the decision', async () => {
  let saved;
  const snapshot = { steps: ['department', 'hr'], self_filing_signatory_policy: 'actual_reviewer', current_step: 1,
    decisions: [{ step: 0, actor_id: head, action: 'approve' }] };
  const db = { query: async (sql, params) => {
    if (sql.includes('SELECT s.signature_asset_id')) return { rows: [{ signature_asset_id: id(99), revision: 1 }] };
    if (sql.includes('SELECT u.id AS employee_id')) return { rows: [person(head, 'Approved Name and Title')] };
    if (sql.startsWith('UPDATE leave_requests')) { saved = JSON.parse(params[1]); return { rows: [] }; }
    throw Error('Unexpected query ' + sql);
  } };
  await engine.saveWorkflow(db, 'leave', id(10), snapshot);
  assert.equal(saved.decisions[0].reviewer.name, 'Approved Name and Title');
  assert.equal(saved.decisions[0].reviewer.position_title, 'Approved Name and Title');
});

test('actual final HR signatory uses the last HR approval when a workflow has multiple HR steps', async () => {
  const row = { employee_id: applicant, workflow_snapshot: {
    self_filing_signatory_policy: 'actual_reviewer',
    steps: ['department', 'hr', 'hr', 'mayor'].map(kind => engine.legacyStep(kind, 0)),
    decisions: [
      { step: 1, action: 'approve', actor_id: head, reviewer: person(head, 'Initial HR') },
      { step: 2, action: 'approve', actor_id: hr, reviewer: person(hr, 'Final HR') },
    ],
  } };
  const official = await require('../src/services/workflowPrintPolicy').selfFilingOfficial({}, row, 'hr', person(mayor, 'Mayor'));
  assert.equal(official.id, hr);
  assert.equal(official.name, 'Final HR');
});
