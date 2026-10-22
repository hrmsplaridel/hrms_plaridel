const test = require('node:test');
const assert = require('node:assert/strict');
const policy = require('../src/services/rspPreDeliberationPolicy');

const freshPass = {
  status: 'exam_taken',
  step4_gate_required: false,
  final_interview_at: null,
  final_interview_passed: null,
  hired_user_id: null,
};

test('the step 4 gate turns on only for a new pass with no deliberation history', () => {
  assert.equal(policy.shouldEnableStep4Gate(freshPass, 'passed'), true);
  assert.equal(policy.shouldEnableStep4Gate({ ...freshPass, status: 'passed' }, 'passed'), false);
  assert.equal(policy.shouldEnableStep4Gate({ ...freshPass, final_interview_at: '2026-01-01' }, 'passed'), false);
  assert.equal(policy.shouldEnableStep4Gate({ ...freshPass, final_interview_passed: true }, 'passed'), false);
  assert.equal(policy.shouldEnableStep4Gate({ ...freshPass, hired_user_id: 'user-1' }, 'passed'), false);
  assert.equal(policy.shouldEnableStep4Gate({ ...freshPass, step4_gate_required: true }, 'passed'), false);
  assert.equal(policy.shouldEnableStep4Gate(freshPass, 'failed'), false);
});

test('scheduling stays locked until all three prerequisites are complete', () => {
  const row = {
    step4_gate_required: true,
    wes_status: 'approved',
    applicants_profile_status: 'completed',
    selection_lineup_status: 'in_progress',
  };
  assert.deepEqual(policy.missingPrerequisites(row), ['Selection Line-Up not completed']);
  assert.equal(policy.deliberationBlocked(row), true);
  assert.deepEqual(policy.missingPrerequisites({
    ...row,
    selection_lineup_status: 'completed',
  }), []);
  assert.deepEqual(policy.missingPrerequisites({ step4_gate_required: false }), []);
});

test('shared HR forms link by application id and refuse an ambiguous name', () => {
  const ana = '9da0c4c5-37eb-4c1b-9b55-af79f1336b31';
  const ben = '8eae3aed-f4c7-431c-a582-9042be848ad7';
  const ids = policy.applicationIdsFromEntry({
    application_id: ana,
    applicants: [
      { name: 'Ana Cruz', application_id: ana },
      { name: 'Ben Santos', applicationId: ben },
      { name: 'Typed by hand' },
    ],
  });
  assert.deepEqual(ids, [ana, ben]);
  const gated = [
    { id: ana, full_name: 'Ana Cruz', position_applied_for: 'Clerk' },
    { id: '11111111-1111-4111-8111-111111111111', full_name: 'Ana Cruz', position_applied_for: 'Clerk' },
    { id: ben, full_name: 'Ben Santos', position_applied_for: 'Clerk' },
  ];
  assert.equal(policy.uniqueNamePositionMatches(gated, {
    name: 'Ana Cruz',
    position: 'Clerk',
  }).length, 2);
  assert.equal(policy.uniqueNamePositionMatches(gated, {
    name: 'Ben Santos',
    position: 'Clerk',
  }).length, 1);
  assert.equal(policy.rowsWithoutApplicationId([
    { name: 'Ana Cruz', application_id: ana },
    { name: 'Typed by hand' },
  ]).length, 1);
});

test('work experience revision keeps the same edit and review rules', () => {
  assert.equal(policy.applicantCanEditWes('needs_revision'), true);
  assert.equal(policy.applicantCanEditWes('submitted_for_review'), false);
  assert.equal(policy.statusAfterWesSubmit('needs_revision'), 'resubmitted_for_review');
  assert.equal(policy.statusAfterWesSubmit('assigned'), 'submitted_for_review');
  assert.equal(policy.hrCanReviewWes('resubmitted_for_review'), true);
  assert.equal(policy.validateWes({
    position_applied_for: 'Clerk',
    department: 'HR',
    min_education: 'College',
    min_experience: '1 year',
    min_training: 'None',
    min_eligibility: 'CS',
    job_description_last_work: 'Records',
    applicant_name: 'Ana',
  }).length, 0);
  assert.deepEqual(policy.validateWes({
    position_applied_for: 'Work Immersion',
    department: 'HR',
    min_education: 'Grade 12',
    min_experience: '2 yrs relevant experience',
    min_training: '72 units',
    job_description_last_work: 'the work i have been is i was fired',
    applicant_name: 'Code Crafters X',
  }), []);
});
