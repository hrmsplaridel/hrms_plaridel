const test = require('node:test');
const assert = require('node:assert/strict');
const { createDtrRuntime } = require('../src/modules/dtr/dtr.runtime');
const { loadDtrDependencies } = require('../src/modules/dtr/dependencies');
const { withMockedModule } = require('./helpers/moduleMocks');

const shift = { punchMode: 'full_day', startMinutes: 480, endMinutes: 1020,
  breakStartMinutes: 720, breakEndMinutes: 780, graceMinutes: 0 };
const employee = '00000000-0000-4000-8000-000000000601';
const date = '2020-06-05';
const saved = { id: 'summary', employee_id: employee, attendance_date_iso: date,
  time_in: `${date}T08:15:00+08:00`, break_out: `${date}T12:00:00+08:00`,
  break_in: `${date}T13:00:00+08:00`, time_out: `${date}T16:30:00+08:00`,
  status: 'late', total_hours: 7.25, late_minutes: 15, undertime_minutes: 30 };

async function today(kind) {
  const restore = withMockedModule('../src/config/db', { pool: { query: async () => ({ rows: [] }) } });
  try {
    const runtime = createDtrRuntime(loadDtrDependencies());
    runtime.todayInHrmsTimezone = () => date;
    runtime._holidaysHasCoverageColumn = async () => true;
    runtime.loadHolidayOverlayMap = async () => kind === 'holiday'
      ? new Map([[date, { id: 'holiday', name: 'Holiday', coverage: 'whole_day' }]]) : new Map();
    runtime.getAssignmentShiftForDate = async () => shift;
    runtime.getAttendancePolicyForEmployeeDate = async () => ({ deductLate: true, deductUndertime: true, deductionMultiplier: 1 });
    const locator = { id: 'locator', segments: ['AM IN', 'AM OUT', 'PM IN', 'PM OUT'] };
    runtime.getApprovedLocatorByDateInRange = async () => kind === 'locator' ? new Map([[`${employee}|${date}`, locator]]) : new Map();
    runtime.annotateLocatorReportRows = require('../src/modules/dtr/services/reportLocators')(runtime).annotateLocatorReportRows;
    runtime.pool = { query: async () => ({ rows: kind === 'locator_only' ? [] : [{ ...saved,
      ...(kind === 'leave' ? { is_leave_covered: true, leave_request_id: 'leave',
        leave_type_name: 'Sick Leave', number_of_days: 1 } : {}),
    }] }) };
    if (kind === 'locator_only') runtime.getApprovedLocatorByDateInRange = async () => new Map([[`${employee}|${date}`, locator]]);
    const handle = require('../src/modules/dtr/controllers/today.controller')(runtime).getTodayRecord;
    const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
    await handle({ user: { id: employee } }, res);
    assert.equal(res.statusCode, 200);
    return res.body;
  } finally { restore(); }
}

for (const [kind, status] of [['leave', 'on_leave'], ['holiday', 'holiday'], ['locator', 'on_field'], ['locator_only', 'on_field']]) {
  test(`today endpoint hides punches under full ${kind}`, async () => {
    const row = await today(kind);
    assert.ok(row);
    assert.equal(row.status, status);
    assert.equal(row.time_in, null);
    assert.equal(row.time_out, null);
    assert.equal(row.total_hours, null);
  });
}

test('today endpoint exposes saved punches when coverage is absent', async () => {
  const row = await today('none');
  assert.equal(row.time_in, saved.time_in);
  assert.equal(row.time_out, saved.time_out);
});
