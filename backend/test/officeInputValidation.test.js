const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const ID = '11111111-1111-4111-8111-111111111111';

async function invoke(method, body, { error, missing = false } = {}) {
  const calls = [];
  const restore = withMockedModule('../src/config/db', { pool: {
    async query(sql, params = []) {
      calls.push({ sql, params });
      if (error) throw Object.assign(new Error('Database error'), { code: error });
      return { rowCount: missing ? 0 : 1, rows: missing ? [] : [{ id: ID }] };
    },
  } });
  clearModule('../src/routes/offices');
  try {
    const router = require('../src/routes/offices');
    const path = method === 'post' ? '/' : '/:id';
    const handler = router.stack.find(layer => layer.route?.path === path && layer.route.methods[method]).route.stack.at(-1).handle;
    const res = { code: 200, status(code) { this.code = code; return this; }, json(data) { this.body = data; return this; } };
    await handler({ body, params: { id: ID } }, res);
    return { res, calls };
  } finally {
    clearModule('../src/routes/offices');
    restore();
  }
}

for (const method of ['post', 'put']) {
  for (const [field, values] of [
    ['name', ['', '  ', null, false, 123, [], {}, ['Office']]],
    ['is_active', ['false', 'true', '', 0, 1, null, [], {}]],
    ['description', [123, false, [], {}]],
  ]) {
    for (const value of values) {
      test(`${method} offices rejects invalid ${field}: ${JSON.stringify(value)}`, async t => {
        t.mock.method(console, 'error', () => {});
        const { res, calls } = await invoke(method, { name: 'Municipal Hall', [field]: value });
        assert.equal(res.code, 400);
        assert.match(res.body.error, new RegExp(field === 'is_active' ? 'is_active|active' : field, 'i'));
        assert.deepEqual(calls, [], 'Invalid input must not reach the database');
      });
    }
  }
  for (const body of [null, [], 'Office', 123]) {
    test(`${method} offices rejects malformed body: ${JSON.stringify(body)}`, async t => {
      t.mock.method(console, 'error', () => {});
      const { res, calls } = await invoke(method, body);
      assert.equal(res.code, 400);
      assert.deepEqual(calls, []);
    });
  }
  for (const is_active of [true, false]) {
    test(`${method} offices preserves valid trimmed fields and boolean ${is_active}`, async () => {
      const { res, calls } = await invoke(method, { name: '  Municipal Hall  ', description: '  Main office  ', is_active });
      assert.equal(res.code, method === 'post' ? 201 : 200);
      assert.equal(calls.length, 1);
      assert.deepEqual(calls[0].params, method === 'post'
        ? ['Municipal Hall', 'Main office', is_active]
        : ['Municipal Hall', 'Main office', is_active, ID]);
    });
  }
  for (const description of [null, '', '   ']) {
    test(`${method} offices permits clearing description: ${JSON.stringify(description)}`, async () => {
      const { res, calls } = await invoke(method, { name: 'Office', description });
      assert.equal(res.code, method === 'post' ? 201 : 200);
      assert.equal(calls[0].params[1], null);
    });
  }
  test(`${method} offices retains duplicate-name conflict response`, async () => {
    const { res, calls } = await invoke(method, { name: 'Office' }, { error: '23505' });
    assert.equal(res.code, 409);
    assert.match(res.body.error, /already exists/i);
    assert.equal(calls.length, 1);
  });
}

test('office creation requires a name before querying', async () => {
  const { res, calls } = await invoke('post', {});
  assert.equal(res.code, 400);
  assert.deepEqual(calls, []);
});

test('office creation defaults to active with no description', async () => {
  const { res, calls } = await invoke('post', { name: 'Office' });
  assert.equal(res.code, 201);
  assert.deepEqual(calls[0].params, ['Office', null, true]);
  assert.match(calls[0].sql, /office_number/);
});

for (const [body, expected] of [
  [{ name: '  New name  ' }, ['New name', ID]],
  [{ description: null }, [null, ID]],
  [{ description: '  Updated description  ' }, ['Updated description', ID]],
  [{ is_active: false }, [false, ID]],
]) {
  test(`office partial update changes only supplied fields: ${JSON.stringify(body)}`, async () => {
    const { res, calls } = await invoke('put', body);
    assert.equal(res.code, 200);
    assert.deepEqual(calls[0].params, expected);
    const assignments = calls[0].sql.match(/SET (.*?) WHERE/)[1];
    assert.equal(assignments, `${Object.keys(body)[0]} = $1`);
  });
}

for (const body of [{}, { unrelated: true }]) {
  test(`office update rejects no supported fields: ${JSON.stringify(body)}`, async () => {
    const { res, calls } = await invoke('put', body);
    assert.equal(res.code, 400);
    assert.match(res.body.error, /No fields to update/);
    assert.deepEqual(calls, []);
  });
}

test('office update retains missing-office response', async () => {
  const { res } = await invoke('put', { name: 'Office' }, { missing: true });
  assert.equal(res.code, 404);
});
