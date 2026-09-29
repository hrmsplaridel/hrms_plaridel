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
  const events = [];
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
  const restoreAppEvents = withMockedModule('../src/websockets/appEvents', {
    broadcastAppEvent: (name, payload, options) => {
      events.push({ name, payload, options });
      return 1;
    },
  });
  clearModule('../src/routes/locatorSlips');
  try {
    const router = require('../src/routes/locatorSlips');
    const route = router.stack.find((entry) =>
      entry.route?.path === '/types' && entry.route.methods.post
    );
    await run(route.route.stack.at(-1).handle, inserts, events);
  } finally {
    clearModule('../src/routes/locatorSlips');
    restoreAppEvents();
    restoreDb();
  }
}

async function withMutationRoute({ method, used = false, isSystem = false }, run) {
  const events = [];
  const existing = {
    id: '22222222-2222-4222-8222-222222222222',
    code: 'remote_work',
    label: 'Remote Work',
    short_label: 'Remote',
    location_label: 'Work Location',
    location_hint: 'Enter work location',
    dtr_slot_label: 'Remote',
    dtr_print_label: 'REMOTE',
    requires_attachment: false,
    coverage_mode: 'wfh',
    is_active: true,
    is_system: isSystem,
    sort_order: 30,
  };
  const query = async (sql, params = []) => {
    const statement = String(sql).replace(/\s+/g, ' ').trim();
    if (statement.startsWith('SELECT * FROM locator_request_types WHERE id')) {
      return { rows: [existing] };
    }
    if (statement.startsWith('SELECT 1 FROM locator_slips')) {
      return { rows: used ? [{ exists: 1 }] : [] };
    }
    if (statement.startsWith('UPDATE locator_request_types SET label =')) {
      return {
        rows: [{
          ...existing,
          label: params[0],
          short_label: params[1],
          location_label: params[2],
          location_hint: params[3],
          dtr_slot_label: params[4],
          dtr_print_label: params[5],
          requires_attachment: params[6],
          coverage_mode: params[7],
          is_active: params[8],
          sort_order: params[9],
        }],
      };
    }
    if (statement.startsWith('UPDATE locator_request_types SET is_active = false')) {
      return { rows: [{ ...existing, is_active: false }] };
    }
    if (statement.startsWith('DELETE FROM locator_request_types')) {
      return { rows: [] };
    }
    return { rows: [] };
  };
  const restoreDb = withMockedModule('../src/config/db', {
    pool: { query, connect: async () => ({ query, release() {} }) },
  });
  const restoreAppEvents = withMockedModule('../src/websockets/appEvents', {
    broadcastAppEvent: (name, payload, options) => {
      events.push({ name, payload, options });
      return 1;
    },
  });
  clearModule('../src/routes/locatorSlips');
  try {
    const router = require('../src/routes/locatorSlips');
    const route = router.stack.find((entry) =>
      entry.route?.path === '/types/:id' && entry.route.methods[method]
    );
    await run(route.route.stack.at(-1).handle, events, existing);
  } finally {
    clearModule('../src/routes/locatorSlips');
    restoreAppEvents();
    restoreDb();
  }
}

const basePayload = {
  code: 'remote_work',
  label: 'Remote Work',
};

function repeated(length) {
  return 'x'.repeat(length);
}

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
  await withCreateRoute(async (handler, inserts, events) => {
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
    assert.equal(events.length, 1);
    assert.equal(events[0].name, 'locator_type_updated');
    assert.equal(events[0].payload.action, 'created');
    assert.equal(events[0].payload.code, 'remote_work');
  });
});

test('locator type creation rejects invalid codes and oversized text', async () => {
  await withCreateRoute(async (handler, inserts) => {
    const cases = [
      [{ code: '' }, /System code is required/],
      [{ code: 'a' }, /System code must be 2 to 64/],
      [{ code: `a${repeated(64)}` }, /System code must be 2 to 64/],
      [{ label: '' }, /Request type name is required/],
      [{ label: repeated(101) }, /Request type name must be 100 characters or less/],
      [{ short_label: repeated(41) }, /Short display name must be 40 characters or less/],
      [{ location_label: repeated(101) }, /Destination field name must be 100 characters or less/],
      [{ location_hint: repeated(201) }, /Destination placeholder must be 200 characters or less/],
      [{ dtr_slot_label: repeated(41) }, /DTR display text must be 40 characters or less/],
      [{ dtr_print_label: repeated(41) }, /DTR print text must be 40 characters or less/],
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

test('locator type creation accepts text at every maximum length', async () => {
  await withCreateRoute(async (handler, inserts) => {
    const res = responseRecorder();
    await handler({
      body: {
        code: `a${repeated(63)}`,
        label: repeated(100),
        short_label: repeated(40),
        location_label: repeated(100),
        location_hint: repeated(200),
        dtr_slot_label: repeated(40),
        dtr_print_label: repeated(40),
      },
    }, res);

    assert.equal(res.statusCode, 201);
    assert.equal(inserts.length, 1);
    assert.equal(inserts[0].params[0].length, 64);
    assert.equal(inserts[0].params[1].length, 100);
    assert.equal(inserts[0].params[2].length, 40);
    assert.equal(inserts[0].params[3].length, 100);
    assert.equal(inserts[0].params[4].length, 200);
    assert.equal(inserts[0].params[5].length, 40);
    assert.equal(inserts[0].params[6].length, 40);
  });
});

test('locator type update broadcasts the changed catalog entry', async () => {
  await withMutationRoute({ method: 'put' }, async (handler, events, existing) => {
    const res = responseRecorder();
    await handler({
      params: { id: existing.id },
      body: { label: 'Remote Work Updated' },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(events.length, 1);
    assert.equal(events[0].name, 'locator_type_updated');
    assert.equal(events[0].payload.action, 'updated');
    assert.equal(events[0].payload.locatorTypeId, existing.id);
  });
});

test('locator type removal broadcasts deactivation or deletion', async () => {
  await withMutationRoute(
    { method: 'delete', used: true },
    async (handler, events, existing) => {
      const res = responseRecorder();
      await handler({ params: { id: existing.id } }, res);

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.deleted, false);
      assert.equal(events[0].payload.action, 'deactivated');
      assert.equal(events[0].payload.isActive, false);
      assert.equal(events[0].payload.deleted, false);
    }
  );

  await withMutationRoute(
    { method: 'delete' },
    async (handler, events, existing) => {
      const res = responseRecorder();
      await handler({ params: { id: existing.id } }, res);

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.deleted, true);
      assert.equal(events[0].payload.action, 'deleted');
      assert.equal(events[0].payload.deleted, true);
    }
  );
});
