const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

function response() {
  return {
    statusCode: 200,
    payload: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.payload = body; return this; },
  };
}

function route(router, method, path) {
  const layer = router.stack.find((item) => item.route?.path === path && item.route.methods?.[method]);
  assert.ok(layer, `${method.toUpperCase()} ${path} route not found`);
  return layer.route.stack.map((item) => item.handle);
}

test('applicant access tokens are bound to both email and application id', () => {
  const previous = process.env.JWT_SECRET;
  process.env.JWT_SECRET = 'test-secret-with-at-least-thirty-two-characters';
  clearModule('../src/utils/rspEmailVerifyToken');
  const tokens = require('../src/utils/rspEmailVerifyToken');
  const id = '9da0c4c5-37eb-4c1b-9b55-af79f1336b31';
  const token = tokens.signRspApplicantAccessToken(id, 'person@example.com');
  assert.equal(tokens.verifyRspApplicantAccessToken(token, id, 'person@example.com'), true);
  assert.equal(tokens.verifyRspApplicantAccessToken(token, '8eae3aed-f4c7-431c-a582-9042be848ad7', 'person@example.com'), false);
  assert.equal(tokens.verifyRspApplicantAccessToken(token, id, 'attacker@example.com'), false);
  process.env.JWT_SECRET = previous;
  clearModule('../src/utils/rspEmailVerifyToken');
});

test('public registration cannot request an administrator role', async () => {
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query: async () => { throw new Error('database must not be reached'); } },
  });
  clearModule('../src/routes/auth');
  const router = require('../src/routes/auth');
  const handlers = route(router, 'post', '/register');
  const req = { body: { email: 'x@example.com', password: 'password123', role: 'admin' } };
  const res = response();
  await handlers[handlers.length - 1](req, res);
  assert.equal(res.statusCode, 403);
  restoreDb();
  clearModule('../src/routes/auth');
});

test('recruitment upload rejects a non-UUID path before multer writes a file', () => {
  const restoreDb = withMockedModule('../src/config/db', { pool: { query: async () => ({ rows: [] }) } });
  clearModule('../src/routes/rspApplications');
  const router = require('../src/routes/rspApplications');
  const handlers = route(router, 'post', '/:applicationId/attachment-file');
  const rejectInvalidPath = handlers.find((handler) => handler.name === 'rejectInvalidApplicationId');
  assert.ok(rejectInvalidPath, 'UUID validation middleware is missing');
  const req = { params: { applicationId: '..\\..\\outside' } };
  const res = response();
  rejectInvalidPath(req, res, () => assert.fail('invalid path reached the next middleware'));
  assert.equal(res.statusCode, 400);
  restoreDb();
  clearModule('../src/routes/rspApplications');
});

test('training attachment endpoint requires a signed token', async () => {
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query: async () => { throw new Error('database must not be reached'); } },
  });
  clearModule('../src/routes/files');
  const router = require('../src/routes/files');
  const handlers = route(router, 'get', '/training-report/:attachmentId');
  const req = { params: { attachmentId: 'attachment-1' }, query: {} };
  const res = response();
  await handlers[handlers.length - 1](req, res);
  assert.equal(res.statusCode, 401);
  restoreDb();
  clearModule('../src/routes/files');
});
