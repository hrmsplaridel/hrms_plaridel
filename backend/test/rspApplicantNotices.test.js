const test = require('node:test');
const assert = require('node:assert/strict');
const emailjs = require('@emailjs/nodejs');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

require('../src/utils/emailJsMail');

const APPLICATION_ID = '9da0c4c5-37eb-4c1b-9b55-af79f1336b31';
const APPLICANT = {
  email: 'applicant@example.com',
  full_name: 'Ana Cruz',
  applicant_number: 'PLR-ABC12345',
  position_applied_for: 'Administrative Aide',
};

const ENV_KEYS = [
  'EMAILJS_SERVICE_ID',
  'EMAILJS_PUBLIC_KEY',
  'EMAILJS_PRIVATE_KEY',
  'EMAILJS_TEMPLATE_HIRE_CREDENTIALS_ID',
  'EMAILJS_TEMPLATE_RSP_DOCUMENT_DECISION_ID',
  'EMAILJS_TEMPLATE_RSP_SCHEDULE_NOTICE_ID',
  'EMAILJS_TEMPLATE_RSP_ACTION_REQUIRED_ID',
  'EMAILJS_TEMPLATE_RSP_FINAL_REQUIREMENT_RETURNED_ID',
  'HRMS_TIMEZONE',
];

function mockEmailSend(impl) {
  const original = emailjs.send;
  Object.defineProperty(emailjs, 'send', {
    configurable: true,
    writable: true,
    value: impl,
  });
  return () => {
    Object.defineProperty(emailjs, 'send', {
      configurable: true,
      enumerable: true,
      writable: true,
      value: original,
    });
  };
}

function useTestEmailEnv() {
  const saved = {};
  for (const key of ENV_KEYS) saved[key] = process.env[key];
  process.env.EMAILJS_SERVICE_ID = 'service_testnotice';
  process.env.EMAILJS_PUBLIC_KEY = 'public_testnotice';
  process.env.EMAILJS_PRIVATE_KEY = 'private_testnotice';
  process.env.EMAILJS_TEMPLATE_HIRE_CREDENTIALS_ID = 'template_hire_credentials';
  process.env.EMAILJS_TEMPLATE_RSP_DOCUMENT_DECISION_ID = 'template_document_decision';
  process.env.EMAILJS_TEMPLATE_RSP_SCHEDULE_NOTICE_ID = 'template_schedule_notice';
  process.env.EMAILJS_TEMPLATE_RSP_ACTION_REQUIRED_ID = 'template_action_required';
  process.env.EMAILJS_TEMPLATE_RSP_FINAL_REQUIREMENT_RETURNED_ID = 'template_final_requirement';
  process.env.HRMS_TIMEZONE = 'Asia/Manila';
  return () => {
    for (const key of ENV_KEYS) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  };
}

function paramsOf(call) {
  return call[2];
}

function response() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

function lastHandler(router, method, path) {
  const layer = router.stack.find(
    (entry) => entry.route?.path === path && entry.route.methods?.[method],
  );
  assert.ok(layer, `${method.toUpperCase()} ${path} not found`);
  return layer.route.stack[layer.route.stack.length - 1].handle;
}

test('document decision email uses the approved template and skips unchanged statuses', async () => {
  const restoreEnv = useTestEmailEnv();
  const calls = [];
  const restoreSend = mockEmailSend(async (...args) => {
    calls.push(args);
    return { status: 200, text: 'OK' };
  });
  const notices = require('../src/services/rspApplicantNotices');
  notices.resetApplicantNoticeDedupe();

  const approved = await notices.notifyDocumentDecision({
    applicationId: APPLICATION_ID,
    previousStatus: 'submitted',
    nextStatus: 'document_approved',
    applicant: APPLICANT,
  });
  assert.equal(approved.sent, true);
  assert.equal(calls[0][1], 'template_document_decision');
  assert.equal(paramsOf(calls[0]).to_email, 'applicant@example.com');
  assert.equal(paramsOf(calls[0]).applicant_name, 'Ana Cruz');
  assert.equal(paramsOf(calls[0]).application_number, 'PLR-ABC12345');
  assert.equal(paramsOf(calls[0]).position, 'Administrative Aide');
  assert.equal(paramsOf(calls[0]).decision, 'Approved');
  assert.match(paramsOf(calls[0]).next_step, /assign your next form/);
  assert.equal(paramsOf(calls[0]).password, undefined);
  assert.equal(paramsOf(calls[0]).otp_code, undefined);

  notices.resetApplicantNoticeDedupe();
  const same = await notices.notifyDocumentDecision({
    applicationId: APPLICATION_ID,
    previousStatus: 'document_approved',
    nextStatus: 'document_approved',
    applicant: APPLICANT,
  });
  assert.equal(same.sent, false);
  assert.equal(same.reason, 'unchanged');

  const other = await notices.notifyDocumentDecision({
    applicationId: APPLICATION_ID,
    previousStatus: 'exam_taken',
    nextStatus: 'passed',
    applicant: APPLICANT,
  });
  assert.equal(other.reason, 'unchanged');
  assert.equal(calls.length, 1);

  notices.resetApplicantNoticeDedupe();
  const declined = await notices.notifyDocumentDecision({
    applicationId: APPLICATION_ID,
    previousStatus: 'submitted',
    nextStatus: 'document_declined',
    applicant: APPLICANT,
  });
  assert.equal(declined.sent, true);
  assert.equal(paramsOf(calls[1]).decision, 'Declined');
  assert.match(paramsOf(calls[1]).next_step, /resubmit/);

  notices.resetApplicantNoticeDedupe();
  const invalid = await notices.notifyDocumentDecision({
    applicationId: APPLICATION_ID,
    previousStatus: 'submitted',
    nextStatus: 'document_approved',
    applicant: { ...APPLICANT, email: 'not-an-email' },
  });
  assert.equal(invalid.reason, 'invalid_recipient');
  assert.equal(calls.length, 2);
  restoreSend();
  restoreEnv();
});

test('schedule notice emails deliberation and orientation only when the time changes', async () => {
  const restoreEnv = useTestEmailEnv();
  const calls = [];
  const restoreSend = mockEmailSend(async (...args) => {
    calls.push(args);
    return { status: 200, text: 'OK' };
  });
  const notices = require('../src/services/rspApplicantNotices');
  notices.resetApplicantNoticeDedupe();
  const first = '2026-10-11T07:00:00.000Z';
  const second = '2026-10-12T01:30:00.000Z';

  const scheduled = await notices.notifyScheduleNotice({
    applicationId: APPLICATION_ID,
    eventName: 'Deliberation',
    previousAt: null,
    nextAt: first,
    applicant: APPLICANT,
  });
  assert.equal(scheduled.sent, true);
  assert.equal(calls[0][1], 'template_schedule_notice');
  assert.equal(paramsOf(calls[0]).event_name, 'Deliberation');
  assert.match(paramsOf(calls[0]).schedule_at, /October 11, 2026/);
  assert.match(paramsOf(calls[0]).schedule_at, /3:00 PM/);
  assert.match(paramsOf(calls[0]).instructions, /deliberation/i);

  const unchanged = await notices.notifyScheduleNotice({
    applicationId: APPLICATION_ID,
    eventName: 'Deliberation',
    previousAt: first,
    nextAt: first,
    applicant: APPLICANT,
  });
  assert.equal(unchanged.reason, 'unchanged');

  const cleared = await notices.notifyScheduleNotice({
    applicationId: APPLICATION_ID,
    eventName: 'Deliberation',
    previousAt: first,
    nextAt: null,
    applicant: APPLICANT,
  });
  assert.equal(cleared.reason, 'unchanged');

  const rescheduled = await notices.notifyScheduleNotice({
    applicationId: APPLICATION_ID,
    eventName: 'Deliberation',
    previousAt: first,
    nextAt: second,
    applicant: APPLICANT,
  });
  assert.equal(rescheduled.sent, true);
  assert.match(paramsOf(calls[1]).schedule_at, /October 12, 2026/);
  assert.match(paramsOf(calls[1]).schedule_at, /9:30 AM/);

  const orientation = await notices.notifyScheduleNotice({
    applicationId: APPLICATION_ID,
    eventName: 'Orientation',
    previousAt: null,
    nextAt: first,
    applicant: APPLICANT,
  });
  assert.equal(orientation.sent, true);
  assert.equal(paramsOf(calls[2]).event_name, 'Orientation');
  assert.match(paramsOf(calls[2]).instructions, /orientation/i);
  assert.equal(calls.length, 3);
  restoreSend();
  restoreEnv();
});

test('action required covers BI, OJT, and Work Experience Sheet assignment and revision', async () => {
  const restoreEnv = useTestEmailEnv();
  const calls = [];
  const restoreSend = mockEmailSend(async (...args) => {
    calls.push(args);
    return { status: 200, text: 'OK' };
  });
  const notices = require('../src/services/rspApplicantNotices');
  notices.resetApplicantNoticeDedupe();

  for (const [formKey, title] of [
    ['bi', 'Background Investigation Form'],
    ['ojt', 'OJT / Work Immersion Evaluation'],
    ['wes', 'Work Experience Sheet'],
  ]) {
    const result = await notices.notifyActionRequired({
      applicationId: APPLICATION_ID,
      formKey,
      mode: 'assign',
      applicant: APPLICANT,
    });
    assert.equal(result.sent, true);
    const sent = paramsOf(calls.at(-1));
    assert.equal(calls.at(-1)[1], 'template_action_required');
    assert.equal(sent.action_title, title);
    assert.equal(sent.hr_comment, '');
    assert.match(sent.action_detail, /assigned this form/);
  }

  const revision = await notices.notifyActionRequired({
    applicationId: APPLICATION_ID,
    formKey: 'wes',
    mode: 'revision',
    comment: 'Add the last position.',
    applicant: APPLICANT,
  });
  assert.equal(revision.sent, true);
  assert.equal(paramsOf(calls.at(-1)).hr_comment, 'Add the last position.');
  assert.match(paramsOf(calls.at(-1)).action_detail, /returned this form for revision/);

  const profile = await notices.notifyActionRequired({
    applicationId: APPLICATION_ID,
    formKey: 'profile',
    mode: 'assign',
    applicant: APPLICANT,
  });
  assert.equal(profile.reason, 'unsupported_form');
  assert.equal(
    notices.revisionIsNew('needs_revision', 'Add the last position.', 'Add the last position.'),
    false,
  );
  assert.equal(
    notices.revisionIsNew('submitted_for_review', 'Add the last position.', 'Add the last position.'),
    true,
  );
  assert.equal(calls.length, 4);
  restoreSend();
  restoreEnv();
});

test('final requirement returned names the document and keeps the recorded reason', async () => {
  const restoreEnv = useTestEmailEnv();
  const calls = [];
  const restoreSend = mockEmailSend(async (...args) => {
    calls.push(args);
    return { status: 200, text: 'OK' };
  });
  const notices = require('../src/services/rspApplicantNotices');
  notices.resetApplicantNoticeDedupe();

  const kinds = [
    ['medical_certificate', 'Medical Certificate'],
    ['drug_test_result', 'Drug Test Result'],
    ['nbi_clearance', 'NBI Clearance'],
  ];
  for (const [documentKind, documentName] of kinds) {
    const result = await notices.notifyFinalRequirementReturned({
      applicationId: APPLICATION_ID,
      documentKind,
      reason: 'Unreadable scan',
      applicant: APPLICANT,
    });
    assert.equal(result.sent, true);
    assert.equal(calls.at(-1)[1], 'template_final_requirement');
    assert.equal(paramsOf(calls.at(-1)).document_name, documentName);
    assert.equal(paramsOf(calls.at(-1)).reason, 'Unreadable scan');
    assert.match(paramsOf(calls.at(-1)).instructions, /Upload a new file/);
  }
  assert.equal(calls.length, 3);
  restoreSend();
  restoreEnv();
});

test('email delivery failure does not throw and a later retry can send', async () => {
  const restoreEnv = useTestEmailEnv();
  let fail = true;
  const calls = [];
  const restoreSend = mockEmailSend(async (...args) => {
    calls.push(args);
    if (fail) throw new Error('EmailJS HTTP 500');
    return { status: 200, text: 'OK' };
  });
  const notices = require('../src/services/rspApplicantNotices');
  notices.resetApplicantNoticeDedupe();
  const failed = await notices.notifyDocumentDecision({
    applicationId: APPLICATION_ID,
    previousStatus: 'submitted',
    nextStatus: 'document_approved',
    applicant: APPLICANT,
  });
  assert.equal(failed.sent, false);
  assert.equal(failed.reason, 'delivery_failed');
  fail = false;
  const retried = await notices.notifyDocumentDecision({
    applicationId: APPLICATION_ID,
    previousStatus: 'submitted',
    nextStatus: 'document_approved',
    applicant: APPLICANT,
  });
  assert.equal(retried.sent, true);
  assert.equal(calls.length, 2);
  restoreSend();
  restoreEnv();
});

test('repeated document decision in the same window sends once', async () => {
  const restoreEnv = useTestEmailEnv();
  const calls = [];
  const restoreSend = mockEmailSend(async (...args) => {
    calls.push(args);
    return { status: 200, text: 'OK' };
  });
  const notices = require('../src/services/rspApplicantNotices');
  notices.resetApplicantNoticeDedupe();
  const input = {
    applicationId: APPLICATION_ID,
    previousStatus: 'submitted',
    nextStatus: 'document_approved',
    applicant: APPLICANT,
  };
  const [first, second] = await Promise.all([
    notices.notifyDocumentDecision(input),
    notices.notifyDocumentDecision(input),
  ]);
  assert.equal(first.sent, true);
  assert.equal(second.reason, 'duplicate');
  assert.equal(calls.length, 1);
  restoreSend();
  restoreEnv();
});

test('hire credentials email still uses its own template', async () => {
  const restoreEnv = useTestEmailEnv();
  const calls = [];
  const restoreSend = mockEmailSend(async (...args) => {
    calls.push(args);
    return { status: 200, text: 'OK' };
  });
  const { sendHireCredentialsEmailJs } = require('../src/utils/emailJsMail');
  await sendHireCredentialsEmailJs({
    to: 'applicant@example.com',
    applicantName: 'Ana Cruz',
    username: 'ana.cruz',
    password: 'temporary-pass',
    accountNote: 'Your account is ready.',
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0][1], 'template_hire_credentials');
  assert.equal(paramsOf(calls[0]).username, 'ana.cruz');
  assert.equal(paramsOf(calls[0]).password, 'temporary-pass');
  restoreSend();
  restoreEnv();
});

test('recruitment routes send after a real change and stay successful when email fails', async () => {
  const restoreEnv = useTestEmailEnv();
  let failSend = false;
  const calls = [];
  const restoreSend = mockEmailSend(async (...args) => {
    calls.push(args);
    if (failSend) {
      const err = new Error('EmailJS HTTP 503');
      err.status = 503;
      throw err;
    }
    return { status: 200, text: 'OK' };
  });

  const state = {
    status: 'submitted',
    finalInterviewAt: null,
    orientationAt: null,
    filePath: 'rsp/medical.pdf',
  };
  const assignState = { applicantNotice: true, formType: 'bi' };
  const revisionState = { applicantNotice: true, comment: 'Fix the school name.' };
  const wesState = { applicantNotice: false };

  const pool = {
    async connect() {
      return { query: (...args) => pool.query(...args), release() {} };
    },
    async query(sql, params) {
      const text = String(sql);
      if (text.includes('FOR UPDATE') && text.includes('final_interview_at')) {
        return {
          rowCount: 1,
          rows: [{ ...APPLICANT, final_interview_at: state.finalInterviewAt }],
        };
      }
      if (text.includes('FOR UPDATE') && text.includes('orientation_at')) {
        return {
          rowCount: 1,
          rows: [{
            ...APPLICANT,
            orientation_at: state.orientationAt,
            final_requirements_approved: true,
          }],
        };
      }
      if (text.includes('FOR UPDATE') && text.includes('file_path')) {
        return {
          rowCount: 1,
          rows: [{
            ...APPLICANT,
            hired_user_id: null,
            status: 'passed',
            file_path: state.filePath,
            file_name: 'medical.pdf',
          }],
        };
      }
      if (text.includes('FOR UPDATE')) {
        return { rowCount: 1, rows: [{ ...APPLICANT, status: state.status }] };
      }
      if (text.includes('SET status')) {
        state.status = params[0];
        return { rowCount: 1, rows: [] };
      }
      if (text.includes('SET final_interview_at')) {
        state.finalInterviewAt = params[0];
        return { rowCount: 1, rows: [{ id: APPLICATION_ID }] };
      }
      if (text.includes('SET orientation_at')) {
        state.orientationAt = params[0];
        return { rowCount: 1, rows: [{ id: APPLICATION_ID }] };
      }
      if (text.includes('final_requirements_approved = FALSE')) {
        state.filePath = null;
        return { rowCount: 1, rows: [{ id: APPLICATION_ID }] };
      }
      if (text.includes('SELECT email, full_name')) {
        return { rowCount: 1, rows: [APPLICANT] };
      }
      return { rowCount: 0, rows: [] };
    },
  };

  const restoreDb = withMockedModule('../src/config/db', { pool });
  const restoreIssued = withMockedModule('../src/services/rspIssuedForm', {
    assertIssuedFormSchema: async () => {},
    shouldEnableIssuedFormGate: (previous) =>
      previous === 'submitted' || previous === 'document_declined',
    assessmentBlocked: () => false,
    assignRequiredForm: async () => ({
      assignment: { formType: assignState.formType, status: 'assigned' },
      created: assignState.applicantNotice,
      applicantNotice: assignState.applicantNotice,
    }),
    requestFormRevision: async () => ({
      assignment: {
        formType: 'ojt',
        status: 'needs_revision',
        reviewComment: revisionState.comment,
      },
      applicantNotice: revisionState.applicantNotice,
    }),
    sendIssuedFormError: (res, err) => {
      res.status(err.status || 500).json({ error: err.message });
    },
  });
  const restorePre = withMockedModule('../src/services/rspPreDeliberation', {
    assertPreDeliberationSchema: async () => {},
    missingPrerequisites: () => [],
    assignWorkExperience: async () => ({
      tracking: { wesStatus: 'assigned' },
      applicantNotice: wesState.applicantNotice,
      created: wesState.applicantNotice,
    }),
    reviewWes: async () => ({
      tracking: { wesReviewComment: 'Add dates.' },
      applicantNotice: true,
    }),
    sendPreDeliberationError: (res, err) => {
      res.status(err.status || 500).json({ error: err.message });
    },
  });
  const restoreFinal = withMockedModule('../src/services/rspFinalHiring', {
    assertFinalHiringSchema: async () => {},
    sendFinalHiringError: (res, err) => {
      res.status(err.status || 500).json({ error: err.message });
    },
  });
  clearModule('../src/services/rspApplicantNotices');
  clearModule('../src/routes/rspApplications');
  const router = require('../src/routes/rspApplications');
  const notices = require('../src/services/rspApplicantNotices');
  notices.resetApplicantNoticeDedupe();

  const status = lastHandler(router, 'put', '/:applicationId/status');
  const interview = lastHandler(router, 'put', '/:applicationId/final-interview');
  const orientation = lastHandler(router, 'put', '/:applicationId/orientation');
  const assign = lastHandler(router, 'post', '/:applicationId/required-form/assign');
  const revision = lastHandler(router, 'post', '/:applicationId/required-form/revision');
  const wes = lastHandler(router, 'post', '/:applicationId/work-experience/assign');
  const wesRevision = lastHandler(router, 'post', '/:applicationId/work-experience/revision');
  const reject = lastHandler(router, 'post', '/:applicationId/final-requirements/:kind/reject');

  const approved = response();
  await status({
    params: { applicationId: APPLICATION_ID },
    body: { status: 'document_approved' },
  }, approved);
  assert.equal(approved.statusCode, 200);
  assert.equal(calls.at(-1)[1], 'template_document_decision');
  assert.equal(paramsOf(calls.at(-1)).decision, 'Approved');

  const sameStatus = response();
  await status({
    params: { applicationId: APPLICATION_ID },
    body: { status: 'document_approved' },
  }, sameStatus);
  assert.equal(sameStatus.statusCode, 200);
  assert.equal(calls.length, 1);

  const deliberation = response();
  await interview({
    params: { applicationId: APPLICATION_ID },
    body: { finalInterviewAt: '2026-10-11T07:00:00.000Z' },
  }, deliberation);
  assert.equal(deliberation.statusCode, 200);
  assert.equal(paramsOf(calls.at(-1)).event_name, 'Deliberation');

  const sameTime = response();
  await interview({
    params: { applicationId: APPLICATION_ID },
    body: { finalInterviewAt: '2026-10-11T07:00:00.000Z' },
  }, sameTime);
  assert.equal(sameTime.statusCode, 200);
  assert.equal(calls.length, 2);

  const cleared = response();
  await interview({
    params: { applicationId: APPLICATION_ID },
    body: { finalInterviewAt: null },
  }, cleared);
  assert.equal(cleared.statusCode, 200);
  assert.equal(calls.length, 2);

  const moved = response();
  await interview({
    params: { applicationId: APPLICATION_ID },
    body: { finalInterviewAt: '2026-10-12T01:30:00.000Z' },
  }, moved);
  assert.equal(moved.statusCode, 200);
  assert.match(paramsOf(calls.at(-1)).schedule_at, /9:30 AM/);

  const orientationRes = response();
  await orientation({
    params: { applicationId: APPLICATION_ID },
    body: { orientationAt: '2026-10-20T00:00:00.000Z' },
  }, orientationRes);
  assert.equal(orientationRes.statusCode, 200);
  assert.equal(paramsOf(calls.at(-1)).event_name, 'Orientation');

  const bi = response();
  await assign({
    params: { applicationId: APPLICATION_ID },
    body: { formType: 'bi' },
    user: { id: 'staff' },
  }, bi);
  assert.equal(bi.statusCode, 200);
  assert.equal(paramsOf(calls.at(-1)).action_title, 'Background Investigation Form');

  assignState.applicantNotice = false;
  const repeatAssign = response();
  await assign({
    params: { applicationId: APPLICATION_ID },
    body: { formType: 'bi' },
    user: { id: 'staff' },
  }, repeatAssign);
  assert.equal(repeatAssign.statusCode, 200);
  assert.equal(paramsOf(calls.at(-1)).action_title, 'Background Investigation Form');

  const formRevision = response();
  await revision({
    params: { applicationId: APPLICATION_ID },
    body: { comment: revisionState.comment },
    user: { id: 'staff' },
  }, formRevision);
  assert.equal(formRevision.statusCode, 200);
  assert.equal(paramsOf(calls.at(-1)).action_title, 'OJT / Work Immersion Evaluation');
  assert.equal(paramsOf(calls.at(-1)).hr_comment, 'Fix the school name.');

  const wesQuiet = response();
  await wes({
    params: { applicationId: APPLICATION_ID },
    body: {},
    user: { id: 'staff' },
  }, wesQuiet);
  assert.equal(wesQuiet.statusCode, 200);
  assert.equal(paramsOf(calls.at(-1)).action_title, 'OJT / Work Immersion Evaluation');

  wesState.applicantNotice = true;
  const wesAssign = response();
  await wes({
    params: { applicationId: APPLICATION_ID },
    body: {},
    user: { id: 'staff' },
  }, wesAssign);
  assert.equal(paramsOf(calls.at(-1)).action_title, 'Work Experience Sheet');

  const wesRev = response();
  await wesRevision({
    params: { applicationId: APPLICATION_ID },
    body: { comment: 'Add dates.' },
    user: { id: 'staff' },
  }, wesRev);
  assert.equal(paramsOf(calls.at(-1)).hr_comment, 'Add dates.');

  const beforeReject = calls.length;
  const rejected = response();
  await reject({
    params: { applicationId: APPLICATION_ID, kind: 'medical_certificate' },
    body: { reason: 'Blurry scan' },
  }, rejected);
  assert.equal(rejected.statusCode, 200);
  assert.equal(paramsOf(calls.at(-1)).document_name, 'Medical Certificate');
  assert.equal(paramsOf(calls.at(-1)).reason, 'Blurry scan');

  const secondReject = response();
  await reject({
    params: { applicationId: APPLICATION_ID, kind: 'medical_certificate' },
    body: { reason: 'Blurry scan' },
  }, secondReject);
  assert.equal(secondReject.statusCode, 400);
  assert.equal(calls.length, beforeReject + 1);

  failSend = true;
  state.status = 'document_declined';
  notices.resetApplicantNoticeDedupe();
  const mailDown = response();
  await status({
    params: { applicationId: APPLICATION_ID },
    body: { status: 'document_approved' },
  }, mailDown);
  assert.equal(mailDown.statusCode, 200);
  assert.equal(mailDown.body.ok, true);

  restoreFinal();
  restorePre();
  restoreIssued();
  restoreDb();
  clearModule('../src/routes/rspApplications');
  clearModule('../src/services/rspApplicantNotices');
  restoreSend();
  restoreEnv();
});
