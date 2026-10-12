const test = require('node:test');
const assert = require('node:assert/strict');
const policy = require('../src/services/rspFinalHiringPolicy');

test('step 5 gate starts only on the first deliberation pass', () => {
  const fresh = {
    step5_gate_required: false,
    final_interview_passed: null,
    final_requirements_approved: false,
    status: 'passed',
  };
  assert.equal(policy.shouldEnableStep5Gate(fresh, true), true);
  assert.equal(policy.shouldEnableStep5Gate(fresh, false), false);
  assert.equal(
    policy.shouldEnableStep5Gate({ ...fresh, final_interview_passed: true }, true),
    false,
  );
  assert.equal(
    policy.shouldEnableStep5Gate(
      { ...fresh, doc_medical_certificate_path: 'uploads/medical.pdf' },
      true,
    ),
    false,
  );
  assert.equal(
    policy.shouldEnableStep5Gate({ ...fresh, status: 'registered', hired_user_id: 'user-1' }, true),
    false,
  );
});

test('final requirements stay locked until TAT and CSC are done', () => {
  assert.deepEqual(policy.missingFinalHiringPrerequisites({ step5_gate_required: false }), []);
  assert.deepEqual(
    policy.missingFinalHiringPrerequisites({
      step5_gate_required: true,
      tat_status: 'waiting',
      csc_approval_status: null,
    }),
    ['Turn-Around Time not completed', 'CSC approval not confirmed'],
  );
  assert.deepEqual(
    policy.missingFinalHiringPrerequisites({
      step5_gate_required: true,
      tat_status: 'completed',
      csc_approval_status: 'approved',
    }),
    [],
  );
});

test('turn-around time links by application id and skips an ambiguous name', () => {
  const rows = [
    { id: '9da0c4c5-37eb-4c1b-9b55-af79f1336b31', full_name: 'Ana Cruz', position_applied_for: 'IT Coder' },
    { id: '8eae3aed-f4c7-431c-a582-9042be848ad7', full_name: 'Ana Cruz', position_applied_for: 'IT Coder' },
  ];
  const ids = policy.applicationIdsFromEntry({
    applicants: [{ name: 'Ana Cruz', application_id: rows[0].id }],
  });
  assert.deepEqual(ids, [rows[0].id]);
  const ambiguous = policy.uniqueNamePositionMatches(rows, {
    name: 'Ana Cruz',
    position: 'IT Coder',
  });
  assert.equal(ambiguous.length, 2);
});
