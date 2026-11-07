const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const policy = require('../src/services/rspPreDeliberationPolicy');

test('exam submission returns the saved Step 4 state for the current application', async (t) => {
  const applicationId = '11111111-1111-4111-8111-111111111111';
  const application = {
    id: applicationId,
    applicant_number: 'PLR-TEST2345',
    email: 'reused@example.com',
    status: 'document_approved',
    step4_gate_required: false,
  };
  let examResult;
  const restore = [
    withMockedModule('../src/config/db', { pool: {
      async query(sql, params) {
        const text = String(sql);
        if (text.includes('INSERT INTO public.recruitment_exam_results')) {
          examResult = {
            id: '22222222-2222-4222-8222-222222222222',
            application_id: params[0], score_percent: params[1],
            passed: params[2], answers_json: params[3],
          };
          return { rows: [], rowCount: 1 };
        }
        if (text.includes('SELECT step2_gate_required')) {
          return { rows: [{ step2_gate_required: false }], rowCount: 1 };
        }
        if (text.includes('FROM public.recruitment_exam_results')) {
          assert.equal(params[0], applicationId);
          return { rows: [examResult], rowCount: 1 };
        }
        if (text.includes('FROM public.recruitment_applications') && text.includes('WHERE id = $1')) {
          assert.equal(params[0], applicationId);
          return { rows: [{ ...application }], rowCount: 1 };
        }
        return { rows: [], rowCount: 0 };
      },
    } }),
    withMockedModule('../src/services/rspIssuedForm', {
      assertIssuedFormSchema: async () => {}, assessmentBlocked: () => false,
    }),
    withMockedModule('../src/services/rspFinalHiring', {
      assertFinalHiringSchema: async () => {},
    }),
    withMockedModule('../src/services/rspPreDeliberation', {
      assertPreDeliberationSchema: async () => {},
      recordAssessmentOutcome: async (id, status) => {
        assert.equal(id, applicationId);
        assert.ok(examResult, 'the exam is saved before the returned status is read');
        application.step4_gate_required = policy.shouldEnableStep4Gate(application, status);
        application.status = status;
      },
    }),
    withMockedModule('../src/utils/rspEmailVerifyToken', {
      signRspApplicantAccessToken: () => 'current-application-token',
    }),
  ];
  clearModule('../src/routes/rspApplications');
  t.after(() => {
    clearModule('../src/routes/rspApplications');
    restore.reverse().forEach(undo => undo());
  });
  const router = require('../src/routes/rspApplications');
  const route = router.stack.find(entry => entry.route?.path === '/exam-results' && entry.route.methods.post);
  const handler = route.route.stack.at(-1).handle;
  const res = {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
  await handler({ body: { applicationId, scorePercent: 92, passed: true, answersJson: {} } }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
  assert.equal(res.body.application.id, applicationId);
  assert.equal(res.body.application.status, 'passed');
  assert.equal(res.body.application.step4_gate_required, true);
  assert.equal(res.body.examResult.application_id, applicationId);
  assert.equal(res.body.examResult.passed, true);
  assert.equal(res.body.applicantAccessToken, 'current-application-token');
});
