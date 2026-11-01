const test = require('node:test');
const assert = require('node:assert/strict');
const { parseLocatorDateOnly, resolveLocatorShiftCoverage, validateLocatorWorkingDayForEmployee } = require('../src/services/locatorFilingRules');

const day = parseLocatorDateOnly('2026-11-02');
const assignment = { shift_id: 'shift', shift_name: 'Day shift', working_days: [1,2,3,4,5], punch_mode: 'full_day', start_time: '08:00', end_time: '17:00', break_end: '13:00' };
function database(holidays = [], shift = assignment) {
  return { async query(sql, params) {
    if (sql.includes('FROM assignments a')) return { rows: [shift] };
    assert.match(sql, /FROM holidays/);
    assert.match(sql, /is_active = true/);
    assert.deepEqual(params, [day.dateStr, day.dateStr]);
    return { rows: holidays };
  } };
}
function holiday(coverage, extra = {}) {
  return { id: 'holiday', name: 'Local holiday', date_from: day.dateStr, date_to: day.dateStr, recurring: false, coverage, ...extra };
}

for (const rows of [
  [holiday('whole_day')],
  [holiday('whole_day', { recurring: true, date_from: '2020-11-02', date_to: '2020-11-02' })],
  [holiday('am_only'), holiday('pm_only', { id: 'afternoon' })],
  [holiday('whole_day', { date_from: '2026-11-01', date_to: '2026-11-03' })],
]) {
  test(`locator rejects holiday coverage: ${JSON.stringify(rows)}`, async () => {
    const db = database(rows);
    const info = await resolveLocatorShiftCoverage(db, 'employee', day);
    assert.equal(info.can_file, false);
    assert.deepEqual(info.allowed_slots, []);
    assert.match(info.error, /holiday.*No locator coverage is required/i);
    const result = await validateLocatorWorkingDayForEmployee(db, 'employee', day, { amIn: true });
    assert.equal(result.ok, false);
    assert.equal(result.error, info.error);
  });
}
for (const [coverage, slots, good, bad] of [
  ['am_only', ['pm_in','pm_out'], { pmIn: true, pmOut: true }, { amIn: true, pmOut: true }],
  ['pm_only', ['am_in','am_out'], { amIn: true, amOut: true }, { amOut: true, pmIn: true }],
]) {
  test(`${coverage} holiday allows only the remaining working slots`, async () => {
    const db = database([holiday(coverage)]);
    const info = await resolveLocatorShiftCoverage(db, 'employee', day);
    assert.equal(info.can_file, true);
    assert.deepEqual(info.allowed_slots, slots);
    assert.equal((await validateLocatorWorkingDayForEmployee(db, 'employee', day, good)).ok, true);
    const rejected = await validateLocatorWorkingDayForEmployee(db, 'employee', day, bad);
    assert.equal(rejected.ok, false);
    assert.match(rejected.error, /holiday|working portion/i);
  });
}
test('partial holiday does not invent a working afternoon for a morning-only shift', async () => {
  const db = database([holiday('am_only')], { ...assignment, punch_mode: 'am_only', end_time: '12:00' });
  assert.equal((await resolveLocatorShiftCoverage(db, 'employee', day)).can_file, false);
});
test('single-session shift keeps IN/OUT for the remaining working portion', async () => {
  const db = database([holiday('am_only')], { ...assignment, punch_mode: 'single_session' });
  const info = await resolveLocatorShiftCoverage(db, 'employee', day);
  assert.equal(info.can_file, true);
  assert.deepEqual(info.allowed_slots, ['am_in','pm_out']);
  assert.equal((await validateLocatorWorkingDayForEmployee(db, 'employee', day, { amIn: true, pmOut: true })).ok, true);
});
test('ordinary dates and explicit working-day overrides retain their scheduled slots', async () => {
  const db = database([], { ...assignment, working_days: [2], override_is_working_day: true });
  assert.deepEqual((await resolveLocatorShiftCoverage(db, 'employee', day)).allowed_slots, ['am_in','am_out','pm_in','pm_out']);
  assert.deepEqual(await validateLocatorWorkingDayForEmployee(db, 'employee', day, { amIn: true }), { ok: true });
});
test('holiday lookup failure cannot silently permit locator filing', async () => {
  const db = { async query(sql) {
    if (sql.includes('FROM assignments a')) return { rows: [assignment] };
    throw new Error('holiday database unavailable');
  } };
  await assert.rejects(validateLocatorWorkingDayForEmployee(db, 'employee', day), /holiday database unavailable/);
});

for (const coverage of ['whole_day', 'am_only', 'pm_only']) {
  test(`HR full-shift filing respects ${coverage} holiday coverage`, async () => {
    const submissions = [];
    const db = database([holiday(coverage)]);
    const controller = require('../src/modules/locator/controllers/staffFiling.controller')({
      pool: { query: async () => ({ rows: [{ id:'employee' }] }) },
      validateStaffBatch: ids => ids, normalizeRequestType: value => value,
      boolField: value => value === true, validateLocatorRequiredFields: () => ({valid:true}),
      parseLocatorDateOnly, resolveLocatorShiftCoverage: (_, employee, date) => resolveLocatorShiftCoverage(db, employee, date),
      runStaffBatch: require('../src/services/locatorStaffFiling').runStaffBatch,
      locatorSubmissionService: { submit: async value => { submissions.push(value); return {id:'saved'}; } },
    });
    const res = { status() { return this; }, json(body) { this.body = body; } };
    await controller.fileForEmployees({ user:{id:'encoder',role:'hr'}, body:{employee_ids:['employee'],slip_date:day.dateStr,request_type:'locator',office:'Hall',reason:'Meeting',full_shift:true} }, res);
    assert.equal(submissions.length, coverage === 'whole_day' ? 0 : 1);
    if (coverage === 'whole_day') assert.match(res.body.results[0].error, /holiday/i);
    else {
      assert.equal(submissions[0].amIn, coverage === 'pm_only');
      assert.equal(submissions[0].amOut, coverage === 'pm_only');
      assert.equal(submissions[0].pmIn, coverage === 'am_only');
      assert.equal(submissions[0].pmOut, coverage === 'am_only');
    }
  });
}

test('leave excludes holiday dates while retaining working dates in a mixed range', async () => {
  const dates = require('../src/modules/leave/policies/dates')({});
  const service = require('../src/modules/leave/services/workingDays')({ ...dates, ...require('../src/services/holidayRangeUtils') });
  const db = { async query(sql) {
    if (sql.includes('FROM generate_series')) return { rows: [2,3,4].map(n => ({attendance_date:`2026-11-0${n}`,working_days:[1,2,3,4,5],has_assignment:true,has_shift:true})) };
    return { rows: sql.includes('recurring = false') ? [holiday('whole_day')] : [] };
  } };
  const result = await service.computeEmployeeLeaveWorkingDays(db, 'employee', '2026-11-02', '2026-11-04');
  assert.equal(result.days, 2);
  assert.deepEqual(result.countedDates, ['2026-11-03','2026-11-04']);
});

for (const [moduleName, handler] of [['submit', 'submitLeave'], ['submitWithAttachment', 'submitWithAttachment'], ['update', 'updateLeave']]) {
  test(`leave ${handler} explains a date range with no working days before any write`, async () => {
    const queries = [];
    const row = { id: 'request', status: 'draft', employee_official_snapshot: {} };
    const db = { async query(sql) { queries.push(sql); return { rows: [row] }; }, release() {} };
    const deps = {
      pool: { connect: async () => db, query: db.query },
      requiredLeaveDateRangeError: () => null, toIsoDateStr: value => value,
      invalidProvidedDate: () => false,
      computeNumberOfDaysSync: () => 1, computeEmployeeLeaveWorkingDays: async () => ({ days: 0, holidayDates: [day.dateStr] }),
      ensureLeaveTypeIdByName: async () => 'type', getLeaveTypeDefinition: async () => ({}),
      assertLeaveEmploymentEligibility: async () => {}, assertLeaveServiceEligibility: async () => {},
      lockEmployeeLeaveFiling: async () => {}, getDepartmentReviewSnapshot: async () => ({}),
      workflowEngine: { prepareWorkflow: async () => ({}) }, assertLeaveSubmissionReviewer: async () => {},
      normalizeEmployeeDetailSchema: () => [], employeeLeaveDetailsFromPayload: () => ({}),
      loadEmployeeOfficialSnapshot: async () => ({}), normalizeEmployeeOfficialSnapshot: () => ({}),
      readMaternityDeliveryType: () => null, readAdoptionParentRole: () => null, readLeaveEventDates: () => ({}),
      validateEmployeeUpdateTransition: () => ({ nextStatus: 'pending_hr' }),
      parseJsonBodyField: value => value,
    };
    const controller = require(`../src/modules/leave/controllers/${moduleName}.controller`)(deps);
    const res = { code: 200, status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; } };
    await controller[handler]({ user: { id: 'employee' }, params: { id: 'request' }, body: { leave_type: 'vacationLeave', start_date: day.dateStr, end_date: day.dateStr }, file: { buffer: Buffer.from('paper') } }, res);
    assert.equal(res.code, 400);
    assert.equal(res.body.error, 'The selected dates contain no working days after excluding holidays and rest days. Choose a date with a scheduled working day.');
    assert.equal(queries.some(sql => /^INSERT|^UPDATE/.test(sql.trim())), false);
  });
}
