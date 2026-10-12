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
  assert.equal(policy.applicantCanEdit('needs_revision'), true);
});

test('OJT applicant submit only requires immersion and school', () => {
  assert.deepEqual(
    policy.validateOjtApplicant({
      ojt_immersion: 'Juan Dela Cruz',
      school: 'Plaridel National High School',
      interview_date: null,
      problem_solving_score: null,
      overall_recommendation: null,
      interviewer: null,
    }),
    [],
  );
  assert.deepEqual(policy.validateOjtApplicant({}), ['OJT / immersion', 'school']);
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
