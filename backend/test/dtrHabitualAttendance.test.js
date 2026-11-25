const test = require('node:test');
const assert = require('node:assert/strict');
const {
  HABITUAL_MONTHLY_THRESHOLD,
  countMonthlyInstances,
  evaluateHabitual,
} = require('../src/modules/dtr/policies/habitualAttendance');
const createControllers = require('../src/modules/dtr/controllers/habitualAttendance.controller');

const EMP_A = '00000000-0000-4000-8000-000000000501';
const EMP_B = '00000000-0000-4000-8000-000000000502';

function months(entries) {
  const counts = Array(12).fill(0);
  for (const [month, count] of Object.entries(entries)) counts[Number(month) - 1] = count;
  return counts;
}

test('threshold follows CSC rule of ten instances a month', () => {
  assert.equal(HABITUAL_MONTHLY_THRESHOLD, 10);
});

test('two qualifying months in the same semester are habitual', () => {
  const result = evaluateHabitual(months({ 2: 10, 4: 12 }));
  assert.deepEqual(result.qualifying_months, [2, 4]);
  assert.equal(result.habitual, true);
});

test('two consecutive qualifying months across semesters are habitual', () => {
  assert.equal(evaluateHabitual(months({ 6: 10, 7: 11 })).habitual, true);
});

test('qualifying months in different semesters and not consecutive are not habitual', () => {
  const result = evaluateHabitual(months({ 5: 15, 8: 15 }));
  assert.deepEqual(result.qualifying_months, [5, 8]);
  assert.equal(result.habitual, false);
});

test('months below ten instances never qualify', () => {
  const result = evaluateHabitual(months({ 1: 9, 2: 9, 3: 9 }));
  assert.deepEqual(result.qualifying_months, []);
  assert.equal(result.habitual, false);
});

test('counts tardy and undertime days only on worked days with punches', () => {
  const punched = { time_in: '2026-03-02T00:10:00Z', time_out: '2026-03-02T09:00:00Z' };
  const counts = countMonthlyInstances([
    { record_date: '2026-03-02', status: 'late', late_minutes: 5, undertime_minutes: 0, ...punched },
    { record_date: '2026-03-03', status: 'present', late_minutes: 1, undertime_minutes: 30, ...punched },
    { record_date: '2026-03-04', status: 'absent', late_minutes: 0, undertime_minutes: 480 },
    { record_date: '2026-03-05', status: 'holiday', late_minutes: 0, undertime_minutes: 240 },
    { record_date: '2026-03-06', status: 'on_leave', late_minutes: 7, undertime_minutes: 0, ...punched },
    { record_date: '2026-03-09', status: 'incomplete', late_minutes: 3, undertime_minutes: 200,
      time_in: '2026-03-09T00:05:00Z', time_out: null },
    { record_date: '2026-04-01', status: 'present', late_minutes: 0, undertime_minutes: 15, ...punched },
  ]);
  assert.equal(counts.tardiness[2], 3);
  assert.equal(counts.undertime[2], 1);
  assert.equal(counts.undertime[3], 1);
});

function lateRows(employeeId, name, month, count) {
  return Array.from({ length: count }, (_, i) => {
    const date = `2026-${String(month).padStart(2, '0')}-${String(i + 1).padStart(2, '0')}`;
    return {
      user_id: employeeId, employee_name: name, record_date: date, status: 'late',
      late_minutes: 4, undertime_minutes: 0,
      time_in: `${date}T00:04:00Z`, time_out: `${date}T09:00:00Z`,
    };
  });
}

function response() {
  return {
    statusCode: 200,
    payload: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.payload = body; return this; },
  };
}

test('report runs the completed DTR month by month through today and lists flagged employees', async () => {
  const calls = [];
  const { getHabitualAttendance } = createControllers({
    todayInHrmsTimezone: () => '2026-04-15',
    async listDtrDailySummaries(req, res) {
      calls.push({ ...req.query, bulkReport: req.bulkReport });
      const month = Number(req.query.start_date.slice(5, 7));
      const rows = [];
      if (month === 2 || month === 3) rows.push(...lateRows(EMP_A, 'Ana Late', month, 10));
      if (month === 1) rows.push(...lateRows(EMP_B, 'Ben Once', month, 11));
      if (month === 2) rows.push(...lateRows(EMP_B, 'Ben Once', month, 2));
      res.json(rows);
    },
  });
  const res = response();
  await getHabitualAttendance(
    { user: { id: EMP_A, role: 'hr' }, query: { year: '2026', department_id: 'dept-1' } },
    res
  );

  assert.equal(res.statusCode, 200);
  assert.deepEqual(
    calls.map((c) => [c.start_date, c.end_date]),
    [
      ['2026-01-01', '2026-01-31'],
      ['2026-02-01', '2026-02-28'],
      ['2026-03-01', '2026-03-31'],
      ['2026-04-01', '2026-04-15'],
    ]
  );
  assert.ok(calls.every((c) => c.recompute === 'true' && c.bulkReport === true));
  assert.ok(calls.every((c) => c.department_id === 'dept-1'));
  assert.equal(res.payload.year, 2026);
  assert.equal(res.payload.through, '2026-04-15');
  assert.equal(res.payload.threshold, 10);
  assert.deepEqual(res.payload.employees.map((e) => e.employee_id), [EMP_A, EMP_B]);
  const [ana, ben] = res.payload.employees;
  assert.equal(ana.employee_name, 'Ana Late');
  assert.equal(ana.tardiness.habitual, true);
  assert.deepEqual(ana.tardiness.qualifying_months, [2, 3]);
  assert.equal(ana.tardiness.monthly[1], 10);
  assert.equal(ana.undertime.habitual, false);
  assert.equal(ben.tardiness.habitual, false);
  assert.deepEqual(ben.tardiness.qualifying_months, [1]);
});

test('report rejects invalid and future years', async () => {
  const { getHabitualAttendance } = createControllers({
    todayInHrmsTimezone: () => '2026-04-15',
    async listDtrDailySummaries() { throw new Error('should not run'); },
  });
  for (const year of ['abc', '1899', '2027']) {
    const res = response();
    await getHabitualAttendance({ user: { role: 'admin' }, query: { year } }, res);
    assert.equal(res.statusCode, 400, year);
  }
});

test('report surfaces pipeline errors', async () => {
  const { getHabitualAttendance } = createControllers({
    todayInHrmsTimezone: () => '2026-04-15',
    async listDtrDailySummaries(req, res) { res.status(400).json({ error: 'bad range' }); },
  });
  const res = response();
  await getHabitualAttendance({ user: { role: 'admin' }, query: { year: '2026' } }, res);
  assert.equal(res.statusCode, 400);
  assert.equal(res.payload.error, 'bad range');
});
