'use strict';

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

async function summary({ holidayCoverage = null, leaveFails = false } = {}) {
  const queries = [];
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      async query(sql, params = []) {
        const text = String(sql);
        queries.push({ sql: text, params });
        if (/FROM holidays/i.test(text)) {
          return holidayCoverage
            ? { rows: [{ id: 'h1', name: 'Holiday', holiday_type: 'regular', coverage: holidayCoverage,
              date_from: '2000-01-01', date_to: '2100-12-31', recurring: false }] }
            : { rows: [] };
        }
        if (/status = 'late'/.test(text)) return { rows: [{ c: '3' }] };
        if (/FROM dtr_daily_summary WHERE attendance_date/.test(text)) return { rows: [{ c: '12' }] };
        if (/covered_employees/.test(text)) {
          if (leaveFails) throw new Error('leave coverage missing');
          return { rows: [{ c: '4' }] };
        }
        if (/FROM leave_requests\s+WHERE status IN/.test(text)) return { rows: [{ c: '7' }] };
        return { rows: [] };
      },
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });
  clearModule('../src/routes/dtrDailySummary');
  try {
    const router = require('../src/routes/dtrDailySummary');
    const layer = router.stack.find((item) => item.route?.path === '/summary' && item.route.methods.get);
    const handler = layer.route.stack.at(-1).handle;
    const res = response();
    const warn = console.warn;
    console.warn = () => {};
    try {
      await handler({ user: { id: 'admin', role: 'admin' } }, res);
    } finally {
      console.warn = warn;
    }
    return { res, queries };
  } finally {
    clearModule('../src/routes/dtrDailySummary');
    restoreWs();
    restoreDb();
  }
}

test('dashboard summary counts present, late, on-leave and pending approvals for today', async () => {
  const { res, queries } = await summary();
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.payload, {
    present_today: 12, late_today: 3, on_leave_today: 4, pending_approval: 7,
  });
  const presentQuery = queries.find(({ sql }) => /AND time_in IS NOT NULL$/.test(sql.trim()));
  assert.match(presentQuery.params[0], /^\d{4}-\d{2}-\d{2}$/);
});

test('a whole-day holiday zeroes present and late counts', async () => {
  const { res } = await summary({ holidayCoverage: 'whole_day' });
  assert.equal(res.payload.present_today, 0);
  assert.equal(res.payload.late_today, 0);
  assert.equal(res.payload.on_leave_today, 4);
});

test('an on-leave lookup failure still returns the other counts', async () => {
  const { res } = await summary({ leaveFails: true });
  assert.equal(res.statusCode, 200);
  assert.equal(res.payload.on_leave_today, 0);
  assert.equal(res.payload.present_today, 12);
});
