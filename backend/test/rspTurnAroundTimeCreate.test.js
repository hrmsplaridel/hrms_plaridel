const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
const { validateTurnAroundTimeCreate } = require('../src/services/rspTurnAroundTimeCreate');

test('create validation rejects missing, null, non-string, and blank position or office', () => {
  const missing = validateTurnAroundTimeCreate({});
  assert.equal(missing.ok, false);
  assert.equal(missing.status, 400);
  assert.equal(missing.fields.position, 'Position is required.');
  assert.equal(missing.fields.office, 'Office is required.');

  const nulls = validateTurnAroundTimeCreate({ position: null, office: null });
  assert.equal(nulls.fields.position, 'Position is required.');
  assert.equal(nulls.fields.office, 'Office is required.');

  const typed = validateTurnAroundTimeCreate({ position: 12, office: ['HR'] });
  assert.equal(typed.fields.position, 'Position is required.');
  assert.equal(typed.fields.office, 'Office is required.');

  const blank = validateTurnAroundTimeCreate({ position: '   ', office: '\n\t' });
  assert.equal(blank.fields.position, 'Position is required.');
  assert.equal(blank.fields.office, 'Office is required.');

  const officeOnly = validateTurnAroundTimeCreate({ position: 'IT Coder', office: ' ' });
  assert.equal(officeOnly.fields.position, undefined);
  assert.equal(officeOnly.fields.office, 'Office is required.');
});

test('create validation trims a valid position and office', () => {
  const result = validateTurnAroundTimeCreate({
    position: '  IT Coder  ',
    office: '  Office of the Municipal Mayor  ',
    applicants: [{ name: 'Kept' }],
  });
  assert.equal(result.ok, true);
  assert.equal(result.position, 'IT Coder');
  assert.equal(result.office, 'Office of the Municipal Mayor');
});

test.describe('turn-around time create route', () => {
  const log = { connects: 0, calls: [] };
  let restoreDb;
  let restoreSignatures;
  let router;

  function resetLog() {
    log.connects = 0;
    log.calls = [];
  }

  test.before(() => {
    restoreDb = withMockedModule('../src/config/db', {
      pool: {
        query: async () => ({ rows: [], rowCount: 0 }),
        connect: async () => {
          log.connects += 1;
          return {
            query: async (sql, params) => {
              log.calls.push({ sql: String(sql), params });
              if (String(sql).includes('INSERT')) {
                return {
                  rows: [{ id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', ...(params ? {} : {}) }],
                  rowCount: 1,
                };
              }
              if (String(sql).includes('UPDATE')) {
                return { rows: [{ id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' }], rowCount: 1 };
              }
              return { rows: [], rowCount: 0 };
            },
            release() {},
          };
        },
      },
    });
    restoreSignatures = withMockedModule('../src/services/docutrackerRspSignatureService', {
      creatorOwnedSlotKeys: () => [],
      initializeCreatorSourceSignatures: async () => {},
    });
    clearModule('../src/routes/rspLdSavedEntries');
    router = require('../src/routes/rspLdSavedEntries');
  });

  test.after(() => {
    clearModule('../src/routes/rspLdSavedEntries');
    restoreSignatures();
    restoreDb();
  });

  function handlers(method, path) {
    const layer = router.stack.find(
      (item) => item.route && item.route.path === path && item.route.methods[method],
    );
    assert.ok(layer, `${method.toUpperCase()} ${path} was not registered`);
    return layer.route.stack.map((item) => item.handle);
  }

  async function invoke(method, path, req) {
    const res = {
      statusCode: 200,
      payload: null,
      status(code) {
        this.statusCode = code;
        return this;
      },
      json(body) {
        this.payload = body;
        return this;
      },
    };
    for (const handler of handlers(method, path)) {
      await handler({ user: { id: '11111111-1111-4111-8111-111111111111' }, ...req }, res);
    }
    return res;
  }

  test('POST without position or office does not insert a row', async () => {
    resetLog();
    const res = await invoke('post', '/:table', {
      params: { table: 'turn_around_time_entries' },
      body: { applicants: [{ name: 'Typed name' }] },
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.payload.fields.position, 'Position is required.');
    assert.equal(res.payload.fields.office, 'Office is required.');
    assert.equal(log.connects, 0);
    assert.equal(log.calls.some((call) => call.sql.includes('INSERT')), false);
  });

  test('POST rejects null and whitespace-only values before insert', async () => {
    resetLog();
    const missing = await invoke('post', '/:table', {
      params: { table: 'turn_around_time_entries' },
      body: { position: null, office: null },
    });
    assert.equal(missing.statusCode, 400);
    assert.equal(log.connects, 0);

    const blank = await invoke('post', '/:table', {
      params: { table: 'turn_around_time_entries' },
      body: { position: '   ', office: '  ' },
    });
    assert.equal(blank.statusCode, 400);
    assert.equal(blank.payload.fields.position, 'Position is required.');
    assert.equal(blank.payload.fields.office, 'Office is required.');
    assert.equal(log.connects, 0);
  });

  test('POST with position and office trims both and inserts', async () => {
    resetLog();
    const res = await invoke('post', '/:table', {
      params: { table: 'turn_around_time_entries' },
      body: {
        position: '  IT Coder  ',
        office: '  Office of the Municipal Mayor  ',
        applicants: [],
      },
    });
    assert.equal(res.statusCode, 201);
    assert.equal(log.connects, 1);
    const insert = log.calls.find((call) => call.sql.includes('INSERT'));
    assert.ok(insert);
    assert.deepEqual(insert.params.slice(0, 2), [
      'IT Coder',
      'Office of the Municipal Mayor',
    ]);
  });

  test('PUT still accepts a historical row with blank position and office', async () => {
    resetLog();
    const res = await invoke('put', '/:table/:id', {
      params: {
        table: 'turn_around_time_entries',
        id: '3c4d87b9-4eed-420c-aec6-fb02b79f66b5',
      },
      body: {
        position: null,
        office: null,
        applicants: [{ name: 'Code Crafters VI' }],
      },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.payload && res.payload.code, undefined);
    assert.equal(log.calls.some((call) => call.sql.includes('UPDATE')), true);
    const update = log.calls.find((call) => call.sql.includes('UPDATE'));
    assert.equal(update.params[0], null);
    assert.equal(update.params[1], null);
  });

  test('other saved-entry creates do not require position or office', async () => {
    resetLog();
    const res = await invoke('post', '/:table', {
      params: { table: 'training_need_analysis_entries' },
      body: { cy_year: '2026', department: 'HRMO' },
    });
    assert.equal(res.statusCode, 201);
    assert.equal(res.payload && res.payload.code, undefined);
    assert.equal(log.calls.some((call) => call.sql.includes('INSERT')), true);
  });
});
