'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const policyId = '11111111-1111-4111-8111-111111111111';

function policyRow({ isUsed = true, overrides = {} } = {}) {
  return {
    id: policyId,
    name: 'Standard policy',
    description: null,
    work_hours_per_day: '8.00',
    use_equivalent_day_conversion: true,
    deduct_late: false,
    convert_late_to_equivalent_day: true,
    deduct_undertime: true,
    convert_undertime_to_equivalent_day: true,
    absent_equals_full_day_deduction: true,
    combine_late_and_undertime: false,
    deduction_multiplier: '1.000',
    is_default: false,
    is_active: true,
    is_used: isUsed,
    created_at: new Date('2026-01-01T00:00:00.000Z'),
    ...overrides,
  };
}

async function updatePolicy({ body, isUsed = true }) {
  const queries = [];
  const invalidations = [];
  const current = policyRow({ isUsed });
  const pool = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ text, params });
      if (text.includes('FROM attendance_policies') && text.includes('WHERE id = $1')) {
        return { rows: [current], rowCount: 1 };
      }
      if (text.startsWith('UPDATE attendance_policies SET')) {
        const updated = { ...current };
        for (const match of text.split(' WHERE ')[0].matchAll(/(\w+) = \$(\d+)/g)) {
          updated[match[1]] = params[Number(match[2]) - 1];
        }
        return { rows: [updated], rowCount: 1 };
      }
      throw new Error(`Unexpected query: ${text}`);
    },
  };
  const restore = withMockedModule('../src/config/db', { pool });
  const restoreCache = withMockedModule('../src/services/attendancePolicyCache', {
    invalidateAttendancePolicyCache: (options) => invalidations.push(options),
  });
  const routePath = '../src/routes/attendancePolicies';
  clearModule(routePath);
  const res = {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
  try {
    const router = require(routePath);
    const route = router.stack.find(
      (entry) => entry.route?.path === '/:id' && entry.route.methods.put
    );
    await route.route.stack.at(-1).handle(
      { params: { id: policyId }, body },
      res
    );
    return { res, queries, invalidations };
  } finally {
    clearModule(routePath);
    restoreCache();
    restore();
  }
}

test('used policy rejects changes to computation settings', async () => {
  const { res, queries } = await updatePolicy({
    body: { work_hours_per_day: 1 },
  });

  assert.equal(res.statusCode, 409);
  assert.match(res.body.error, /already been used/i);
  assert.deepEqual(res.body.locked_fields, ['work_hours_per_day']);
  assert.equal(queries.some(({ text }) => text.startsWith('UPDATE ')), false);
});

test('used policy permits metadata edits with unchanged submitted settings', async () => {
  const { res, queries, invalidations } = await updatePolicy({
    body: {
      policy_name: 'Renamed standard policy',
      description: 'Corrected description',
      work_hours_per_day: 8,
      use_equivalent_day_conversion: true,
      deduct_late: false,
      convert_late_to_equivalent_day: true,
      deduct_undertime: true,
      convert_undertime_to_equivalent_day: true,
      absent_equals_full_day_deduction: true,
      combine_late_and_undertime: false,
      deduction_multiplier: 1,
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.policy_name, 'Renamed standard policy');
  assert.equal(res.body.is_used, true);
  assert.equal(queries.some(({ text }) => text.startsWith('UPDATE ')), true);
  assert.deepEqual(invalidations, [undefined]);
});

test('unused policy permits computation changes', async () => {
  const { res } = await updatePolicy({
    isUsed: false,
    body: {
      work_hours_per_day: 1,
      deduct_late: true,
      deduction_multiplier: 2,
    },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.work_hours_per_day, 1);
  assert.equal(res.body.deduct_late, true);
  assert.equal(res.body.deduction_multiplier, 2);
  assert.equal(res.body.is_used, false);
});
