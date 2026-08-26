const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');

const { createAuthMiddleware } = require('../src/middleware/auth');

function responseRecorder() {
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

function tokenFor(payload) {
  return jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: '5m' });
}

test('authentication rejects a deactivated account before access-token expiry', async () => {
  const previousSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = 'account-state-test-secret';
  try {
    const middleware = createAuthMiddleware({
      query: async () => ({
        rowCount: 1,
        rows: [
          {
            id: '11111111-1111-4111-8111-111111111111',
            email: 'employee@example.test',
            role: 'employee',
            is_active: false,
            employment_status: 'active',
          },
        ],
      }),
    });
    const req = {
      headers: {
        authorization: `Bearer ${tokenFor({
          id: '11111111-1111-4111-8111-111111111111',
          role: 'employee',
          typ: 'access',
        })}`,
      },
    };
    const res = responseRecorder();
    let called = false;

    await middleware(req, res, () => {
      called = true;
    });

    assert.equal(called, false);
    assert.equal(res.statusCode, 403);
    assert.equal(res.body.error, 'Account is deactivated');
  } finally {
    process.env.JWT_SECRET = previousSecret;
  }
});

test('authentication uses the current database role instead of the stale token role', async () => {
  const previousSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = 'account-role-test-secret';
  try {
    const middleware = createAuthMiddleware({
      query: async () => ({
        rowCount: 1,
        rows: [
          {
            id: '22222222-2222-4222-8222-222222222222',
            email: 'former-admin@example.test',
            role: 'employee',
            is_active: true,
            employment_status: 'active',
          },
        ],
      }),
    });
    const req = {
      headers: {
        authorization: `Bearer ${tokenFor({
          id: '22222222-2222-4222-8222-222222222222',
          role: 'admin',
          typ: 'access',
        })}`,
      },
    };
    const res = responseRecorder();
    let called = false;

    await middleware(req, res, () => {
      called = true;
    });

    assert.equal(called, true);
    assert.equal(req.user.role, 'employee');
    assert.equal(res.statusCode, 200);
  } finally {
    process.env.JWT_SECRET = previousSecret;
  }
});
