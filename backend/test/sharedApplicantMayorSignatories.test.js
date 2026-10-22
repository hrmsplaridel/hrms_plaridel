'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const engine = require('../src/services/approvalWorkflows');
const createSignatories = require('../src/modules/leave/controllers/signatories.controller');
const { mapOfficialSignatoryProfile, mapSignatoryProfile } = require('../src/modules/leave/services/signatories')({});
const id = n => `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
const applicant = id(1), head = id(2), hr = id(3), mayor = id(4), department = id(5);
const profile = (person, name) => ({ id: person, employee_id: person, name, position_title: name });
const mayorProfile = profile(mayor, 'Saved Mayor');
const steps = [
  { label: 'Department', assignee_source: 'submitter_department_reviewers' },
  { label: 'HR', assignee_source: 'final_hr_reviewers' },
  { label: 'Mayor', assignee_source: 'active_mayor' },
];

for (const policy of ['mayor', 'actual_reviewer']) for (const applicantIsFinalHr of [false, true]) {
  test(`department-only Locator prints confirmed head ink and leaves final block empty: ${policy}, applicant HR=${applicantIsFinalHr}`, async () => {
    const signature = { revision: 1, signature_asset_id: id(30), signer_name_snapshot: 'Admin User' };
    const row = { id: id(10), employee_id: applicant, employee_name: 'Applicant',
      department_id: department, slip_date_text: '2026-10-22', status: 'approved', signature_revision: 1,
      print_signatories: { applicant: profile(applicant, 'Applicant'), department_head: profile(head, 'Old Head'), hr_approver: profile(head, 'Old Final') },
      workflow_snapshot: { steps: steps.slice(0, 1), current_step: 1, self_filing_signatory_policy: policy,
        decisions: [{ step: 0, action: 'approve', actor_id: head, reviewer: profile(head, 'Admin User'), signature }] },
    };
    const calls = [];
    const db = { query: async sql => {
      calls.push(sql);
      if (sql.includes('FROM locator_slips ls')) return { rows: [row] };
      if (sql.includes('FROM docutracker_locator_signatures')) return { rows: [] };
      if (sql.includes('FROM docutracker_signature_assets')) return { rows: [{ id: id(30), owner_user_id: head, signature_image_base64: 'saved-head-ink' }] };
      throw Error('Unexpected query ' + sql);
    } };
    const restores = [
      withMockedModule('../src/services/departmentReviewerService', { resolveDepartmentReviewers: async () => ({ primary: { reviewerId: head } }) }),
      withMockedModule('../src/services/leaveFinalReviewerService', { resolveFinalLeaveReviewerConfiguration: async () => ({ primary: profile(applicantIsFinalHr ? applicant : hr, 'Primary HR') }) }),
      withMockedModule('../src/services/officialSignatoryService', { resolveActiveMayor: async () => mayorProfile }),
      withMockedModule('../src/services/sharedWorkflowInbox', { canRead: async () => true }),
    ];
    const module = '../src/services/locatorSignatureService'; clearModule(module);
    try {
      const result = await require(module).getLocatorSourceSignatures(db, { id: applicant, role: 'employee' }, 'dtr', 'locator_slips', row.id);
      assert.equal(result.print_signatories.department_head.name, 'Admin User');
      assert.equal(result.print_signatories.department_head.signature_image_base64, 'saved-head-ink');
      assert.equal(result.print_signatories.hr_approver.name, '');
      assert.equal(result.print_signatories.hr_approver.signature_image_base64, null);
      assert.equal(calls.some(sql => /^(UPDATE|INSERT|DELETE)/.test(sql)), false);
    } finally { clearModule(module); restores.reverse().forEach(restore => restore()); }
  });
}

for (const role of ['department', 'hr', 'both', 'neither']) {
  test(`shared leave replaces only the applicant's primary ${role} roles, preserving the approved Mayor`, async () => {
    const row = { id: id(10), employee_id: applicant, status: 'approved', submitted_on: '2026-10-01',
      approved_on: '2026-10-18', review_department_id: department, assigned_department_head_id: head,
      approving_authority_snapshot: mayorProfile, workflow_snapshot: { steps, current_step: 3, decisions: [] } };
    const restores = [withMockedModule('../src/services/sharedWorkflowInbox', {
      pendingReadAccess: async () => true, canRead: async () => true,
    })];
    try {
      const controller = createSignatories({
        pool: { query: async () => ({ rows: [row] }) },
        resolveFinalLeaveReviewerConfiguration: async () => ({ primary: profile(['hr', 'both'].includes(role) ? applicant : hr, 'Primary HR') }),
        resolveDepartmentReviewers: async () => ({ primary: { reviewerId: ['department', 'both'].includes(role) ? applicant : head } }),
        resolveActiveMayor: async () => profile(id(6), 'New Mayor'),
        findAssignmentProfileByUserIdAtDate: async () => profile(head, 'Backup Head'),
        todayInHrmsTimezone: () => '2026-10-18', mapOfficialSignatoryProfile, mapSignatoryProfile,
        workflowEngine: { ...engine, printOfficials: async () => ({ department_head: profile(head, 'Backup Head'), hr_approver: mayorProfile }) },
      });
      const res = { code: 200, status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
      await controller.getSignatories({ user: { id: applicant, role: 'admin' }, query: { employee_id: applicant, leave_request_id: row.id } }, res);
      assert.equal(res.code, 200);
      assert.equal(res.body.hr_certification_officer.user_id, ['hr', 'both'].includes(role) ? mayor : hr);
      assert.equal(res.body.recommendation_officer.user_id, ['department', 'both'].includes(role) ? mayor : head);
      assert.equal(res.body.approving_authority.user_id, mayor);
      if (role === 'both') assert.equal(res.body.recommendation_officer.name, 'Saved Mayor');
    } finally { restores.reverse().forEach(restore => restore()); }
  });
}

test('new shared locator snapshots both Mayor replacements before any approval', async () => {
  const row = { id: id(10), employee_id: applicant, employee_name: 'Applicant', department_id: department,
    slip_date_text: '2026-10-18', status: 'pending_hr', final_review_route: 'hr',
    workflow_snapshot: { steps: steps.slice(0, 2), current_step: 0, decisions: [] } };
  let stored;
  const db = { async query(sql, params) {
    if (sql.includes('FROM locator_slips ls')) return { rows: [row] };
    if (sql.includes('FROM assignments a JOIN positions p')) return { rows: [{ position_title: 'Employee Position' }] };
    if (sql.includes('SET print_signatories')) { stored = JSON.parse(params[1]); return { rows: [] }; }
    throw Error('Unexpected query ' + sql);
  } };
  const restores = [
    withMockedModule('../src/services/departmentReviewerService', {
      resolveDepartmentReviewers: async () => ({ primary: { reviewerId: applicant, reviewerName: 'Applicant' } }),
      replaceRequestReviewerSnapshot: async () => {},
    }),
    withMockedModule('../src/services/leaveFinalReviewerService', {
      resolveFinalLeaveReviewerConfiguration: async () => ({ primary: profile(applicant, 'Applicant') }),
    }),
    withMockedModule('../src/services/officialSignatoryService', { resolveActiveMayor: async () => mayorProfile }),
    withMockedModule('../src/services/approvalWorkflows', { ...engine, printOfficials: async () => ({
      department_head: profile(head, 'Backup Head'), hr_approver: profile(hr, 'Backup HR'),
    }) }),
  ];
  const path = '../src/services/locatorSignatureService'; clearModule(path);
  try {
    await require(path).snapshotLocatorReviewers(db, { requestType: 'locator', requestId: row.id, departmentId: department, reviewers: [] });
    assert.equal(stored.applicant.id, applicant);
    assert.equal(stored.department_head.id, mayor);
    assert.equal(stored.hr_approver.id, mayor);
  } finally { clearModule(path); restores.reverse().forEach(restore => restore()); }
});

for (const role of ['department', 'hr', 'both', 'neither']) {
  for (const route of ['mayor', 'manual', 'hr', 'custom']) {
   for (const status of ['approved', ['hr', 'custom'].includes(route) ? 'pending_hr' : 'pending_mayor']) {
    test(`shared locator ${route}/${status}: applicant primary ${role} prints Mayor with only confirmed matching ink`, async () => {
      const ownsHead = ['department', 'both'].includes(role);
      const ownsHr = ['hr', 'both'].includes(role);
      const hrRoute = ['hr', 'custom'].includes(route);
      const routeSteps = route === 'custom' ? steps.slice(0, 2).map(step => ({ ...step, assignee_source: 'specific_users' })) : route === 'hr' ? steps.slice(0, 2) : route === 'manual'
        ? [...steps.slice(0, 2), { label: 'Manual Mayor', assignee_source: 'manual_mayor' }] : steps;
      const printedMayor = hrRoute ? profile(id(6), 'New Mayor') : mayorProfile;
      const snapshot = { steps: routeSteps, current_step: status === 'approved' ? routeSteps.length : routeSteps.length - 1, decisions: [
        { step: 0, action: 'approve', actor_id: head, reviewer: profile(head, 'Acting Head'), signature: { revision: 2, signature_asset_id: id(20) } },
        { step: 1, action: 'approve', actor_id: hr, reviewer: profile(hr, 'Acting HR'), signature: { revision: 2, signature_asset_id: id(21) } },
        ...(status === 'approved' && route === 'mayor' ? [{ step: 2, action: 'approve', actor_id: mayor, reviewer: mayorProfile, signature: { revision: 2, signature_asset_id: id(22) } }] : []),
      ] };
      const row = { id: id(10), employee_id: applicant, employee_name: 'Applicant', department_id: department,
        status, slip_date_text: '2026-10-18', signature_revision: 2, hr_reviewer_id: status === 'approved' ? mayor : hr,
        dept_head_reviewer_id: head, final_review_route: hrRoute ? 'hr' : route === 'manual' ? 'mayor' : 'mayor_direct', workflow_snapshot: snapshot,
        print_signatories: { applicant: profile(applicant, 'Applicant'), department_head: profile(head, 'Acting Head'), hr_approver: mayorProfile } };
      const calls = [];
      const db = { async query(sql, params) {
        calls.push(sql);
        if (sql.includes('FROM locator_slips ls')) return { rows: [row] };
        if (sql.includes('FROM docutracker_locator_signatures s')) return { rows: status === 'approved' ? [{ slot_key: 'hr_approver', signed_by: mayor, revision: 2, signature_image_base64: 'mayor-ink' }] : [] };
        if (sql.includes('FROM docutracker_signature_assets')) return { rows: [
          { id: id(20), owner_user_id: head, signature_image_base64: 'head-ink' },
          { id: id(21), owner_user_id: hr, signature_image_base64: 'hr-ink' },
          { id: id(22), owner_user_id: mayor, signature_image_base64: 'mayor-ink' },
        ] };
        throw Error('Unexpected query ' + sql);
      } };
      const restores = [
        withMockedModule('../src/services/departmentReviewerService', { resolveDepartmentReviewers: async () => ({ primary: { reviewerId: ownsHead ? applicant : head } }) }),
        withMockedModule('../src/services/leaveFinalReviewerService', {
          resolveFinalLeaveReviewerConfiguration: async () => ({ primary: profile(ownsHr ? applicant : hr, 'Primary HR') }),
          resolveEligibleFinalReviewers: async () => [],
        }),
        withMockedModule('../src/services/officialSignatoryService', { resolveActiveMayor: async () => profile(id(6), 'New Mayor') }),
        withMockedModule('../src/services/sharedWorkflowInbox', { canRead: async () => true }),
        withMockedModule('../src/services/approvalWorkflows', { ...engine, printOfficials: async () => ({
          department_head: profile(head, 'Acting Head'), hr_approver: hrRoute ? profile(hr, 'Acting HR') : mayorProfile,
        }) }),
      ];
      const path = '../src/services/locatorSignatureService'; clearModule(path);
      try {
        const result = await require(path).getLocatorSourceSignatures(db, { id: applicant, role: 'admin' }, 'dtr', 'locator_slips', row.id);
        assert.equal(result.print_signatories.applicant.name, 'Applicant');
        assert.equal(result.print_signatories.department_head.name, ownsHead ? printedMayor.name : 'Acting Head');
        assert.equal(result.print_signatories.department_head.signature_image_base64, ownsHead ? status === 'approved' && route === 'mayor' ? 'mayor-ink' : null : 'head-ink');
        assert.equal(result.print_signatories.hr_approver.name, hrRoute ? ownsHr ? 'New Mayor' : 'Acting HR' : 'Saved Mayor');
        assert.equal(result.print_signatories.hr_approver.signature_image_base64, status !== 'approved' || route === 'manual' ? null : route === 'mayor' ? 'mayor-ink' : ownsHr ? null : 'hr-ink');
        assert.equal(calls.some(sql => /^(UPDATE|INSERT|DELETE)/.test(sql)), false, 'Preview must not rewrite requests or decisions');
      } finally { clearModule(path); restores.reverse().forEach(restore => restore()); }
    });
   }
  }
}
