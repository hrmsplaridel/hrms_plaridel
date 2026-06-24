const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseAssistantDateRange,
} = require('../src/utils/dateRangeParser');
const {
  createDtrExportAttachment,
  dtrExportRows,
  getDtrExport,
} = require('../src/services/dtrAssistant/dtrAssistantExportService');

test('DTR assistant date parser handles payroll, boundaries, and natural ranges', () => {
  const cases = [
    [
      'next cutoff',
      '2026-06-24',
      { startDate: '2026-06-16', endDate: '2026-06-30' },
    ],
    [
      'last pay period',
      '2026-06-24',
      { startDate: '2026-06-01', endDate: '2026-06-15' },
    ],
    [
      '2 weeks ago',
      '2026-06-24',
      { startDate: '2026-06-08', endDate: '2026-06-14' },
    ],
    [
      'first Monday of June 2026',
      '2026-06-24',
      { startDate: '2026-06-01', endDate: '2026-06-01' },
    ],
    [
      'from Monday to Friday',
      '2026-06-24',
      { startDate: '2026-06-22', endDate: '2026-06-26' },
    ],
    [
      'tomorrow',
      '2026-12-31',
      { startDate: '2027-01-01', endDate: '2027-01-01' },
    ],
    [
      'yesterday',
      '2026-01-01',
      { startDate: '2025-12-31', endDate: '2025-12-31' },
    ],
    [
      'February 2024',
      '2024-02-15',
      { startDate: '2024-02-01', endDate: '2024-02-29' },
    ],
    [
      'next Monday',
      '2026-06-29',
      { startDate: '2026-07-06', endDate: '2026-07-06' },
    ],
  ];

  for (const [message, today, expected] of cases) {
    const actual = parseAssistantDateRange(message, { today });
    assert.equal(actual.startDate, expected.startDate, message);
    assert.equal(actual.endDate, expected.endDate, message);
  }
});

test('DTR exports include no-record workdays and generate owned CSV/XLS files', () => {
  const context = {
    date_range: {
      label: 'June 2026',
      startDate: '2026-06-22',
      endDate: '2026-06-24',
    },
    dtr_records: [
      {
        attendance_date: '2026-06-22',
        status: 'present',
        time_in: '2026-06-22T08:00:00+08:00',
        time_out: '2026-06-22T17:00:00+08:00',
        total_hours: 8,
        late_minutes: 0,
        undertime_minutes: 0,
        overtime_minutes: 0,
        remarks: 'Complete',
      },
    ],
    dtr_calendar_days: [
      {
        attendance_date: '2026-06-22',
        shift_id: 'shift-1',
        shift_name: 'Morning Shift',
        start_time: '08:00:00',
        end_time: '17:00:00',
        grace_period_minutes: 5,
      },
      {
        attendance_date: '2026-06-23',
        shift_id: 'shift-1',
        shift_name: 'Morning Shift',
        start_time: '08:00:00',
        end_time: '17:00:00',
        grace_period_minutes: 5,
      },
      {
        attendance_date: '2026-06-24',
        shift_id: null,
        shift_name: null,
        holiday_name: 'Local Holiday',
        holiday_coverage: 'whole_day',
      },
    ],
  };
  const rows = dtrExportRows(context);
  const statusIndex = rows.header.indexOf('Status');
  assert.equal(rows.rows.length, 3);
  assert.equal(rows.rows[1][statusIndex], 'no_record');
  assert.equal(rows.rows[2][statusIndex], 'no_schedule');

  const userId = 'export-owner';
  const csvAttachment = createDtrExportAttachment(context, userId, 'csv');
  const csv = getDtrExport(csvAttachment.id, userId);
  assert.equal(csvAttachment.kind, 'csv');
  assert.match(csv.filename, /\.csv$/);
  assert.match(csv.buffer.toString('utf8'), /2026-06-23/);
  assert.match(csv.buffer.toString('utf8'), /no_record/);
  assert.equal(getDtrExport(csvAttachment.id, 'other-user'), null);

  const xlsAttachment = createDtrExportAttachment(context, userId, 'xls');
  const xls = getDtrExport(xlsAttachment.id, userId);
  assert.equal(xlsAttachment.kind, 'excel');
  assert.match(xls.filename, /\.xls$/);
  assert.match(xls.buffer.toString('utf8'), /<Workbook/);
  assert.match(xls.buffer.toString('utf8'), /2026-06-23/);
});
