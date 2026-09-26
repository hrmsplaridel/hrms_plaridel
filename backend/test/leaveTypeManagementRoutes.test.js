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

async function withCreateRoute(run) {
  const inserts = [];
  const query = async (sql, params = []) => {
    const statement = String(sql).replace(/\s+/g, ' ').trim();
    if (statement.startsWith('INSERT INTO leave_types')) {
      inserts.push({ statement, params });
      return {
        rows: [{
          id: '11111111-1111-4111-8111-111111111111',
          name: params[0],
          display_name: params[1],
          description: params[2],
          is_active: params[3],
          is_system: false,
          employee_can_file: params[4],
          admin_only: params[5],
          allows_past_dates: params[6],
          requires_attachment: params[7],
          requires_attachment_when_over_days: params[8],
          max_days: params[9],
          minimum_advance_days: params[10],
          affects_dtr_normally: params[11],
          balance_ledger_type: params[12],
          entitlement_basis: params[13],
          sex_eligibility: params[14],
          employee_detail_schema: [],
        }],
      };
    }
    return { rows: [] };
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query, connect: async () => ({ query, release() {} }) },
  });
  clearModule('../src/routes/leaveRoutes');
  try {
    const router = require('../src/routes/leaveRoutes');
    const route = router.stack.find((entry) =>
      entry.route?.path === '/types' && entry.route.methods.post
    );
    await run(route.route.stack.at(-1).handle, inserts);
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
}

const basePayload = {
  name: 'bereavementLeave',
  display_name: 'Bereavement Leave',
};

test('leave type creation rejects malformed and unsafe numeric rules', async () => {
  await withCreateRoute(async (handler, inserts) => {
    const cases = [
      [{ max_days: 'abc' }, /Maximum working days must be a valid number/],
      [{ max_days: 0 }, /Maximum working days must be greater than 0/],
      [{ max_days: -1 }, /Maximum working days must be greater than 0/],
      [{ requires_attachment_when_over_days: 0 }, /Attachment threshold days must be greater than 0/],
      [{ minimum_advance_days: '1.5' }, /Minimum advance days must be a whole number/],
      [{ minimum_advance_days: '12days' }, /Minimum advance days must be a whole number/],
    ];

    const originalError = console.error;
    console.error = () => {};
    try {
      for (const [override, message] of cases) {
        const res = responseRecorder();
        await handler({ body: { ...basePayload, ...override } }, res);
        assert.equal(res.statusCode, 400);
        assert.match(res.body.error, message);
      }
    } finally {
      console.error = originalError;
    }
    assert.equal(inserts.length, 0);
  });
});

test('leave type creation accepts positive decimals and zero advance days', async () => {
  await withCreateRoute(async (handler, inserts) => {
    const res = responseRecorder();
    await handler({
      body: {
        ...basePayload,
        max_days: 5.5,
        requires_attachment: true,
        requires_attachment_when_over_days: 3,
        minimum_advance_days: 0,
      },
    }, res);

    assert.equal(res.statusCode, 201);
    assert.equal(inserts.length, 1);
    assert.equal(inserts[0].params[8], 3);
    assert.equal(inserts[0].params[9], 5.5);
    assert.equal(inserts[0].params[10], 0);
  });
});
