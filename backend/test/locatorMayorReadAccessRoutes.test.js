'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const actor = '11111111-1111-4111-8111-111111111111';
const owner = '22222222-2222-4222-8222-222222222222';
const otherMayor = '33333333-3333-4333-8333-333333333333';
const id = '44444444-4444-4444-8444-444444444444';

async function read(path, { currentMayor = actor, route = 'mayor_direct', own = false, reviewer = false } = {}) {
  const calls = [];
  const query = async (sql, params) => {
    calls.push({ sql, params });
    if (/^CREATE /.test(sql.trim())) return { rows: [] };
    if (sql.includes('INSERT INTO locator_request_types')) return { rows: [] };
    if (sql.trim().startsWith('UPDATE locator_slips AS slip')) return { rows: [] };
    if (sql.includes("= 'mayor'")) return { rows: currentMayor ? [{ employee_id: currentMayor }] : [] };
    if (sql.includes('FROM locator_slips ls')) return { rows: [{
      id, employee_id: own ? actor : owner, status: 'approved', final_review_route: route,
      dept_head_reviewer_id: reviewer ? actor : null, attachment_name: 'support.pdf', attachment_path: null,
    }] };
    if (sql.includes('locator_slip_history')) return { rows: [{ event_type: 'submitted' }] };
    if (sql.includes('locator_attachment_access_logs')) return { rows: [] };
    if (sql.includes('COUNT(*)::integer AS total')) return { rows: [{ total: 0 }] };
    throw new Error(`Unexpected query: ${sql}`);
  };
  const restore = withMockedModule('../src/config/db', { pool: { query, connect: async () => ({ query, release() {} }) } });
  clearModule('../src/routes/locatorSlips');
  try {
    const router = require('../src/routes/locatorSlips');
    const handler = router.stack.find(e => e.route?.path === path && e.route.methods.get).route.stack.at(-1).handle;
    const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
    await handler({ user: { id: actor, role: 'mayor' }, params: { id }, query: {}, get() { return 'test'; } }, res);
    return { res, calls };
  } finally {
    clearModule('../src/routes/locatorSlips');
    restore();
  }
}

test('the Mayor queue uses the same current-authority check', async () => {
  for (const currentMayor of [actor, otherMayor, null]) {
    const { res, calls } = await read('/admin', { currentMayor });
    assert.equal(res.code, currentMayor === actor ? 200 : 403);
    assert.equal(calls.some(c => c.sql.includes('COUNT(*)::integer AS total')), currentMayor === actor);
  }
});

for (const path of ['/:id/history', '/:id/attachment']) {
  for (const currentMayor of [otherMayor, null]) {
    test(`${path} denies Mayor role alone when current Mayor is ${currentMayor}`, async () => {
      const { res, calls } = await read(path, { currentMayor });
      assert.equal(res.code, 404);
      assert.equal(res.body.error, 'Locator slip not found');
      assert.equal(calls.some(c => c.sql.includes('FROM locator_slip_history')), false);
      if (path.endsWith('/attachment')) {
        const audit = calls.find(c => c.sql.includes('INSERT INTO locator_attachment_access_logs'));
        assert.equal(audit.params[4], 'not_authorized');
        assert.equal(audit.params[5], 'denied');
      }
    });
  }
  test(`${path} permits the current direct-route Mayor and preserves independent access`, async () => {
    for (const options of [{}, { currentMayor: otherMayor, own: true, route: 'hr' }, { currentMayor: otherMayor, reviewer: true }]) {
      const { res } = await read(path, options);
      if (path.endsWith('/attachment')) assert.equal(res.body.error, 'No attachment for this request');
      else assert.equal(res.code, 200);
    }
    for (const route of ['hr', 'mayor']) {
      const { res } = await read(path, { route });
      assert.equal(res.body.error, 'Locator slip not found');
    }
  });
}
