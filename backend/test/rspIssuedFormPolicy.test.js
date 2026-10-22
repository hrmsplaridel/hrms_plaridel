const test = require('node:test');
const assert = require('node:assert/strict');
const policy = require('../src/services/rspIssuedFormPolicy');

test('legacy applications without the gate stay unlocked', () => {
  assert.equal(policy.assessmentBlocked({ step2_gate_required: false, required_form_status: null }), false);
  assert.equal(policy.assessmentBlocked({ step2_gate_required: false, required_form_status: 'assigned' }), false);
});

test('a new document approval stays locked until the assigned form is approved', () => {
  assert.equal(policy.shouldEnableIssuedFormGate('submitted'), true);
  assert.equal(policy.shouldEnableIssuedFormGate('document_declined'), true);
  assert.equal(policy.shouldEnableIssuedFormGate('document_approved'), false);
  assert.equal(policy.shouldEnableIssuedFormGate('exam_taken'), false);
  assert.equal(
    policy.assessmentBlocked({ step2_gate_required: true, required_form_status: 'waiting_for_hr_form' }),
    true,
  );
  assert.equal(
    policy.assessmentBlocked({ step2_gate_required: true, required_form_status: 'submitted_for_review' }),
    true,
  );
  assert.equal(
    policy.assessmentBlocked({ step2_gate_required: true, required_form_status: 'approved' }),
    false,
  );
});

test('revision resubmits into review and does not reject the application', () => {
  assert.equal(policy.statusAfterApplicantSubmit('in_progress'), 'submitted_for_review');
  assert.equal(policy.statusAfterApplicantSubmit('needs_revision'), 'resubmitted_for_review');
  assert.equal(policy.hrCanReview('resubmitted_for_review'), true);
  assert.equal(policy.canReassign('submitted_for_review'), false);
  assert.equal(policy.canUndoAssignment('assigned'), true);
  assert.equal(policy.canUndoAssignment('in_progress'), true);
  assert.equal(policy.canUndoAssignment('submitted_for_review'), false);
  assert.equal(policy.canUndoAssignment('approved'), false);
  assert.equal(policy.applicantCanEdit('needs_revision'), true);
});

test('OJT applicant submit requires school and evidence notes', () => {
  assert.deepEqual(
    policy.validateOjtApplicant({
      school: 'Plaridel National High School',
      problem_solving_notes: 'Solved the case',
      communication_notes: 'Clear answers',
      teamwork_notes: 'Worked with the group',
      adaptability_notes: 'Adjusted to the task',
    }),
    [],
  );
  assert.deepEqual(policy.validateOjtApplicant({}), [
    'school',
    'problem solving evidence',
    'communication evidence',
    'teamwork evidence',
    'adaptability evidence',
  ]);
});

test('only a Recommended OJT result counts as passed', () => {
  assert.equal(policy.ojtPassed({ overall_recommendation: 'Recommended' }), true);
  assert.equal(policy.ojtPassed({ overall_recommendation: 'Not Recommended' }), false);
  assert.equal(policy.ojtPassed({ overall_recommendation: 'For Further Review' }), false);
});

test('OJT approval waits for interviewer fields', () => {
  assert.equal(
    policy.ojtReadyForApproval({
      problem_solving_score: 4,
      communication_score: 4,
      teamwork_score: 4,
      adaptability_score: 4,
      overall_recommendation: 'Recommended',
      interviewer: 'HR Officer',
    }),
    true,
  );
  assert.equal(
    policy.ojtReadyForApproval({
      ojt_immersion: 'Juan',
      school: 'State University',
    }),
    false,
  );
});

test('BI submission requires the applicant pages', () => {
  const missing = policy.validateBiSubmission({
    applicant_name: 'Ana',
    respondent_name: '',
    functional_areas: [],
  });
  assert.ok(missing.includes('respondent name'));
  assert.ok(missing.includes('at least one functional area'));
});
