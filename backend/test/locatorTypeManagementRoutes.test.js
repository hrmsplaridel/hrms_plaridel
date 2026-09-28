'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

function rowFromCreateParams(params) {
  return {
    id: '11111111-1111-4111-8111-111111111111',
    code: params[0],
    label: params[1],
    short_label: params[2],
    location_label: params[3],
    location_hint: params[4],
    dtr_slot_label: params[5],
    dtr_print_label: params[6],
    requires_attachment: params[7],
    coverage_mode: params[8],
    is_active: params[9],
    is_system: false,
    sort_order: params[10],
  };
}

async function withCreateRoute(run) {
  const inserts = [];
  const query = async (sql, params = []) => {
    const statement = String(sql).replace(/\s+/g, ' ').trim();
    if (statement.startsWith('INSERT INTO locator_request_types') && params.length === 11) {
      inserts.push({ statement, params });
      return { rows: [rowFromCreateParams(params)] };
    }
    return { rows: [] };
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query, connect: async () => ({ query, release() {} }) },
  });
  clearModule('../src/routes/locatorSlips');
  try {
    const router = require('../src/routes/locatorSlips');
    const route = router.stack.find((entry) =>
      entry.route?.path === '/types' && entry.route.methods.post
    );
    await run(route.route.stack.at(-1).handle, inserts);
  } finally {
    clearModule('../src/routes/locatorSlips');
    restoreDb();
  }
}

const basePayload = {
  code: 'remote_work',
  label: 'Remote Work',
};

test('locator type creation rejects malformed rules without writing', async () => {
  await withCreateRoute(async (handler, inserts) => {
    const cases = [
      [{ sort_order: 'abc' }, /Sort order must be a whole number/],
      [{ sort_order: '12abc' }, /Sort order must be a whole number/],
      [{ sort_order: '1.5' }, /Sort order must be a whole number/],
      [{ sort_order: -1 }, /Sort order must be a whole number/],
      [{ sort_order: 2147483648 }, /Sort order must be a whole number/],
      [{ coverage_mode: '' }, /Coverage mode must be manual or wfh/],
      [{ coverage_mode: 'wfhh' }, /Coverage mode must be manual or wfh/],
      [{ requires_attachment: 'yes' }, /Requires attachment must be a boolean/],
      [{ is_active: 'enabled' }, /Available for filing must be a boolean/],
    ];

    for (const [override, message] of cases) {
      const res = responseRecorder();
      await handler({ body: { ...basePayload, ...override } }, res);
      assert.equal(res.statusCode, 400);
      assert.match(res.body.error, message);
    }
    assert.equal(inserts.length, 0);
  });
});

test('locator type creation persists valid explicit rules', async () => {
  await withCreateRoute(async (handler, inserts) => {
    const res = responseRecorder();
    await handler({
      body: {
        ...basePayload,
        requires_attachment: true,
        coverage_mode: 'wfh',
        is_active: false,
        sort_order: 30,
      },
    }, res);

    assert.equal(res.statusCode, 201);
    assert.equal(inserts.length, 1);
    assert.equal(inserts[0].params[7], true);
    assert.equal(inserts[0].params[8], 'wfh');
    assert.equal(inserts[0].params[9], false);
    assert.equal(inserts[0].params[10], 30);
  });
});
