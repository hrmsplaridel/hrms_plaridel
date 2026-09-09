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
    if (res.statusCode < 400) {
      assert.ok(events.indexOf('QUEUE') < events.indexOf('COMMIT'));
      assert.ok(events.indexOf('COMMIT') < events.indexOf('BROADCAST'));
    } else {
      assert.equal(events.includes('WRITE'), false);
      assert.equal(events.includes('QUEUE'), false);
      assert.equal(events.includes('BROADCAST'), false);
    }
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
    const { coverage, ...body } = initial;
    const res = await request('post', { ...body, holiday_type: type });
    assert.equal(res.body.coverage, 'whole_day');
  }
});

test('API rejects string booleans instead of treating them as true', async () => {
  const res = await request('post', { ...initial, is_active: 'false' });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /is_active must be true or false/i);
});

test('API rejects blank names on partial updates', async () => {
  const res = await request('put', { name: '   ' });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /name must be a nonempty string/i);
});

test('API rejects unsupported holiday types and coverage values', async () => {
  const invalidType = await request('post', { ...initial, holiday_type: 'national' });
  assert.equal(invalidType.statusCode, 400);
  assert.match(invalidType.body.error, /holiday_type must be one of/i);

  const invalidCoverage = await request('put', { coverage: 'morning' });
  assert.equal(invalidCoverage.statusCode, 400);
  assert.match(invalidCoverage.body.error, /coverage must be one of/i);
});

test('API rejects partial coverage for regular and local holidays', async () => {
  const res = await request('post', { ...initial, holiday_type: 'regular', coverage: 'am_only' });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /coverage must be whole_day/i);
});

test('API rejects nonexistent calendar dates', async () => {
  const res = await request('post', {
    ...initial,
    date_from: '2026-02-30',
    date_to: '2026-02-30',
  });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /date_from must be a real date/i);
});

test('template rows reject invalid booleans, enums, and calendar dates', () => {
  assert.throws(
    () => normalizeTemplatePayload({ year: 2026, holidays: [{ ...initial, name: 123 }] }),
    /Holiday row 1 name must be a nonempty string/i
  );
  assert.throws(
    () => normalizeTemplatePayload({ year: 2026, holidays: [{ ...initial, recurring: 'false' }] }),
    /recurring must be true or false/i
  );
  assert.throws(
    () => normalizeTemplatePayload({ year: 2026, holidays: [{ ...initial, holiday_type: 'national' }] }),
    /holiday_type must be one of/i
  );
  assert.throws(
    () => normalizeTemplatePayload({
      year: 2026,
      holidays: [{ ...initial, date_from: '2026-02-30', date_to: '2026-02-30' }],
    }),
    /date_from must be a real date/i
  );
});

test('non-recurring template rows must use the labeled template year', () => {
  assert.throws(
    () => normalizeTemplatePayload({
      year: 2027,
      holidays: [{
        ...initial,
        date_from: '2026-09-09',
        date_to: '2026-09-09',
        recurring: false,
      }],
    }),
    /Holiday row 1 must use template year 2027 for both dates because it is non-recurring/i
  );
});

test('non-recurring template ranges cannot silently cross into another year', () => {
  assert.throws(
    () => normalizeTemplatePayload({
      year: 2027,
      holidays: [{
        ...initial,
        date_from: '2027-12-31',
        date_to: '2028-01-01',
        recurring: false,
      }],
    }),
    /Holiday row 1 must use template year 2027 for both dates/i
  );
});

test('recurring template rows retain their original month-day anchors', () => {
  const template = normalizeTemplatePayload({
    year: 2027,
    holidays: [{
      ...initial,
      date_from: '2024-12-31',
      date_to: '2025-01-01',
      recurring: true,
    }],
  });
  assert.equal(template.holidays[0].date_from, '2024-12-31');
  assert.equal(template.holidays[0].date_to, '2025-01-01');
});
