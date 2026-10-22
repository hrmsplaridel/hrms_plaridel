const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const EMPLOYEE = '00000000-0000-4000-8000-000000000601';
const DEPARTMENT = '00000000-0000-4000-8000-000000000602';
const entry = '../src/routes/dtrDailySummary';

function fixtureDatabase() {
  const assignment = {
    id: 'assignment', employee_id: EMPLOYEE, department_id: DEPARTMENT,
    effective_from: '2020-01-01', effective_to: null,
    start_time: '08:00:00', end_time: '17:00:00', break_end: '13:00:00',
    shift_start: '08:00:00', shift_end: '17:00:00', shift_break_end: '13:00:00',
    shift_break_start: '12:00:00', grace_period_minutes: 0,
    punch_mode: 'full_day', working_days: [1, 2, 3, 4, 5],
  };
  const locator = (date) => ({
    id: `locator-${date}`, employee_id: EMPLOYEE, slip_date_str: date,
    am_in: true, am_out: true, pm_in: true, pm_out: true,
    request_type: 'locator', dtr_slot_label: 'Official Business', coverage_mode: 'manual',
  });
  return {
    async query(sql) {
      const text = String(sql);
      let rows;
      if (text === 'SELECT coverage FROM holidays LIMIT 1') rows = [];
      else if (text.includes('d.attendance_date::text AS attendance_date_iso')) rows = [{
        id: 'physical-record', employee_id: EMPLOYEE, employee_name: 'Sample Employee',
        attendance_date_iso: '2020-06-05', status: 'late', source: 'biometric',
        time_in: '2020-06-05T08:15:00+08:00', break_out: '2020-06-05T12:00:00+08:00',
        break_in: '2020-06-05T13:00:00+08:00', time_out: '2020-06-05T16:30:00+08:00',
        total_hours: '7.25', late_minutes: 15, undertime_minutes: 30,
      }];
      else if (text.includes('FROM holidays')) rows = [{
        id: 'holiday', name: 'Local Holiday', holiday_type: 'local',
        date_from: '2020-06-01', date_to: '2020-06-01', recurring: false, coverage: 'whole_day',
      }];
      else if (text.includes('FROM dtr_leave_coverage c')) rows = ['2020-06-01', '2020-06-02'].map((date) => ({
        employee_id: EMPLOYEE, attendance_date: date, leave_coverage_id: `coverage-${date}`,
        leave_request_id: 'leave-request', leave_type_name: 'Wellness Leave',
      }));
      else if (text.includes('FROM leave_requests lr')) rows = [];
      else if (text.includes('FROM locator_slips ls')) rows = ['2020-06-01', '2020-06-02', '2020-06-04', '2020-06-05'].map(locator);
      else if (text.includes('FROM assignments a')) rows = [assignment];
      else if (text.includes('FROM employee_schedule_overrides')) rows = [];
      else if (text.includes('FROM attendance_policies')) rows = [{
        id: 'policy', is_default: true, is_active: true, work_hours_per_day: 8,
        deduct_late: true, deduct_undertime: true, deduction_multiplier: 1,
        use_equivalent_day_conversion: true, absent_equals_full_day_deduction: true,
      }];
      else if (text.includes('FROM policy_assignments')) rows = [];
      else if (text.includes('SELECT full_name FROM users')) rows = [{ full_name: 'Sample Employee' }];
      else assert.fail(`Unexpected report query: ${text}`);
      return { rows: structuredClone(rows) };
    },
  };
}

async function report(query, run) {
  const restore = withMockedModule('../src/config/db', { pool: fixtureDatabase() });
  clearModule(entry);
  try {
    const router = require(entry);
    const handle = router.stack.find((l) => l.route.path === '/' && l.route.methods.get).route.stack.at(-1).handle;
    const res = {
      statusCode: 200, headers: {},
      status(code) { this.statusCode = code; return this; },
      json(body) { this.body = body; return this; },
      setHeader(name, value) { this.headers[name] = value; },
    };
    await handle({ user: { id: EMPLOYEE, role: 'employee' }, query: {
      start_date: '2020-06-01', end_date: '2020-06-07', recompute: 'true', ...query,
    } }, res);
    assert.equal(res.statusCode, 200, JSON.stringify(res.body));
    await run(res);
  } finally { clearModule(entry); restore(); }
}

test('DTR report merges holiday, leave, absence, locator and physical punches with their existing precedence', async () => {
  await report({}, async (res) => {
    assert.deepEqual(res.body.map((r) => [r.record_date, r.status]), [
      ['2020-06-05', 'late'], ['2020-06-04', 'on_field'], ['2020-06-03', 'absent'],
      ['2020-06-02', 'on_leave'], ['2020-06-01', 'holiday'],
    ]);
    assert.equal(res.headers['X-Total-Count'], '5');
    assert.equal(res.body.find((r) => r.status === 'on_leave').leave_request_id, 'leave-request');
    const absence = res.body.find((r) => r.status === 'absent');
    assert.equal(absence.report_deduction.absence_minutes, 480);
    for (const row of res.body.filter((r) => ['on_leave', 'holiday', 'on_field'].includes(r.status))) {
      assert.equal(row.report_deduction.total_minutes, 0);
    }
  });
});

test('approved locator coverage keeps penalties calculated from physical punches', async () => {
  await report({}, async (res) => {
    const physical = res.body.find((r) => r.id === 'physical-record');
    assert.equal(physical.locator_slip_id, 'locator-2020-06-05');
    assert.equal(physical.late_minutes, 15);
    assert.equal(physical.undertime_minutes, 30);
    assert.equal(physical.attendance_remark, 'Late + Undertime');
    assert.equal(physical.report_deduction.total_minutes, 45);
    assert.equal(physical.source, 'biometric');
  });
});

test('DTR paginates after all report overlays and keeps the complete total', async () => {
  await report({ limit: '2', offset: '1' }, async (res) => {
    assert.equal(res.headers['X-Total-Count'], '5');
    assert.equal(res.headers['X-Limit'], '2');
    assert.equal(res.headers['X-Offset'], '1');
    assert.deepEqual(res.body.map((r) => r.record_date), ['2020-06-04', '2020-06-03']);
  });
});
