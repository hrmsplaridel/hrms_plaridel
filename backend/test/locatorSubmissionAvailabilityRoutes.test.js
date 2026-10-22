'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const applicant = '11111111-1111-4111-8111-111111111111';
const head = '22222222-2222-4222-8222-222222222222';
const alternate = '33333333-3333-4333-8333-333333333333';
const mayor = '44444444-4444-4444-8444-444444444444';
const type = (route = 'hr', extra = {}) => ({ code: 'travel', label: 'Travel Order', is_active: true,
  filing_access: 'employee', approval_route: route, mayor_employment_types: null, ...extra });

async function availability({ types = [type()], employmentType = 'regular', mayorId = mayor,
  finals = [], departmentIds = [head], queryParams = {}, failQuery = false } = {}) {
  const calls = [];
  const dates = [];
  const query = async (sql, params = []) => {
    calls.push({ sql, params });
    if (/^CREATE /.test(sql.trim()) || sql.includes('INSERT INTO locator_request_types') ||
      sql.trim().startsWith('UPDATE locator_slips AS slip')) return { rows: [] };
    if (failQuery && sql.includes('FROM locator_request_types')) throw new Error('Fixture database unavailable');
    if (sql.includes('FROM locator_request_types')) return { rows: types.filter(t => t.is_active !== false) };
    if (sql.includes('SELECT employment_type')) {
      assert.equal(params[0], applicant);
      return { rows: [{ employment_type: employmentType }] };
    }
    if (sql.includes("= 'mayor'")) return { rows: mayorId ? [{ employee_id: mayorId, name: 'Mayor' }] : [] };
    if (sql.includes('primary_reviewer_designations')) return { rows: finals.slice(0, 1) };
    if (sql.includes('leave_final_reviewer_backups')) return { rows: finals.slice(1) };
    throw new Error(`Unexpected query: ${sql}`);
  };
  const department = require('../src/services/departmentHeadService');
  const restores = [
    withMockedModule('../src/config/db', { pool: { query, connect: async () => ({ query, release() {} }) } }),
    withMockedModule('../src/services/departmentHeadService', { ...department,
      getDepartmentReviewSnapshotForDate: async (_db, employeeId, date) => {
        assert.equal(employeeId, applicant);
        dates.push(date);
        return { departmentHeadUserId: departmentIds[0] || null, reviewerUserIds: departmentIds,
          reviewers: departmentIds.map(reviewerId => ({ reviewerId })) };
      } }),
  ];
  const servicePath = path.join(__dirname, '../src/services/locatorSubmissionAvailability.js');
  delete require.cache[servicePath];
  clearModule('../src/routes/locatorSlips');
  const originalError = console.error;
  try {
    console.error = () => {};
    const router = require('../src/routes/locatorSlips');
    const handler = router.stack.find(e => e.route?.path === '/submission-availability').route.stack.at(-1).handle;
    const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
    await handler({ user: { id: applicant, role: 'employee' }, query: queryParams }, res);
    return { res, calls, dates };
  } finally {
    console.error = originalError;
    clearModule('../src/routes/locatorSlips');
    delete require.cache[servicePath];
    restores.reverse().forEach(restore => restore());
  }
}

test('regular employee excluded from a restricted Mayor type needs an eligible HR route', async () => {
  const { res } = await availability({ types: [type('mayor_direct', { mayor_employment_types: ['job_order'] })] });
  assert.equal(res.code, 200);
  assert.equal(res.body.can_submit, false);
  assert.match(res.body.reason, /final locator reviewer/i);
  assert.equal(res.body.types[0].route, 'hr');
  assert.equal(res.body.types[0].can_submit, false);
});

test('HR/admin-only and inactive types cannot make employee filing available', async () => {
  for (const excluded of [type('mayor_direct', { filing_access: 'admin' }), type('mayor_direct', { is_active: false })]) {
    const { res } = await availability({ types: [excluded], finals: [{ id: alternate, role: 'hr' }] });
    assert.equal(res.body.can_submit, false);
    assert.match(res.body.reason, /employee filing/i);
    assert.deepEqual(res.body.types, []);
  }
});

test('manual Mayor signing requires a department reviewer even with an available Mayor', async () => {
  const { res } = await availability({ types: [type('mayor')], departmentIds: [] });
  assert.equal(res.body.can_submit, false);
  assert.match(res.body.reason, /department reviewer/i);
  assert.equal(res.body.types[0].route, 'mayor');
});

test('eligible direct and manual Mayor routes do not need a final HR reviewer', async () => {
  for (const route of ['mayor_direct', 'mayor']) {
    const { res } = await availability({ types: [type(route, { filing_access: 'both', mayor_employment_types: ['job_order'] })],
      employmentType: 'job_order', departmentIds: route === 'mayor_direct' ? [] : [head] });
    assert.equal(res.body.can_submit, true);
    assert.equal(res.body.types[0].route, route);
    assert.equal(res.body.types[0].can_submit, true);
  }
});

test('absent or self Mayor blocks Mayor-only routes', async () => {
  for (const mayorId of [null, applicant]) {
    const { res } = await availability({ types: [type('mayor_direct')], mayorId });
    assert.equal(res.body.can_submit, false);
    assert.match(res.body.reason, /eligible active Mayor/i);
  }
});

test('HR availability honors distinct stages, applicant exclusion, and admin module permissions', async () => {
  for (const finals of [[{ id: head, role: 'hr' }], [{ id: applicant, role: 'hr' }],
    [{ id: alternate, role: 'admin', locator_allowed: false }]]) {
    const { res } = await availability({ finals });
    assert.equal(res.body.can_submit, false);
    assert.ok(res.body.reason);
  }
  for (const config of [
    { finals: [{ id: head, role: 'hr' }, { id: alternate, role: 'admin', locator_allowed: true }] },
    { finals: [{ id: head, role: 'hr' }], departmentIds: [head, alternate] },
    { finals: [{ id: head, role: 'hr' }], departmentIds: [] },
  ]) {
    const { res } = await availability(config);
    assert.equal(res.body.can_submit, true);
  }
});

test('an excluded employee may use the restricted type through HR when that route is ready', async () => {
  const { res } = await availability({ types: [type('mayor_direct', { mayor_employment_types: ['job_order'] })],
    mayorId: null, finals: [{ id: alternate, role: 'hr' }] });
  assert.equal(res.body.can_submit, true);
  assert.equal(res.body.types[0].route, 'hr');
});

test('mixed availability reports usable types and route-specific blocking reasons', async () => {
  const { res, calls } = await availability({ types: [type('mayor_direct'), type('hr', { code: 'field', label: 'Field Work' })] });
  assert.equal(res.body.can_submit, true);
  assert.deepEqual(res.body.types.map(t => [t.code, t.route, t.can_submit]),
    [['travel', 'mayor_direct', true], ['field', 'hr', false]]);
  assert.match(res.body.types[1].reason, /final locator reviewer/i);
  assert.equal(calls.some(c => /^\s*(INSERT|UPDATE|DELETE)/.test(c.sql) && !c.sql.includes('locator_request_types') && !c.sql.includes('UPDATE locator_slips AS slip')), false);
});

test('availability uses the requested locator date and ignores another employee ID', async () => {
  const { res, dates } = await availability({ queryParams: { slip_date: '2026-10-20', employee_id: mayor },
    types: [type('mayor_direct')] });
  assert.equal(res.body.can_submit, true);
  assert.deepEqual(dates, ['2026-10-20']);
  assert.equal(res.body.effective_date, '2026-10-20');
});

test('invalid availability dates and unexpected database errors fail closed', async () => {
  const invalid = await availability({ queryParams: { slip_date: '2026-02-30' } });
  assert.equal(invalid.res.code, 400);
  const failed = await availability({ failQuery: true });
  assert.equal(failed.res.code, 500);
  assert.notEqual(failed.res.body.can_submit, true);
});
