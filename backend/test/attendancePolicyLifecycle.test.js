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

async function updatePolicy({ body, isUsed = true, currentOverrides = {} }) {
  const queries = [];
  const invalidations = [];
  const current = policyRow({ isUsed, overrides: currentOverrides });
  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      queries.push({ text, params });
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(text)) {
        return { rows: [], rowCount: 0 };
      }
      if (text.includes('pg_advisory_xact_lock')) {
        return { rows: [{}], rowCount: 1 };
      }
      if (text.includes('SET is_default = false') && text.includes('id <> $1')) {
        return { rows: [], rowCount: 0 };
      }
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
    release() {},
  };
  const pool = {
    async connect() {
      return client;
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

test('promoting an active policy demotes the previous default in the same transaction', async () => {
  const { res, queries } = await updatePolicy({
    isUsed: false,
    body: { is_default: true },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.is_default, true);
  assert.equal(queries[0].text, 'BEGIN');
  assert.equal(queries.some(({ text }) => text.includes('pg_advisory_xact_lock')), true);
  assert.equal(
    queries.some(({ text }) => text.includes('SET is_default = false') && text.includes('id <> $1')),
    true
  );
  assert.equal(queries.at(-1).text, 'COMMIT');
});

test('deactivating the default policy also clears its default flag', async () => {
  const { res, queries } = await updatePolicy({
    isUsed: false,
    currentOverrides: { is_default: true },
    body: { is_default: true, is_active: false },
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.is_active, false);
  assert.equal(res.body.is_default, false);
  const update = queries.find(({ text }) => text.startsWith('UPDATE attendance_policies SET'));
  assert.match(update.text, /is_default = \$\d+/);
});

test('an inactive policy cannot be promoted as default', async () => {
  const { res, queries } = await updatePolicy({
    isUsed: false,
    body: { is_default: true, is_active: false },
  });

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /active policy/i);
  assert.equal(
    queries.some(({ text }) => text.startsWith('UPDATE attendance_policies SET')),
    false
  );
  assert.equal(queries.at(-1).text, 'ROLLBACK');
});
