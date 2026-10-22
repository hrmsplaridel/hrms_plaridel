const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  requireMayor,
  requireMayorOfficeStaff,
  requireMayorEndorsementAccess,
} = require('../src/middleware/rbac');

function mockRes() {
  return {
    statusCode: 200,
    body: null,
    status(n) {
      this.statusCode = n;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

function runMw(mw, role) {
  const res = mockRes();
  let nextCalled = false;
  mw({ user: role == null ? null : { role } }, res, () => {
    nextCalled = true;
  });
  return { res, nextCalled };
}

test('requireMayor allows only mayor', () => {
  assert.equal(runMw(requireMayor, 'mayor').nextCalled, true);
  for (const role of ['mayor_office_staff', 'admin', 'employee', null]) {
    const { res, nextCalled } = runMw(requireMayor, role);
    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 403);
  }
});

test('requireMayorOfficeStaff allows only staff', () => {
  assert.equal(runMw(requireMayorOfficeStaff, 'mayor_office_staff').nextCalled, true);
  for (const role of ['mayor', 'admin', 'employee', null]) {
    const { res, nextCalled } = runMw(requireMayorOfficeStaff, role);
    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 403);
  }
});

test('requireMayorEndorsementAccess allows mayor and staff', () => {
  assert.equal(runMw(requireMayorEndorsementAccess, 'mayor').nextCalled, true);
  assert.equal(
    runMw(requireMayorEndorsementAccess, 'mayor_office_staff').nextCalled,
    true,
  );
  const denied = runMw(requireMayorEndorsementAccess, 'admin');
  assert.equal(denied.nextCalled, false);
  assert.equal(denied.res.statusCode, 403);
});

test('Mayor endorsement routes wire staff vs mayor guards', () => {
  const src = fs.readFileSync(
    path.join(__dirname, '../src/routes/mayorEndorsements.js'),
    'utf8',
  );
  assert.match(src, /const staffOpsOnly = \[authMiddleware, requireMayorOfficeStaff\]/);
  assert.match(src, /const mayorDecisionOnly = \[authMiddleware, requireMayor\]/);
  assert.match(src, /const endorsementAccess = \[authMiddleware, requireMayorEndorsementAccess\]/);
  assert.match(src, /router\.post\('\/requests',\s*staffOpsOnly/);
  assert.match(src, /router\.post\('\/:id\/meeting-request',\s*staffOpsOnly/);
  assert.match(src, /router\.post\('\/:id\/schedule',\s*staffOpsOnly/);
  // Attendance: Mayor or Staff (endorsementAccess) — early/sudden meetings.
  assert.match(src, /router\.post\('\/:id\/no-show',\s*endorsementAccess/);
  assert.match(src, /router\.post\('\/:id\/met',\s*endorsementAccess/);
  assert.match(src, /router\.post\('\/:id\/meeting\/approve',\s*mayorDecisionOnly/);
  assert.match(src, /router\.post\('\/:id\/endorse',\s*mayorDecisionOnly/);
  assert.match(src, /router\.post\('\/:id\/approve',\s*mayorDecisionOnly/);
  assert.match(src, /router\.post\('\/:id\/approve-form',\s*mayorDecisionOnly/);
  assert.match(src, /router\.post\('\/:id\/reject',\s*mayorDecisionOnly/);
  assert.match(src, /router\.get\('\/dashboard',\s*endorsementAccess/);
  assert.match(src, /router\.get\('\/history',\s*endorsementAccess/);
});

test('M4 migration adds mayor_office_staff without changing single-mayor index', () => {
  const m4 = fs.readFileSync(
    path.join(
      __dirname,
      '../scripts/migrations/20261020_mayor_isolation_m4_staff_role.sql',
    ),
    'utf8',
  );
  assert.match(m4, /mayor_office_staff/);
  assert.doesNotMatch(m4, /DROP INDEX/i);
  assert.match(m4, /Keeps users_single_active_mayor_idx unchanged/i);
  assert.doesNotMatch(m4, /CREATE UNIQUE INDEX[\s\S]*mayor_office_staff/i);
  const init = fs.readFileSync(
    path.join(__dirname, '../scripts/init-schema.sql'),
    'utf8',
  );
  assert.match(init, /mayor_office_staff/);
  assert.match(
    init,
    /CREATE UNIQUE INDEX IF NOT EXISTS users_single_active_mayor_idx[\s\S]*WHERE role = 'mayor' AND is_active = true/i,
  );
});

test('Leave and DocuTracker still key off mayor role only', () => {
  const leave = fs.readFileSync(
    path.join(__dirname, '../src/routes/leaveRoutes.js'),
    'utf8',
  );
  assert.match(leave, /role\s*===\s*'mayor'/);
  assert.doesNotMatch(leave, /mayor_office_staff/);
  const sig = fs.readFileSync(
    path.join(__dirname, '../src/services/docutrackerLeaveSignatureService.js'),
    'utf8',
  );
  assert.match(sig, /role\s*===\s*'mayor'/);
  assert.doesNotMatch(sig, /mayor_office_staff/);
});
