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
    employee_detail_schema: JSON.parse(params[15]),
  };
}

async function withCreateRoute(run, { insertError = null } = {}) {
  const inserts = [];
  const query = async (sql, params = []) => {
    const statement = String(sql).replace(/\s+/g, ' ').trim();
    if (statement.startsWith('INSERT INTO leave_types')) {
      inserts.push({ statement, params });
      if (insertError) throw insertError;
      return { rows: [rowFromCreateParams(params)] };
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

async function withUpdateRoute(existing, run) {
  const updates = [];
  const query = async (sql, params = []) => {
    const statement = String(sql).replace(/\s+/g, ' ').trim();
    if (statement.startsWith('SELECT * FROM leave_types WHERE id')) {
      return { rows: existing ? [existing] : [] };
    }
    if (statement.startsWith('UPDATE leave_types SET name =')) {
      updates.push({ statement, params });
      return {
        rows: [{
          ...existing,
          id: params[17],
          name: params[0],
          display_name: params[1],
          description: params[2],
          is_active: params[3],
          is_system: params[4],
          employee_can_file: params[5],
          admin_only: params[6],
          allows_past_dates: params[7],
          requires_attachment: params[8],
          requires_attachment_when_over_days: params[9],
          max_days: params[10],
          minimum_advance_days: params[11],
          affects_dtr_normally: params[12],
          balance_ledger_type: params[13],
          entitlement_basis: params[14],
          sex_eligibility: params[15],
          employee_detail_schema: JSON.parse(params[16]),
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
      entry.route?.path === '/types/:id' && entry.route.methods.put
    );
    await run(route.route.stack.at(-1).handle, updates);
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
}

async function withListRoute(run) {
  const includeInactiveValues = [];
  const active = {
    ...rowFromCreateParams([
      'activeLeave', 'Active Leave', null, true, true, false, true, false,
      null, null, null, true, 'none', 'per_request', 'any', '[]',
    ]),
    id: '22222222-2222-4222-8222-222222222222',
  };
  const inactive = {
    ...active,
    id: '33333333-3333-4333-8333-333333333333',
    name: 'inactiveLeave',
    display_name: 'Inactive Leave',
    is_active: false,
  };
  const query = async (sql, params = []) => {
    const statement = String(sql).replace(/\s+/g, ' ').trim();
    if (statement.startsWith('SELECT * FROM leave_types WHERE')) {
      includeInactiveValues.push(params[0]);
      return { rows: params[0] ? [active, inactive] : [active] };
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
      entry.route?.path === '/types' && entry.route.methods.get
    );
    await run(route.route.stack.at(-1).handle, includeInactiveValues);
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

test('leave type creation persists eligibility and custom field rules', async () => {
  await withCreateRoute(async (handler, inserts) => {
    const res = responseRecorder();
    await handler({
      body: {
        ...basePayload,
        description: 'For an immediate family bereavement.',
        is_active: true,
        allows_past_dates: false,
        requires_attachment: true,
        requires_attachment_when_over_days: 2,
        max_days: 5,
        minimum_advance_days: 0,
        entitlement_basis: 'per_event',
        sex_eligibility: 'female',
        employee_detail_schema: [{
          key: 'custom_relationship',
          label: 'Relationship',
          type: 'text',
          required: true,
          max_length: 80,
        }],
      },
    }, res);

    assert.equal(res.statusCode, 201);
    assert.equal(inserts.length, 1);
    assert.equal(inserts[0].params[6], false);
    assert.equal(inserts[0].params[8], 2);
    assert.equal(inserts[0].params[13], 'per_event');
    assert.equal(inserts[0].params[14], 'female');
    assert.deepEqual(JSON.parse(inserts[0].params[15]), [{
      key: 'custom_relationship',
      label: 'Relationship',
      type: 'text',
      required: true,
      max_length: 80,
    }]);
    assert.equal(res.body.sex_eligibility, 'female');
  });
});

test('duplicate leave type key returns conflict', async () => {
  const duplicate = Object.assign(new Error('duplicate key'), { code: '23505' });
  const originalError = console.error;
  console.error = () => {};
  try {
    await withCreateRoute(async (handler) => {
      const res = responseRecorder();
      await handler({ body: basePayload }, res);
      assert.equal(res.statusCode, 409);
      assert.equal(res.body.error, 'Leave type key already exists');
    }, { insertError: duplicate });
  } finally {
    console.error = originalError;
  }
});

test('custom leave type update persists inactive status and changed rules', async () => {
  const existing = {
    ...rowFromCreateParams([
      'bereavementLeave', 'Bereavement Leave', null, true, true, false, true,
      false, null, 5, 0, true, 'none', 'per_request', 'any', '[]',
    ]),
    id: '44444444-4444-4444-8444-444444444444',
  };

  await withUpdateRoute(existing, async (handler, updates) => {
    const res = responseRecorder();
    await handler({
      params: { id: existing.id },
      body: {
        name: 'bereavementLeave',
        display_name: 'Bereavement and Funeral Leave',
        is_active: false,
        max_days: 7,
        sex_eligibility: 'male',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(updates.length, 1);
    assert.equal(updates[0].params[0], 'bereavementLeave');
    assert.equal(updates[0].params[1], 'Bereavement and Funeral Leave');
    assert.equal(updates[0].params[3], false);
    assert.equal(updates[0].params[10], 7);
    assert.equal(updates[0].params[15], 'male');
    assert.equal(res.body.is_active, false);
  });
});

test('leave type update returns not found without writing', async () => {
  await withUpdateRoute(null, async (handler, updates) => {
    const res = responseRecorder();
    await handler({
      params: { id: '55555555-5555-4555-8555-555555555555' },
      body: basePayload,
    }, res);

    assert.equal(res.statusCode, 404);
    assert.equal(res.body.error, 'Leave type not found');
    assert.equal(updates.length, 0);
  });
});

test('inactive leave types are returned only for management requests', async () => {
  await withListRoute(async (handler, includeInactiveValues) => {
    const activeRes = responseRecorder();
    await handler({ query: {} }, activeRes);
    assert.deepEqual(activeRes.body.map((item) => item.name), ['activeLeave']);

    const managementRes = responseRecorder();
    await handler({ query: { include_inactive: '1' } }, managementRes);
    assert.deepEqual(
      managementRes.body.map((item) => item.name),
      ['activeLeave', 'inactiveLeave']
    );
    assert.deepEqual(includeInactiveValues, [false, true]);
  });
});
