const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const express = require('express');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const entry = '../src/routes/locatorSlips';
const EMPLOYEE = '11111111-1111-4111-8111-111111111111';

async function withUploadServer(run) {
  const uploadRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hrms-locator-module-'));
  const originalRoot = process.env.UPLOAD_DIR;
  const submissions = [];
  let failSubmission = false;
  const query = async () => ({ rows: [] });
  const restores = [
    withMockedModule('../src/config/db', { pool: { query, connect: async () => ({ query, release() {} }) } }),
    withMockedModule('../src/middleware/auth', {
      authMiddleware(req, _res, next) { req.user = { id: EMPLOYEE, role: 'employee' }; next(); },
    }),
    withMockedModule('../src/services/locatorSubmissionService', {
      createLocatorSubmissionService: () => ({ async submit(input) {
        submissions.push(input);
        if (failSubmission) throw Object.assign(new Error('Conflict'), {
          statusCode: 409, payload: { error: 'Fixture conflict', code: 'locator_conflict' },
        });
        return { id: 'saved', status: 'pending_department_head' };
      } }),
    }),
  ];
  let server;
  try {
    process.env.UPLOAD_DIR = uploadRoot;
    clearModule(entry);
    const app = express();
    app.use('/api/locator-slips', require(entry));
    server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    await run({
      uploadRoot, submissions,
      failNextSubmission() { failSubmission = true; },
      async upload(filename = 'support.pdf') {
        const form = new FormData();
        for (const [key, value] of Object.entries({
          slip_date: '2026-10-20', office: 'Municipal Hall', reason: 'Official meeting',
          request_type: 'locator', am_in: 'true', am_out: '1', pm_in: 'false', pm_out: '0',
          signature: '{"asset_id":"applicant-ink"}', additional_details: '{"contact":"Earl"}',
        })) form.set(key, value);
        form.set('file', new Blob(['%PDF-fixture'], { type: 'application/pdf' }), filename);
        return fetch(`http://127.0.0.1:${server.address().port}/api/locator-slips/submit-with-attachment`, {
          method: 'POST', body: form,
        });
      },
    });
  } finally {
    if (server) await new Promise((resolve) => server.close(resolve));
    clearModule(entry);
    restores.reverse().forEach((restore) => restore());
    if (originalRoot === undefined) delete process.env.UPLOAD_DIR;
    else process.env.UPLOAD_DIR = originalRoot;
    // Only remove the unique directory created by this test.
    assert.equal(path.dirname(uploadRoot), path.resolve(os.tmpdir()));
    assert.ok(path.basename(uploadRoot).startsWith('hrms-locator-module-'));
    fs.rmSync(uploadRoot, { recursive: true, force: true });
  }
}

test('real Locator multipart requests preserve storage paths, filing fields and applicant signature', async () => {
  await withUploadServer(async ({ upload, uploadRoot, submissions }) => {
    const response = await upload();
    assert.equal(response.status, 201);
    assert.deepEqual(await response.json(), { id: 'saved', status: 'pending_department_head' });
    const input = submissions[0];
    assert.equal(input.employeeUserId, EMPLOYEE);
    assert.equal(input.slipDate, '2026-10-20');
    assert.equal(input.office, 'Municipal Hall');
    assert.equal(input.reason, 'Official meeting');
    assert.equal(input.requestType, 'locator');
    assert.deepEqual([input.amIn, input.amOut, input.pmIn, input.pmOut], [true, true, false, false]);
    assert.equal(input.signature, '{"asset_id":"applicant-ink"}');
    assert.equal(input.additionalDetails, '{"contact":"Earl"}');
    assert.equal(input.attachment.name, 'support.pdf');
    assert.equal(input.attachment.mimeType, 'application/pdf');
    assert.match(input.attachment.path, /^locator-attachments\/[^/]+\.pdf$/);
    assert.equal(fs.readFileSync(path.join(uploadRoot, input.attachment.path), 'utf8'), '%PDF-fixture');
  });
});

test('Locator rejects unsupported uploads and removes a stored file after submission failure', async () => {
  await withUploadServer(async ({ upload, uploadRoot, submissions, failNextSubmission }) => {
    const denied = await upload('support.exe');
    assert.equal(denied.status, 400);
    assert.match((await denied.json()).error, /Only PDF, JPG, JPEG, or PNG/);
    assert.equal(submissions.length, 0);
    assert.deepEqual(fs.readdirSync(path.join(uploadRoot, 'locator-attachments')), []);
    failNextSubmission();
    const conflict = await upload();
    assert.equal(conflict.status, 409);
    assert.equal((await conflict.json()).code, 'locator_conflict');
    assert.equal(submissions.length, 1);
    assert.equal(fs.existsSync(path.join(uploadRoot, submissions[0].attachment.path)), false);
  });
});

for (const failAudit of [false, true]) {
  test(`Locator cancellation ${failAudit ? 'rolls back on history failure' : 'commits history before broadcasting'}`, async () => {
    const events = [];
    const client = {
      async query(sql) {
        const text = String(sql).trim();
        events.push(text.startsWith('SELECT') ? 'LOCK' : text.startsWith('UPDATE') ? 'UPDATE' : text);
        return { rows: text.startsWith('SELECT') ? [{ id: 'request', status: 'pending_hr' }] : [] };
      },
      release() { events.push('RELEASE'); },
    };
    const row = { id: 'request', employee_id: EMPLOYEE, status: 'cancelled', slip_date_text: '2026-10-20' };
    const pool = {
      async query(sql) {
        if (String(sql).trim().startsWith('SELECT ls.*')) {
          assert.ok(events.includes('COMMIT'));
          return { rows: [row] };
        }
        return { rows: [] };
      },
      connect: async () => client,
    };
    const originalHistory = require('../src/services/locatorWorkflowHistory');
    const restores = [
      withMockedModule('../src/config/db', { pool }),
      withMockedModule('../src/services/locatorWorkflowHistory', { ...originalHistory,
        async recordLocatorWorkflowEvent(db, input) {
          assert.equal(db, client);
          assert.equal(input.action, 'cancelled');
          assert.equal(input.fromStatus, 'pending_hr');
          events.push('HISTORY');
          if (failAudit) throw new Error('Fixture history failure');
        },
      }),
      withMockedModule('../src/websockets/appEvents', {
        broadcastAppEvent(name, input) {
          assert.ok(events.includes('COMMIT'));
          assert.equal(name, 'locator_updated');
          assert.equal(input.action, 'cancelled');
          assert.equal(input.userId, EMPLOYEE);
          events.push('BROADCAST');
        },
      }),
    ];
    const originalError = console.error;
    clearModule(entry);
    try {
      if (failAudit) console.error = () => {};
      const handle = require(entry).stack.find((l) => l.route?.path === '/:id/cancel').route.stack.at(-1).handle;
      const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; } };
      await handle({ user: { id: EMPLOYEE }, params: { id: 'request' } }, res);
      assert.equal(res.statusCode, failAudit ? 500 : 200);
      assert.deepEqual(events, failAudit
        ? ['BEGIN', 'LOCK', 'UPDATE', 'HISTORY', 'ROLLBACK', 'RELEASE']
        : ['BEGIN', 'LOCK', 'UPDATE', 'HISTORY', 'COMMIT', 'BROADCAST', 'RELEASE']);
      if (!failAudit) assert.equal(res.body.status, 'cancelled');
    } finally {
      console.error = originalError;
      clearModule(entry);
      restores.reverse().forEach((restore) => restore());
    }
  });
}
