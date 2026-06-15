const test = require('node:test');
const assert = require('node:assert/strict');

const {
  detectEmployeeAssistantIntent,
} = require('../src/services/dtrAssistant/dtrAssistantIntentService');
const {
  buildFastEmployeeAssistantReply,
} = require('../src/services/dtrAssistant/dtrAssistantFastReply');
const {
  dtrExportRows,
} = require('../src/services/dtrAssistant/dtrAssistantExportService');
const {
  normalizeRating,
} = require('../src/services/dtrAssistant/dtrAssistantFeedbackService');

test('DTR assistant regression: Bisaya/Tagalog/English prompts route to expected intents', () => {
  const cases = [
    ['pila kabuok absent nako aning bulana?', 'dtr_absent_summary'],
    ['unsay status sa akong dtr adtung niaging miyerkules?', 'dtr_status_explanation'],
    ['naa koy absent gahapon?', 'dtr_absent_summary'],
    ['pila akong balance sa sick leave?', 'leave_balance'],
    ['ngano gamay nalang akong vacation leave?', 'leave_balance'],
    ['why is my vacation leave balance low?', 'leave_balance'],
    ['unsay requirements sa maternity leave?', 'leave_requirements'],
    ['need med cert if 5 days sick leave?', 'leave_attachment_requirement'],
    ['kinsa nag hold sa akong leave request?', 'leave_approval_tracker'],
    ['ngano gi reject akong leave?', 'leave_rejection_reason'],
    ['pwede ba ko mag file ug pass slip ugma?', 'locator_availability_check'],
    ['ngano gi reject akong locator?', 'locator_rejection_reason'],
    ['asa na akong official business request?', 'locator_approval_tracker'],
    ['covered ba sa locator akong PM out?', 'dtr_locator_coverage_check'],
    ['export my dtr this month', 'dtr_export_guidance'],
  ];

  for (const [message, expected] of cases) {
    assert.equal(detectEmployeeAssistantIntent(message), expected, message);
  }
});

test('DTR assistant regression: locator exact slot coverage requires approved matching slot', () => {
  const context = {
    date_range: {
      label: 'tomorrow',
      startDate: '2026-06-16',
      endDate: '2026-06-16',
    },
    recent_locator_slips: [
      {
        slip_date: '2026-06-16',
        request_type: 'pass_slip',
        request_type_label: 'Pass Slip',
        status: 'pending_department_head',
        coverage: {
          am_in: false,
          am_out: false,
          pm_in: true,
          pm_out: true,
        },
      },
    ],
  };

  const reply = buildFastEmployeeAssistantReply(
    'covered ba sa locator akong PM out ugma?',
    context,
    'dtr_locator_coverage_check'
  );

  assert.match(reply, /PM out/);
  assert.match(reply, /wala koy approved locator/i);
  assert.match(reply, /not final coverage until approved/i);
});

test('DTR assistant regression: DTR export rows include no-record scheduled days', () => {
  const rows = dtrExportRows({
    date_range: {
      startDate: '2026-06-01',
      endDate: '2026-06-02',
    },
    dtr_records: [
      {
        attendance_date: '2026-06-01',
        status: 'present',
        time_in: '08:00',
        time_out: '17:00',
      },
    ],
    dtr_calendar_days: [
      {
        attendance_date: '2026-06-01',
        shift_id: 'shift-1',
        shift_name: 'Morning Shift',
        start_time: '08:00',
        end_time: '17:00',
      },
      {
        attendance_date: '2026-06-02',
        shift_id: 'shift-1',
        shift_name: 'Morning Shift',
        start_time: '08:00',
        end_time: '17:00',
      },
    ],
  });

  assert.equal(rows.rows.length, 2);
  assert.equal(rows.rows[0][5], 'present');
  assert.equal(rows.rows[1][5], 'no_record');
});

test('DTR assistant regression: feedback rating aliases normalize safely', () => {
  assert.equal(normalizeRating('correct'), 'up');
  assert.equal(normalizeRating('wrong'), 'down');
  assert.equal(normalizeRating('maybe'), null);
});
