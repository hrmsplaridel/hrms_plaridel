const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

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

test('DTR attendance writes reject employees and allow Admin or HR', () => {
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query: async () => { throw new Error('database must not be reached'); } },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');

  for (const [method, path] of [['post', '/'], ['put', '/:id']]) {
    const handlers = route(router, method, path);
    const guard = handlers.find((handler) => handler.name === 'requireAdminOrHr');
    assert.ok(guard, `${method.toUpperCase()} ${path} is missing the Admin/HR guard`);

    const employeeRes = response();
    let employeeAdvanced = false;
    guard(
      { user: { id: 'employee-1', role: 'employee' } },
      employeeRes,
      () => { employeeAdvanced = true; },
    );
    assert.equal(employeeRes.statusCode, 403);
    assert.equal(employeeAdvanced, false);

    for (const role of ['admin', 'hr']) {
      const allowedRes = response();
      let allowedAdvanced = false;
      guard(
        { user: { id: `${role}-1`, role } },
        allowedRes,
        () => { allowedAdvanced = true; },
      );
      assert.equal(allowedAdvanced, true, `${role} should be allowed`);
    }
  }

  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});

test('blank Admin or HR manual DTR entry is rejected before database access', async () => {
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      query: async () => {
        throw new Error('blank manual entry must not reach the database');
      },
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');
  const handlers = route(router, 'post', '/');
  const req = {
    user: { id: 'admin-1', role: 'admin' },
    body: {
      employee_id: 'employee-1',
      attendance_date: '2026-08-14',
      time_in: null,
      break_out: '',
      break_in: null,
      time_out: '   ',
    },
  };
  const res = response();

  await handlers[handlers.length - 1](req, res);

  assert.equal(res.statusCode, 400);
  assert.match(res.payload?.error || '', /at least one attendance punch/i);
  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});

test('DTR deletion requires an administrator reason before database access', async () => {
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      connect: async () => {
        throw new Error('invalid deletion must not reach the database');
      },
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');
  const handlers = route(router, 'delete', '/:id');
  const req = {
    user: { id: '9da0c4c5-37eb-4c1b-9b55-af79f1336b31', role: 'admin' },
    params: { id: '5cc06130-7dd8-4792-bc4f-ac1b423bb2a9' },
    body: { reason: '  ' },
  };
  const res = response();

  await handlers[handlers.length - 1](req, res);

  assert.equal(res.statusCode, 400);
  assert.match(res.payload?.error || '', /deletion reason/i);
  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});

test('DTR deletion snapshots the processed row and preserves biometric logs', async () => {
  const queries = [];
  const targetRow = {
    id: '5cc06130-7dd8-4792-bc4f-ac1b423bb2a9',
    employee_id: '5b9fe943-4700-4ff6-a84e-66ef793ecfc4',
    attendance_date: '2026-06-16',
    attendance_date_iso: '2026-06-16',
    time_in: '2026-06-16T00:00:00.000Z',
    time_out: '2026-06-16T09:00:00.000Z',
    source: 'system',
    status: 'present',
  };
  const client = {
    async query(sql, params = []) {
      queries.push({ sql: String(sql), params });
      if (/SELECT d\.\*/i.test(String(sql))) {
        return { rowCount: 1, rows: [targetRow] };
      }
      return { rowCount: 1, rows: [] };
    },
    release() {},
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      connect: async () => client,
      query: async () => ({ rowCount: 0, rows: [] }),
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');
  const handlers = route(router, 'delete', '/:id');
  const req = {
    user: { id: '9da0c4c5-37eb-4c1b-9b55-af79f1336b31', role: 'admin' },
    params: { id: targetRow.id },
    body: { reason: 'Biometric device recorded the wrong employee.' },
  };
  const res = response();

  await handlers[handlers.length - 1](req, res);

  assert.equal(res.statusCode, 204);
  assert.ok(
    queries.some(({ sql }) => /INSERT INTO dtr_daily_summary_deletions/i.test(sql)),
    'deletion audit snapshot was not inserted',
  );
  assert.ok(
    queries.some(({ sql }) => /DELETE FROM dtr_daily_summary WHERE id/i.test(sql)),
    'processed DTR row was not deleted',
  );
  assert.equal(
    queries.some(({ sql }) => /DELETE FROM biometric_attendance_logs/i.test(sql)),
    false,
    'raw biometric evidence must not be deleted',
  );
  const auditInsert = queries.find(({ sql }) => /INSERT INTO dtr_daily_summary_deletions/i.test(sql));
  assert.deepEqual(JSON.parse(auditInsert.params[6]), targetRow);

  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});

test('DTR restoration recreates the saved snapshot and records the restoring administrator', async () => {
  const queries = [];
  const deletionId = '1dbb69ac-d1f1-44ca-a692-f11506e8dd80';
  const employeeId = '5b9fe943-4700-4ff6-a84e-66ef793ecfc4';
  const recordId = '5cc06130-7dd8-4792-bc4f-ac1b423bb2a9';
  const actorId = '9da0c4c5-37eb-4c1b-9b55-af79f1336b31';
  const deletion = {
    id: deletionId,
    deleted_dtr_summary_id: recordId,
    employee_id: employeeId,
    attendance_date: '2026-06-16',
    restored_at: null,
    record_snapshot: {
      source: 'system',
      status: 'present',
      time_in: '2026-06-16T00:00:00.000Z',
      time_out: '2026-06-16T09:00:00.000Z',
      total_hours: 8,
      late_minutes: 0,
      undertime_minutes: 0,
      overtime_minutes: 0,
      created_at: '2026-06-16T09:01:00.000Z',
    },
  };
  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ sql: text, params });
      if (/SELECT \*\s+FROM dtr_daily_summary_deletions/i.test(text)) {
        return { rowCount: 1, rows: [deletion] };
      }
      if (/SELECT id\s+FROM dtr_daily_summary\s+WHERE employee_id/i.test(text)) {
        return { rowCount: 0, rows: [] };
      }
      if (/INSERT INTO dtr_daily_summary \(/i.test(text)) {
        return {
          rowCount: 1,
          rows: [
            {
              id: recordId,
              employee_id: employeeId,
              attendance_date: '2026-06-16',
              source: 'system',
              status: 'present',
            },
          ],
        };
      }
      return { rowCount: 1, rows: [] };
    },
    release() {},
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      connect: async () => client,
      query: async () => ({ rowCount: 0, rows: [] }),
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');
  const handlers = route(router, 'post', '/deletions/:deletionId/restore');
  const req = {
    user: { id: actorId, role: 'admin' },
    params: { deletionId },
    body: { reason: 'Deletion was made against the wrong employee.' },
  };
  const res = response();

  await handlers[handlers.length - 1](req, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.payload?.id, recordId);
  const insert = queries.find(({ sql }) => /INSERT INTO dtr_daily_summary \(/i.test(sql));
  assert.ok(insert, 'saved DTR snapshot was not restored');
  assert.equal(insert.params[0], recordId);
  assert.equal(insert.params[1], employeeId);
  const auditUpdate = queries.find(({ sql }) => /UPDATE dtr_daily_summary_deletions/i.test(sql));
  assert.ok(auditUpdate, 'restoration metadata was not recorded');
  assert.deepEqual(auditUpdate.params, [
    deletionId,
    actorId,
    'Deletion was made against the wrong employee.',
  ]);

  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});

test('DTR restoration refuses to overwrite a corrected attendance row', async () => {
  const deletionId = '1dbb69ac-d1f1-44ca-a692-f11506e8dd80';
  const client = {
    async query(sql) {
      const text = String(sql);
      if (/SELECT \*\s+FROM dtr_daily_summary_deletions/i.test(text)) {
        return {
          rowCount: 1,
          rows: [
            {
              id: deletionId,
              employee_id: '5b9fe943-4700-4ff6-a84e-66ef793ecfc4',
              attendance_date: '2026-06-16',
              restored_at: null,
              record_snapshot: {},
            },
          ],
        };
      }
      if (/SELECT id\s+FROM dtr_daily_summary\s+WHERE employee_id/i.test(text)) {
        return { rowCount: 1, rows: [{ id: 'corrected-record' }] };
      }
      return { rowCount: 0, rows: [] };
    },
    release() {},
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { connect: async () => client },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  const router = require('../src/routes/dtrDailySummary');
  const handlers = route(router, 'post', '/deletions/:deletionId/restore');
  const res = response();

  await handlers[handlers.length - 1](
    {
      user: { id: '9da0c4c5-37eb-4c1b-9b55-af79f1336b31', role: 'admin' },
      params: { deletionId },
      body: { reason: 'Restore the original biometric record.' },
    },
    res,
  );

  assert.equal(res.statusCode, 409);
  assert.match(res.payload?.error || '', /attendance already exists/i);
  restoreWs();
  restoreDb();
  clearModule('../src/routes/dtrDailySummary');
});
