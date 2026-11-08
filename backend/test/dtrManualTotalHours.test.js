const test = require('node:test');
const assert = require('node:assert/strict');
const createControllers = require('../src/modules/dtr/controllers/create.controller');
const updateControllers = require('../src/modules/dtr/controllers/update.controller');
const { validateDtrPunchDates } = require('../src/services/dtrPunchDateValidation');
const { computeTotalHoursFromRecord } = require('../src/services/shiftAttendance');
const { computeTotalHours } = require('../src/modules/dtr/services/shifts')({ computeTotalHoursFromRecord });
const { dtrAuditSnapshot } = require('../src/modules/dtr/serializers/audit')({ toIsoDateStr: value => String(value).slice(0, 10) });

const ID = '11111111-1111-4111-8111-111111111111';
const DATE = '2026-10-01';
const stamp = (time, day = DATE) => `${day}T${time}:00+08:00`;
const day = { startMinutes: 480, endMinutes: 1020, breakStartMinutes: 720, breakEndMinutes: 780, punchMode: 'full_day' };
const night = { startMinutes: 1200, endMinutes: 420, punchMode: 'single_session', captureWindowMinutes: 120 };
const full = { time_in: stamp('08:00'), break_out: stamp('12:00'), break_in: stamp('13:00'), time_out: stamp('17:00') };

test.beforeEach(t => t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-11-02T04:00:00Z') }));

function fixture({ punches = full, shift = day, storedTotal = 900, snapshot = true, coverage = null, compute = computeTotalHours } = {}) {
  const calls = [], broadcasts = [];
  let row = { id: ID, employee_id: ID, attendance_date: DATE, attendance_date_iso: DATE,
    ...punches, total_hours: storedTotal, shift_snapshot: snapshot ? shift : null,
    holiday_id: null, status: 'present', source: 'system', remarks: null };
  const query = async (sql, params = []) => {
    calls.push({ sql, params });
    if (sql.includes('SELECT d.*')) return { rows: [{ ...row }] };
    if (sql.includes('INSERT INTO dtr_daily_summary')) {
      row = { ...row, employee_id: params[0], time_in: params[2], break_out: params[3],
        break_in: params[4], time_out: params[5], total_hours: params[6], status: params[9] };
      return { rows: [{ ...row }] };
    }
    if (sql.includes('UPDATE dtr_daily_summary SET')) {
      for (const match of sql.matchAll(/\b([a-z_]+)\s*=\s*\$(\d+)/g)) {
        row[match[1]] = params[Number(match[2]) - 1];
      }
      row.source = 'adjusted';
      return { rows: [{ ...row }] };
    }
    return { rows: [] };
  };
  const dependencies = {
    pool: { query, connect: async () => ({ query, release() {} }) },
    HRMS_TIMEZONE: 'Asia/Manila', todayInHrmsTimezone: () => '2026-11-02', validateDtrPunchDates,
    inclusiveIsoDateRangeDays: (from, to) => from === DATE && to === DATE ? 1 : null,
    getAssignmentShiftForDate: async () => shift,
    getApprovedLeaveCoverageForDate: async () => coverage, getHolidayByDate: async () => null,
    computeTotalHours: compute, computeStatusFromShift: async () => 'present', computePmLateStatus: async () => 'present',
    computeLateMinutes: async () => 0, computeUndertimeMinutes: async () => 0,
    applyAttendancePolicyPenalties: async () => ({ lateMinutes: 0, undertimeMinutes: 0 }),
    minutesFromMidnightInTimeZone: () => 780, minutesToTimeStr: () => '17:00',
    _holidaysHasCoverageColumn: async () => true, toIsoDateStr: value => String(value).slice(0, 10), dtrAuditSnapshot,
    broadcastBiometricUpdate: (...args) => broadcasts.push(args),
  };
  return {
    calls, broadcasts,
    async invoke(method, body = {}) {
      const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; return this; } };
      const req = { params: { id: ID }, user: { id: ID, role: 'admin' },
        body: method === 'create' ? { employee_id: ID, attendance_date: DATE, ...punches, ...body } : body };
      await (method === 'create' ? createControllers(dependencies).createRecord : updateControllers(dependencies).updateRecord)(req, res);
      return res;
    },
  };
}

for (const method of ['create', 'update']) {
  for (const total of [900, -1, '900junk', '1e309', NaN, Infinity, true, [900], { hours: 900 }, null, '', 8, '8.00']) {
    test(`${method} derives hours from punches regardless of client total ${JSON.stringify(total)}`, async () => {
      const f = fixture();
      const res = await f.invoke(method, { total_hours: total });
      assert.equal(res.code, method === 'create' ? 201 : 200);
      assert.equal(res.body.total_hours, 8);
      const write = f.calls.find(c => /INSERT INTO dtr_daily_summary|UPDATE dtr_daily_summary SET/.test(c.sql));
      assert.ok(write);
      if (method === 'create') assert.equal(write.params[6], 8);
      else {
        const totalParameter = /total_hours\s*=\s*\$(\d+)/.exec(write.sql);
        assert.equal(write.params[Number(totalParameter[1]) - 1], 8);
        const audit = f.calls.find(c => c.sql.includes('INSERT INTO audit_logs'));
        const detail = JSON.parse(audit.params[2]);
        assert.equal(detail.before.total_hours, 900);
        assert.equal(detail.after.total_hours, 8);
        assert.equal(f.calls.some(c => c.sql === 'COMMIT'), true);
      }
      assert.equal(f.broadcasts.length, 1);
    });
  }
}

const scenarios = [
  ['full day', day, full, 8],
  ['AM shift', { startMinutes: 480, endMinutes: 720, punchMode: 'am_only' },
    { time_in: stamp('08:00'), break_out: stamp('12:00'), break_in: null, time_out: null }, 4],
  ['PM shift', { startMinutes: 780, endMinutes: 1020, punchMode: 'pm_only' },
    { time_in: null, break_out: null, break_in: stamp('13:00'), time_out: stamp('17:00') }, 4],
  ['single session', { startMinutes: 480, endMinutes: 1020, punchMode: 'single_session' },
    { time_in: stamp('08:00'), break_out: null, break_in: null, time_out: stamp('17:00') }, 9],
  ['overnight', night, { time_in: stamp('20:00'), break_out: null, break_in: null, time_out: stamp('07:00', '2026-10-02') }, 11],
  ['overnight four punches', { ...night, punchMode: 'full_day', breakStartMinutes: 0, breakEndMinutes: 60 },
    { time_in: stamp('20:00'), break_out: stamp('00:00', '2026-10-02'), break_in: stamp('01:00', '2026-10-02'), time_out: stamp('07:00', '2026-10-02') }, 10],
  ['incomplete', day, { time_in: stamp('08:00'), break_out: null, break_in: null, time_out: null }, 0],
  ['late departure capped at scheduled end', day, { ...full, time_out: stamp('17:20') }, 8],
  ['early arrival capped at scheduled start', day, { ...full, time_in: stamp('07:00') }, 8],
];
for (const method of ['create', 'update']) {
  for (const [name, shift, punches, hours] of scenarios) {
    test(`${method} calculates scheduled ${name} hours`, async () => {
      const f = fixture({ shift, punches });
      const res = await f.invoke(method, method === 'update' ? { ...punches } : {});
      assert.equal(res.code, method === 'create' ? 201 : 200);
      assert.equal(res.body.total_hours, hours);
    });
  }
  test(`${method} rejects an actual punch duration longer than 24 hours before writes`, async () => {
    const punches = { time_in: stamp('04:00'), break_out: null, break_in: null, time_out: stamp('06:00', '2026-10-02') };
    const f = fixture({ shift: night, punches });
    const res = await f.invoke(method, method === 'update' ? { ...punches } : {});
    assert.equal(res.code, 400);
    assert.match(res.body.error, /total hours|24 hours/i);
    assert.equal(f.calls.some(c => /INSERT INTO dtr_daily_summary|UPDATE dtr_daily_summary SET|INSERT INTO audit_logs|COMMIT/.test(c.sql)), false);
    if (method === 'update') assert.equal(f.calls.some(c => c.sql === 'ROLLBACK'), true);
    assert.deepEqual(f.broadcasts, []);
  });
  test(`${method} accepts a measured duration at the 24-hour ceiling but credits only the shift`, async () => {
    const punches = { time_in: stamp('07:00'), break_out: null, break_in: null, time_out: stamp('07:00', '2026-10-02') };
    const f = fixture({ shift: night, punches });
    const res = await f.invoke(method, method === 'update' ? { ...punches } : {});
    assert.equal(res.code, method === 'create' ? 201 : 200);
    assert.equal(res.body.total_hours, 11);
  });
  test(`${method} fails closed if the duration calculation returns a nonfinite number`, async () => {
    const f = fixture({ compute: () => NaN });
    const res = await f.invoke(method, method === 'update' ? { time_out: stamp('17:00') } : {});
    assert.equal(res.code, 400);
    assert.equal(f.calls.some(c => /INSERT INTO dtr_daily_summary|UPDATE dtr_daily_summary SET|INSERT INTO audit_logs|COMMIT/.test(c.sql)), false);
    assert.deepEqual(f.broadcasts, []);
  });
}

test('partial update merges changed punches with locked existing punches', async () => {
  const f = fixture();
  const res = await f.invoke('update', { time_out: stamp('18:00'), total_hours: 8 });
  assert.equal(res.code, 200);
  assert.equal(res.body.total_hours, 8);
});

test('update without a saved shift snapshot derives hours from the resolved assignment shift', async () => {
  const f = fixture({ snapshot: false });
  const res = await f.invoke('update', { total_hours: 900 });
  assert.equal(res.code, 200);
  assert.equal(res.body.total_hours, 8);
});

test('clearing punches recomputes zero instead of keeping a client total', async () => {
  const f = fixture();
  const res = await f.invoke('update', { time_in: null, break_out: null, break_in: null, time_out: null, total_hours: 900 });
  assert.equal(res.code, 200);
  assert.equal(res.body.total_hours, 0);
});

test('remarks-only updates do not silently rewrite historical totals', async () => {
  const f = fixture();
  const res = await f.invoke('update', { remarks: 'HR verified the original record' });
  assert.equal(res.code, 200);
  const write = f.calls.find(c => c.sql.includes('UPDATE dtr_daily_summary SET'));
  assert.doesNotMatch(write.sql, /total_hours\s*=/);
  assert.equal(res.body.total_hours, 900);
});

test('approved leave still prevents ordinary attendance edits', async () => {
  const f = fixture({ coverage: { leave_request_id: ID } });
  const res = await f.invoke('update', { total_hours: 900 });
  assert.equal(res.code, 409);
  assert.equal(f.calls.some(c => /UPDATE dtr_daily_summary SET|INSERT INTO audit_logs|COMMIT/.test(c.sql)), false);
});

test('duration validation failure rolls back before editing attendance under leave coverage', async () => {
  const f = fixture({ coverage: { leave_request_id: ID }, compute: () => Infinity });
  const res = await f.invoke('update', { time_out: stamp('17:00'), edit_underlying_attendance: true });
  assert.equal(res.code, 400);
  assert.equal(f.calls.some(c => c.sql === 'ROLLBACK'), true);
  assert.equal(f.calls.some(c => /UPDATE dtr_daily_summary SET|INSERT INTO audit_logs|COMMIT/.test(c.sql)), false);
});
