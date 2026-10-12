const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

function response() {
  return {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('DTR report and management access are independent, and personal attendance remains available', async () => {
  let access = { reports_allowed: true, manage_allowed: false };
  const restore = withMockedModule('../src/config/db', {
    pool: { async query() { return { rows: [access] }; } },
  });
  const path = '../src/middleware/dtrAccess';
  clearModule(path);
  try {
    const {
      requireDtrReportsIfAdmin,
      requireDtrManageIfAdmin,
      requireAnyDtrAccessForList,
      requireDtrFeatureIfAdmin,
    } = require(path);
    const req = { user: { role: 'admin', id: 'admin-1' }, query: {} };
    let nextCalls = 0;
    const next = () => { nextCalls++; };
    await requireDtrReportsIfAdmin(req, response(), next);
    assert.equal(nextCalls, 1);
    const denied = response();
    await requireDtrManageIfAdmin(req, denied, next);
    assert.equal(denied.statusCode, 403);

    access = { ...access, leave_allowed: false };
    const leaveDenied = response();
    await requireDtrFeatureIfAdmin('leave_allowed')(req, leaveDenied, next);
    assert.equal(leaveDenied.statusCode, 403);
    access = { ...access, leave_allowed: true };
    await requireDtrFeatureIfAdmin('leave_allowed')(req, response(), next);
    assert.equal(nextCalls, 2);

    access = { reports_allowed: false, manage_allowed: false };
    const listDenied = response();
    await requireAnyDtrAccessForList(req, listDenied, next);
    assert.equal(listDenied.statusCode, 403);
    await requireAnyDtrAccessForList({
      user: req.user,
      query: { employee_id: 'admin-1' },
    }, response(), next);
    assert.equal(nextCalls, 3);

    const employee = { user: { role: 'employee', id: 'employee-1' }, query: {} };
    await requireDtrReportsIfAdmin(employee, response(), next);
    assert.equal(nextCalls, 4);
  } finally {
    clearModule(path);
    restore();
  }
});

test('only super-admin can save DTR permissions and changes are audited', async () => {
  const queries = [];
  const client = {
    async query(sql, params) {
      queries.push({ sql, params });
      if (sql.includes('FROM users WHERE id')) return { rows: [{ role: 'admin' }] };
      if (sql.includes('FROM dtr_admin_access WHERE')) {
        return { rows: [{ reports_allowed: true, manage_allowed: true, revision: 'r1' }] };
      }
      if (sql.includes('INSERT INTO dtr_admin_access')) return { rows: [{ revision: 'r2' }] };
      return { rows: [] };
    },
    release() {},
  };
  const restore = withMockedModule('../src/config/db', {
    pool: { async connect() { return client; } },
  });
  const path = '../src/routes/dtrAccess';
  clearModule('../src/middleware/dtrAccess');
  clearModule(path);
  try {
    const router = require(path);
    const route = router.stack.find(entry => entry.route?.methods.put).route;
    const denied = response();
    route.stack[1].handle({ user: { role: 'admin' } }, denied, () => {});
    assert.equal(denied.statusCode, 403);

    const invalid = response();
    await route.stack[2].handle({ params: { adminId: 'bad' }, body: {} }, invalid);
    assert.equal(invalid.statusCode, 400);

    const success = response();
    await route.stack[2].handle({
      user: { id: '00000000-0000-4000-8000-000000000002' },
      params: { adminId: '00000000-0000-4000-8000-000000000001' },
      body: { reports_allowed: false, manage_allowed: true, expected_revision: 'r1' },
    }, success);
    assert.equal(success.statusCode, 200);
    assert.equal(success.body.revision, 'r2');
    assert.ok(queries.some(({ sql }) => sql.includes('dtr_admin_access_changed')));
    assert.ok(queries.some(({ sql }) => sql === 'COMMIT'));
  } finally {
    clearModule(path);
    clearModule('../src/middleware/dtrAccess');
    restore();
  }
});

test('assigned reviewer access cannot be disabled before reassignment', async () => {
  const queries = [];
  const client = {
    async query(sql) {
      queries.push(sql);
      if (sql.includes('FROM users WHERE id')) return { rows: [{ role: 'admin' }] };
      if (sql.includes('FROM dtr_admin_access WHERE')) return { rows: [{
        reports_allowed: true, manage_allowed: true, corrections_allowed: true,
        employees_allowed: true, leave_allowed: true, approvals_allowed: true,
        locator_allowed: true, revision: 'r1',
      }] };
      return { rows: [] };
    },
    release() {},
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { async connect() { return client; } },
  });
  const restoreReviewers = withMockedModule('../src/services/dtrFeatureReviewerAccess', {
    activeReviewerFeatures: async () => ({ leave_allowed: true, locator_allowed: false }),
  });
  const path = '../src/routes/dtrAccess';
  clearModule(path);
  try {
    const router = require(path);
    const route = router.stack.find(entry => entry.route?.methods.put).route;
    const result = response();
    await route.stack[2].handle({
      user: { id: '00000000-0000-4000-8000-000000000002' },
      params: { adminId: '00000000-0000-4000-8000-000000000001' },
      body: { reports_allowed: true, manage_allowed: true, leave_allowed: false, expected_revision: 'r1' },
    }, result);
    assert.equal(result.statusCode, 409);
    assert.match(result.body.error, /Reassign this active reviewer/);
    assert.ok(queries.includes('ROLLBACK'));
    assert.ok(!queries.some(sql => sql.includes('INSERT INTO dtr_admin_access')));
  } finally {
    clearModule(path);
    restoreReviewers();
    restoreDb();
  }
});

test('report generation and DTR write routes include permission middleware', () => {
  const {
    requireDtrReportsIfAdmin,
    requireDtrManageIfAdmin,
  } = require('../src/middleware/dtrAccess');
  const summary = require('../src/routes/dtrDailySummary');
  const biometric = require('../src/routes/biometricAttendanceLogs');
  const report = summary.stack.find(entry =>
    entry.route?.path === '/bulk-report' && entry.route.methods.post
  ).route;
  const manualEntry = summary.stack.find(entry =>
    entry.route?.path === '/' && entry.route.methods.post
  ).route;
  const importLogs = biometric.stack.find(entry =>
    entry.route?.path === '/import' && entry.route.methods.post
  ).route;
  assert.ok(report.stack.some(layer => layer.handle === requireDtrReportsIfAdmin));
  assert.ok(manualEntry.stack.some(layer => layer.handle === requireDtrManageIfAdmin));
  assert.ok(importLogs.stack.some(layer => layer.handle === requireDtrManageIfAdmin));
});
