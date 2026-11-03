const test = require('node:test');
const assert = require('node:assert/strict');
const createControllers = require('../src/modules/leave/controllers/administration.controller');

function fixture() {
  const calls = [];
  const record = (name, result) => async (...args) => {
    calls.push({ name, args });
    return typeof result === 'function' ? result(...args) : result;
  };
  const controllers = createControllers({
    pool: {
      query: record('query', { rows: [] }),
      connect: record('connect', {}),
    },
    yearEndManilaYearNow: () => 2026,
    notificationMonthForTarget: () => '2026-10',
    runLeaveMonthlyAccrual: record('accrual', (_, options) => ({
      dryRun: options.dryRun, targetYearMonth: '2026-10', details: [], rowsUpdated: 0,
    })),
    runMonthlyAttendanceDeductions: record('attendance', { details: [] }),
    applyYearEndForcedLeaveDeductions: record('yearEnd', { summary: { applied: 0 } }),
    notifyLeaveMonthEnd: record('notify'),
    notifyLeaveMonthEndFailure: record('notifyFailure'),
    broadcastAppEvent: record('broadcast'),
    broadcastLeaveUpdated: record('broadcastLeave'),
  });
  return {
    calls,
    async invoke(handler, { body = {}, query = {} } = {}) {
      const response = {
        statusCode: 200,
        status(code) { this.statusCode = code; return this; },
        json(value) { this.body = value; return this; },
      };
      await controllers[handler]({
        user: { id: 'admin' }, body: { year: 2025, target_month: '2026-10', ...body }, query,
      }, response);
      return response;
    },
  };
}

for (const handler of ['runMonthlyAccrual', 'applyYearEndForcedLeave']) {
  for (const field of ['dry_run', 'dryRun']) {
    for (const value of ['true', 'false', 1, 0, null, [], {}, '']) {
      test(`${handler} rejects body ${field}=${JSON.stringify(value)} before any work`, async () => {
        const f = fixture();
        const result = await f.invoke(handler, { body: { [field]: value } });
        assert.equal(result.statusCode, 400);
        assert.match(result.body.error, /dry_run.*boolean/i);
        assert.deepEqual(f.calls, [], 'No processing, database, notification or broadcast calls');
      });
    }
    for (const value of [true, 1, null, [], ['true'], {}, '', 'yes', 'TRUE']) {
      test(`${handler} rejects query ${field}=${JSON.stringify(value)} before any work`, async () => {
        const f = fixture();
        const result = await f.invoke(handler, { query: { [field]: value } });
        assert.equal(result.statusCode, 400);
        assert.match(result.body.error, /dry_run/i);
        assert.deepEqual(f.calls, []);
      });
    }
  }

  for (const input of [
    { body: { dry_run: true, dryRun: false } },
    { body: { dry_run: false, dryRun: true } },
    { body: { dry_run: true }, query: { dry_run: 'false' } },
    { body: { dryRun: false }, query: { dry_run: '1' } },
    { query: { dry_run: 'true', dryRun: '0' } },
  ]) {
    test(`${handler} rejects conflicting flags ${JSON.stringify(input)}`, async () => {
      const f = fixture();
      const result = await f.invoke(handler, input);
      assert.equal(result.statusCode, 400);
      assert.match(result.body.error, /conflict/i);
      assert.deepEqual(f.calls, []);
    });
  }

  for (const [input, expected] of [
    [{}, false],
    [{ body: { dry_run: true } }, true],
    [{ body: { dry_run: false } }, false],
    [{ body: { dryRun: true } }, true],
    [{ body: { dryRun: false } }, false],
    [{ query: { dry_run: 'true' } }, true],
    [{ query: { dry_run: '1' } }, true],
    [{ query: { dry_run: 'false' } }, false],
    [{ query: { dry_run: '0' } }, false],
    [{ query: { dryRun: 'true' } }, true],
    [{ query: { dryRun: 'false' } }, false],
    [{ body: { dry_run: true, dryRun: true }, query: { dry_run: '1' } }, true],
    [{ body: { dry_run: false }, query: { dry_run: 'false', dryRun: '0' } }, false],
  ]) {
    test(`${handler} preserves valid preview/apply ${JSON.stringify(input)}`, async () => {
      const f = fixture();
      const result = await f.invoke(handler, input);
      assert.equal(result.statusCode, handler === 'runMonthlyAccrual' || expected ? 200 : 201);
      const processing = f.calls.filter(c => ['accrual', 'attendance', 'yearEnd'].includes(c.name));
      assert.equal(processing.length, handler === 'runMonthlyAccrual' ? 2 : 1);
      for (const call of processing) assert.equal(call.args[1].dryRun, expected);
      assert.equal(f.calls.some(c => c.name === 'notifyFailure'), false);
      if (expected) {
        assert.equal(f.calls.some(c => c.name.startsWith('broadcast')), false);
      }
    });
  }
}

for (const location of ['body', 'query']) {
  for (const value of [null, '', true, false, [], [2], {}, 0, -1, 121, 1.5, '12garbage', '1e2', 'Infinity']) {
    test(`month-end rejects ${location} catch-up=${JSON.stringify(value)} before processing`, async () => {
      const f = fixture();
      const result = await f.invoke('runMonthlyAccrual', {
        body: { dry_run: true, ...(location === 'body' ? { max_catch_up_months: value } : {}) },
        query: location === 'query' ? { max_catch_up_months: value } : {},
      });
      assert.equal(result.statusCode, 400);
      assert.match(result.body.error, /max_catch_up_months.*1.*120/i);
      assert.deepEqual(f.calls, []);
    });
  }
}

for (const value of [1, 120, '1', '120', ' 12 ']) {
  test(`month-end accepts valid catch-up ${JSON.stringify(value)}`, async () => {
    const f = fixture();
    const result = await f.invoke('runMonthlyAccrual', {
      body: { dry_run: true, max_catch_up_months: value },
    });
    assert.equal(result.statusCode, 200);
    assert.equal(f.calls.find(c => c.name === 'accrual').args[1].maxCatchUpMonths, Number(value));
  });
}

test('month-end rejects an invalid query limit even when a valid body limit is supplied', async () => {
  const f = fixture();
  const result = await f.invoke('runMonthlyAccrual', {
    body: { dry_run: false, max_catch_up_months: 1 }, query: { max_catch_up_months: '2junk' },
  });
  assert.equal(result.statusCode, 400);
  assert.deepEqual(f.calls, []);
});

test('month-end rejects conflicting catch-up limits', async () => {
  const f = fixture();
  const result = await f.invoke('runMonthlyAccrual', {
    body: { dry_run: false, max_catch_up_months: 1 }, query: { max_catch_up_months: '2' },
  });
  assert.equal(result.statusCode, 400);
  assert.match(result.body.error, /conflict/i);
  assert.deepEqual(f.calls, []);
});

test('month-end keeps the service default when catch-up is omitted', async () => {
  const f = fixture();
  assert.equal((await f.invoke('runMonthlyAccrual')).statusCode, 200);
  assert.equal(f.calls.find(c => c.name === 'accrual').args[1].maxCatchUpMonths, undefined);
});

test('year-end still blocks live processing of an unclosed year but allows preview', async () => {
  const live = fixture();
  assert.equal((await live.invoke('applyYearEndForcedLeave', { body: { year: 2026, dry_run: false } })).statusCode, 409);
  assert.deepEqual(live.calls, []);
  const preview = fixture();
  assert.equal((await preview.invoke('applyYearEndForcedLeave', { body: { year: 2026, dry_run: true } })).statusCode, 200);
  assert.equal(preview.calls.find(c => c.name === 'yearEnd').args[1].dryRun, true);
});
