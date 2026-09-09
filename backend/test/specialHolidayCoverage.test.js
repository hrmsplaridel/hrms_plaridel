'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
const { normalizeTemplatePayload } = require('../src/services/holidayDefaultTemplates');

const initial = {
  id: '11111111-1111-4111-8111-111111111111', name: 'Special AM holiday',
  date_from: '2026-09-09', date_to: '2026-09-09',
  holiday_type: 'special', coverage: 'am_only', is_active: true, recurring: false,
};

async function request(method, body) {
  let stored = { ...initial };
  const events = [];
  let released = false;
  const client = {
    async query(sql, params = []) {
      const text = String(sql).trim();
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(text)) {
        events.push(text);
        return { rows: [], rowCount: 0 };
      }
      if (text.startsWith('SELECT')) return { rows: [{ ...stored }], rowCount: 1 };
      if (text.startsWith('INSERT INTO holidays')) {
        const fields = ['date_from', 'date_to', 'name', 'holiday_type', 'description', 'is_active', 'recurring', 'coverage'];
        fields.forEach((field, index) => { stored[field] = params[index]; });
      } else if (text.startsWith('UPDATE holidays')) {
        for (const match of text.split(' WHERE ')[0].matchAll(/(\w+) = \$(\d+)/g)) {
          stored[match[1]] = params[Number(match[2]) - 1];
        }
      } else throw new Error(`Unexpected query: ${text}`);
      events.push('WRITE');
      return { rows: [{ ...stored }], rowCount: 1 };
    },
    release() { released = true; },
  };
  const restores = [
    withMockedModule('../src/config/db', { pool: { connect: async () => client } }),
    withMockedModule('../src/services/dtrMonthEndReconciliation', {
      enqueueHolidayReconciliation: async (db) => { assert.equal(db, client); events.push('QUEUE'); },
    }),
    withMockedModule('../src/websockets/biometricStream', {
      broadcastBiometricUpdate: () => events.push('BROADCAST'),
    }),
  ];
  const path = '../src/routes/holidays';
  clearModule(path);
  const res = {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
  try {
    const router = require(path);
    const route = router.stack.find((entry) => entry.route?.path === (method === 'post' ? '/' : '/:id') && entry.route.methods[method]);
    await route.route.stack.at(-1).handle({ body, params: { id: initial.id } }, res);
    assert.equal(released, true);
    assert.ok(events.indexOf('QUEUE') < events.indexOf('COMMIT'));
    assert.ok(events.indexOf('COMMIT') < events.indexOf('BROADCAST'));
    return res;
  } finally {
    clearModule(path);
    restores.reverse().forEach((restore) => restore());
  }
}

for (const coverage of ['am_only', 'pm_only', 'whole_day']) {
  test(`special holiday creation preserves ${coverage}`, async () => {
    const res = await request('post', { ...initial, coverage });
    assert.equal(res.statusCode, 201);
    assert.equal(res.body.coverage, coverage);
  });
  test(`special holiday update preserves ${coverage}`, async () => {
    const res = await request('put', { coverage });
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.coverage, coverage);
  });
  test(`special holiday template preserves ${coverage}`, () => {
    const template = normalizeTemplatePayload({ year: 2026, holidays: [{ ...initial, coverage }] });
    assert.equal(template.holidays[0].coverage, coverage);
  });
}

test('new special holiday without coverage defaults to whole day', async () => {
  const { coverage, ...body } = initial;
  const res = await request('post', body);
  assert.equal(res.body.coverage, 'whole_day');
});

test('description-only API edit keeps existing AM-only special holiday', async () => {
  const res = await request('put', { description: 'Updated wording' });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.coverage, 'am_only');
});

test('regular/local creation rules remain unchanged', async () => {
  for (const type of ['regular', 'local']) {
    const res = await request('post', { ...initial, holiday_type: type });
    assert.equal(res.body.coverage, 'whole_day');
  }
});
