const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const APPLICATION_ID = '9da0c4c5-37eb-4c1b-9b55-af79f1336b31';
const SECRET = 'required-form-access-test-secret-32';

function response() {
  return {
    statusCode: 200,
    payload: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.payload = body; return this; },
    send(body) { this.payload = body; return this; },
  };
}

function route(router, method, path) {
  const layer = router.stack.find((item) => item.route?.path === path && item.route.methods?.[method]);
  assert.ok(layer, `${method.toUpperCase()} ${path} route not found`);
  return layer.route.stack.map((item) => item.handle);
}

function staffToken(role) {
  return jwt.sign(
    {
      id: '11111111-1111-4111-8111-111111111111',
      email: `${role}@example.com`,
      role,
      typ: 'access',
      auth_version: 1,
    },
    process.env.JWT_SECRET,
  );
}

async function invoke(handlers, req) {
  const res = response();
  for (const handler of handlers) {
    let advanced = false;
    await handler(req, res, () => { advanced = true; });
    if (!advanced) break;
  }
  return res;
}

test('required-form staff routes allow Admin and HR and block everyone else', async () => {
  const previousSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = SECRET;
  let account = null;
  const assignCalls = [];
  const reviewCalls = [];

  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      query: async (sql) => {
        if (String(sql).includes('FROM users')) {
          return account ? { rows: [account], rowCount: 1 } : { rows: [], rowCount: 0 };
        }
        if (String(sql).includes('step4_gate_required')) {
          return {
            rows: [{
              gate_column: true,
              wes_link: true,
              profile_link: true,
              lineup_link: true,
            }],
            rowCount: 1,
          };
        }
        if (String(sql).includes('step5_gate_required')) {
          return { rows: [{ gate_column: true }], rowCount: 1 };
        }
        return { rows: [], rowCount: 0 };
      },
    },
  });
  const restoreIssued = withMockedModule('../src/services/rspIssuedForm', {
    assertIssuedFormSchema: async () => {},
    assessmentBlocked: () => false,
    shouldEnableIssuedFormGate: () => false,
    getRequiredForm: async () => ({ assignment: { status: 'assigned' }, entry: null }),
    assignRequiredForm: async (args) => {
      assignCalls.push(args);
      return {
        assignment: { formType: args.formType, status: 'assigned' },
        entry: { id: 'entry-1' },
        created: true,
      };
    },
    approveRequiredForm: async (args) => {
      reviewCalls.push({ action: 'approve', ...args });
      return { assignment: { status: 'approved' }, entry: null };
    },
    requestFormRevision: async (args) => {
      reviewCalls.push({ action: 'revision', ...args });
      return { assignment: { status: 'needs_revision' }, entry: null };
    },
    sendIssuedFormError: (res, err) => {
      res.status(err.status || 500).json({ error: err.message, code: err.code });
    },
  });
  clearModule('../src/middleware/auth');
  clearModule('../src/utils/rspEmailVerifyToken');
  clearModule('../src/routes/rspApplications');
  const router = require('../src/routes/rspApplications');
  process.env.JWT_SECRET = SECRET;
  clearModule('../src/utils/rspEmailVerifyToken');
  const tokens = require('../src/utils/rspEmailVerifyToken');

  const assign = route(router, 'post', '/:applicationId/required-form/assign');
  const read = route(router, 'get', '/:applicationId/required-form');
  const approve = route(router, 'post', '/:applicationId/required-form/approve');
  const revision = route(router, 'post', '/:applicationId/required-form/revision');
  const statusUpdate = route(router, 'put', '/:applicationId/status');
  const applicantMine = route(router, 'get', '/:applicationId/required-form/mine');

  for (const handlers of [assign, read, approve, revision]) {
    assert.equal(handlers[0].name, 'authMiddleware');
    assert.equal(handlers[1].name, 'requireAdminOrHr');
    assert.equal(handlers.some((handler) => handler.name === 'requireAdmin'), false);
    assert.equal(handlers.some((handler) => handler.name === 'requireApplicantProof'), false);
  }
  assert.equal(statusUpdate[1].name, 'requireAdmin');
  assert.equal(applicantMine[0].name, 'requireApplicantProof');

  function asRole(role) {
    account = {
      id: '11111111-1111-4111-8111-111111111111',
      email: `${role}@example.com`,
      role,
      is_active: true,
      employment_status: 'active',
      auth_version: 1,
    };
  }

  async function postAssign(role, formType) {
    asRole(role);
    return invoke(assign, {
      headers: { authorization: `Bearer ${staffToken(role)}` },
      params: { applicationId: APPLICATION_ID },
      body: { formType },
    });
  }

  const adminBi = await postAssign('admin', 'bi');
  assert.equal(adminBi.statusCode, 200);
  assert.equal(adminBi.payload.assignment.formType, 'bi');
  assert.equal(assignCalls.at(-1).formType, 'bi');
  assert.equal(assignCalls.at(-1).actorId, account.id);

  const hrBi = await postAssign('hr', 'bi');
  assert.equal(hrBi.statusCode, 200);
  assert.equal(assignCalls.at(-1).formType, 'bi');

  const hrOjt = await postAssign('hr', 'ojt');
  assert.equal(hrOjt.statusCode, 200);
  assert.equal(hrOjt.payload.assignment.formType, 'ojt');
  assert.equal(assignCalls.at(-1).formType, 'ojt');

  const beforeBlocked = assignCalls.length;
  const employeeAssign = await postAssign('employee', 'bi');
  assert.equal(employeeAssign.statusCode, 403);
  assert.equal(assignCalls.length, beforeBlocked);

  const supervisorAssign = await postAssign('supervisor', 'bi');
  assert.equal(supervisorAssign.statusCode, 403);
  assert.equal(assignCalls.length, beforeBlocked);

  account = null;
  const applicantToken = tokens.signRspApplicantAccessToken(APPLICATION_ID, 'applicant@example.com');
  const applicantAssign = await invoke(assign, {
    headers: { authorization: `Bearer ${applicantToken}` },
    params: { applicationId: APPLICATION_ID },
    body: { formType: 'bi' },
  });
  assert.equal(applicantAssign.statusCode, 401);
  assert.equal(assignCalls.length, beforeBlocked);

  const missingAuth = await invoke(assign, {
    headers: {},
    params: { applicationId: APPLICATION_ID },
    body: { formType: 'bi' },
  });
  assert.equal(missingAuth.statusCode, 401);
  assert.equal(assignCalls.length, beforeBlocked);

  asRole('hr');
  const hrApprove = await invoke(approve, {
    headers: { authorization: `Bearer ${staffToken('hr')}` },
    params: { applicationId: APPLICATION_ID },
    body: {},
  });
  assert.equal(hrApprove.statusCode, 200);
  assert.equal(reviewCalls.at(-1).action, 'approve');

  const hrRevision = await invoke(revision, {
    headers: { authorization: `Bearer ${staffToken('hr')}` },
    params: { applicationId: APPLICATION_ID },
    body: { comment: 'Correct the school name.' },
  });
  assert.equal(hrRevision.statusCode, 200);
  assert.equal(reviewCalls.at(-1).action, 'revision');

  asRole('employee');
  const employeeApprove = await invoke(approve, {
    headers: { authorization: `Bearer ${staffToken('employee')}` },
    params: { applicationId: APPLICATION_ID },
    body: {},
  });
  assert.equal(employeeApprove.statusCode, 403);

  asRole('hr');
  const hrStatus = await invoke(statusUpdate, {
    headers: { authorization: `Bearer ${staffToken('hr')}` },
    params: { applicationId: APPLICATION_ID },
    body: { status: 'document_approved' },
  });
  assert.equal(hrStatus.statusCode, 403);

  restoreIssued();
  restoreDb();
  clearModule('../src/routes/rspApplications');
  clearModule('../src/middleware/auth');
  clearModule('../src/utils/rspEmailVerifyToken');
  if (previousSecret === undefined) delete process.env.JWT_SECRET;
  else process.env.JWT_SECRET = previousSecret;
});
