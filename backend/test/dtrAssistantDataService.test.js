const test = require('node:test');
const assert = require('node:assert/strict');

const {
  loadEmployeeAssistantContext,
} = require('../src/services/dtrAssistant/dtrAssistantDataService');

function resultForSql(sql) {
  if (/FROM users\s+WHERE id/i.test(sql)) {
    return {
      rows: [
        {
          id: 'employee-1',
          full_name: 'Employee One',
          role: 'employee',
          sex: 'female',
          civil_status: 'single',
          date_of_birth: '1995-01-01',
        },
      ],
    };
  }
  if (/FROM dtr_daily_summary/i.test(sql)) {
    return {
      rows: [
        {
          id: 'dtr-1',
          attendance_date: '2026-06-24',
          time_in: 'invalid date',
          break_out: null,
          break_in: null,
          time_out: null,
          total_hours: '7.5',
          late_minutes: null,
          undertime_minutes: 30,
          overtime_minutes: 0,
          status: 'present',
          remarks: '  A   spaced   remark  ',
        },
      ],
    };
  }
  if (/FROM generate_series/i.test(sql)) {
    return {
      rows: [
        {
          attendance_date: '2026-06-24',
          assignment_id: 'assignment-1',
          shift_id: 'shift-1',
          shift_name: 'Morning Shift',
          start_time: '08:00:00',
          end_time: '17:00:00',
          break_end: '13:00:00',
          punch_mode: 'four_punch',
          grace_period_minutes: null,
          working_days: [1, '2', 3],
          holiday_id: null,
        },
      ],
    };
  }
  if (/FROM leave_balances/i.test(sql)) {
    return {
      rows: [
        {
          leave_type: 'sickLeave',
          earned_days: '3.75',
          used_days: '3',
          pending_days: '0.25',
          adjusted_days: null,
          as_of_date: '2026-06-24',
        },
      ],
    };
  }
  if (/FROM leave_requests/i.test(sql)) {
    return {
      rows: [
        {
          id: 'leave-1',
          start_date: '2026-06-25',
          end_date: '2026-06-25',
          days: '1',
          status: 'pending_hr',
          reason: '  Family   matter ',
          attachment_path: null,
          details: 'not-an-object',
          history: 'invalid json',
          leave_type_key: 'vacationLeave',
          leave_type: 'Vacation Leave',
          created_at: '2026-06-20T00:00:00.000Z',
        },
      ],
    };
  }
  if (/FROM leave_types/i.test(sql)) {
    return {
      rows: [
        {
          id: 'leave-type-1',
          name: 'sickLeave',
          display_name: 'Sick Leave',
          description: 'Illness leave',
          employee_can_file: true,
          admin_only: false,
          allows_past_dates: false,
          requires_attachment: false,
          requires_attachment_when_over_days: '5',
          max_days: null,
          minimum_advance_days: 0,
          sex_eligibility: null,
          affects_dtr_normally: true,
          balance_ledger_type: 'sickLeave',
          is_active: true,
        },
      ],
    };
  }
  if (/FROM locator_slips/i.test(sql)) {
    return {
      rows: [
        {
          id: 'locator-1',
          slip_date: '2026-06-24',
          request_type: 'work_from_home',
          office: ' Home ',
          reason: ' Payroll ',
          am_in: true,
          am_out: true,
          pm_in: true,
          pm_out: true,
          status: 'approved',
          attachment_path: null,
          request_type_label: 'Work From Home',
          request_type_requires_attachment: false,
          request_type_coverage_mode: 'wfh',
        },
      ],
    };
  }
  if (/FROM locator_request_types/i.test(sql)) {
    return {
      rows: [
        {
          code: 'work_from_home',
          label: 'Work From Home',
          requires_attachment: false,
          coverage_mode: 'wfh',
          is_active: true,
          sort_order: 1,
        },
      ],
    };
  }
  throw new Error(`Unhandled SQL in test: ${sql.slice(0, 80)}`);
}

test('DTR assistant data loader scopes every employee query and normalizes rows', async () => {
  const calls = [];
  const userId = '55555555-5555-4555-8555-555555555555';
  const pool = {
    query: async (sql, params = []) => {
      calls.push({ sql, params });
      return resultForSql(sql);
    },
  };

  const context = await loadEmployeeAssistantContext(pool, {
    userId,
    message: 'show my records today',
    dateRange: {
      label: 'today',
      startDate: '2026-06-24',
      endDate: '2026-06-24',
    },
  });

  assert.equal(calls.length, 8);
  const globalQueries = calls.filter(
    ({ sql }) =>
      /FROM leave_types/i.test(sql) ||
      /FROM locator_request_types/i.test(sql)
  );
  const employeeQueries = calls.filter((call) => !globalQueries.includes(call));
  assert.equal(globalQueries.length, 2);
  for (const call of employeeQueries) {
    assert.equal(call.params[0], userId, call.sql.slice(0, 60));
  }

  assert.equal(context.scope, 'employee_self');
  assert.equal(context.employee.id, 'employee-1');
  assert.equal(context.dtr_records[0].time_in, null);
  assert.equal(context.dtr_records[0].total_hours, 7.5);
  assert.equal(context.dtr_records[0].late_minutes, 0);
  assert.equal(context.dtr_records[0].remarks, 'A spaced remark');
  assert.deepEqual(context.dtr_calendar_days[0].working_days, [1, 2, 3]);
  assert.equal(context.dtr_calendar_days[0].grace_period_minutes, 0);
  assert.equal(context.leave_balances[0].remaining_days, 0.75);
  assert.equal(context.leave_balances[0].available_days, 0.5);
  assert.deepEqual(context.recent_leave_requests[0].history, []);
  assert.deepEqual(context.recent_leave_requests[0].details, {});
  assert.equal(context.recent_leave_requests[0].reason, 'Family matter');
  assert.equal(context.recent_locator_slips[0].coverage.pm_out, true);
  assert.equal(context.locator_types[0].code, 'work_from_home');
  assert.ok(context.leave_guideline_catalog.length > 0);
  assert.ok(context.dtr_policies.length > 0);
  assert.ok(context.locator_policies.length > 0);
});

test('DTR assistant data loader returns safe empty collections when records are absent', async () => {
  const pool = {
    query: async () => ({ rows: [] }),
  };
  const context = await loadEmployeeAssistantContext(pool, {
    userId: '66666666-6666-4666-8666-666666666666',
    message: 'show my DTR today',
    dateRange: {
      label: 'today',
      startDate: '2026-06-24',
      endDate: '2026-06-24',
    },
  });

  assert.equal(context.employee, null);
  assert.deepEqual(context.dtr_records, []);
  assert.deepEqual(context.dtr_calendar_days, []);
  assert.deepEqual(context.leave_balances, []);
  assert.deepEqual(context.recent_leave_requests, []);
  assert.deepEqual(context.recent_locator_slips, []);
});

test('DTR assistant data loader does not hide database failures', async () => {
  const pool = {
    query: async () => {
      const error = new Error('connection refused');
      error.code = 'ECONNREFUSED';
      throw error;
    },
  };

  await assert.rejects(
    loadEmployeeAssistantContext(pool, {
      userId: '77777777-7777-4777-8777-777777777777',
      message: 'show my DTR today',
    }),
    /connection refused/
  );
});
