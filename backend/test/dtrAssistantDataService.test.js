const test = require('node:test');
const assert = require('node:assert/strict');

const {
  loadEmployeeAssistantContext,
  __test: dataServiceTest,
} = require('../src/services/dtrAssistant/dtrAssistantDataService');
const {
  dtrExportRows,
} = require('../src/services/dtrAssistant/dtrAssistantExportService');

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
  if (/SUM\(COALESCE\(lr\.number_of_days/i.test(sql)) {
    return {
      rows: [
        {
          leave_type_key: 'soloParentLeave',
          days: 2,
          request_count: 1,
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
    query: async (query, params = []) => {
      const sql = typeof query === 'string' ? query : query.text;
      const values = typeof query === 'string' ? params : query.values || [];
      calls.push({
        sql,
        params: values,
        queryTimeout: typeof query === 'string' ? null : query.query_timeout,
      });
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

  assert.equal(calls.length, 9);
  const globalQueries = calls.filter(
    ({ sql }) =>
      /FROM leave_types/i.test(sql) ||
      /FROM locator_request_types/i.test(sql)
  );
  const employeeQueries = calls.filter((call) => !globalQueries.includes(call));
  assert.equal(globalQueries.length, 2);
  for (const call of employeeQueries) {
    assert.equal(call.params[0], userId, call.sql.slice(0, 60));
    assert.equal(call.queryTimeout, 10000, call.sql.slice(0, 60));
  }
  for (const call of globalQueries) {
    assert.equal(call.queryTimeout, 10000, call.sql.slice(0, 60));
  }
  const calendarQuery = calls.find(({ sql }) => /FROM generate_series/i.test(sql));
  assert.match(calendarQuery.sql, /LEAST\s*\(/i);
  assert.equal(calendarQuery.params[3], 366);

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
  assert.deepEqual(
    context.leave_annual_usage.find(
      (item) => item.leave_type_key === 'soloParentLeave'
    ),
    {
      year: 2026,
      leave_type_key: 'soloParentLeave',
      days: 2,
      request_count: 1,
    }
  );
  assert.equal(context.recent_locator_slips[0].coverage.pm_out, true);
  assert.equal(context.locator_types[0].code, 'work_from_home');
  assert.ok(context.leave_guideline_catalog.length > 0);
  assert.ok(context.dtr_policies.length > 0);
  assert.ok(context.locator_policies.length > 0);
});

test('DTR assistant data loader validates ranges before issuing queries', async () => {
  let queryCount = 0;
  const pool = {
    query: async () => {
      queryCount += 1;
      return { rows: [] };
    },
  };

  await assert.rejects(
    loadEmployeeAssistantContext(pool, {
      userId: '88888888-8888-4888-8888-888888888888',
      message: 'show my DTR',
      dateRange: {
        label: 'invalid',
        startDate: '2026-02-30',
        endDate: '2026-02-30',
      },
    }),
    (error) => error.statusCode === 400 && error.code === 'ASSISTANT_DATE_INVALID'
  );
  assert.equal(queryCount, 0);
});

test('DTR assistant data loader rejects an aborted request before querying', async () => {
  let queryCount = 0;
  const pool = {
    query: async () => {
      queryCount += 1;
      return { rows: [] };
    },
  };
  const controller = new AbortController();
  controller.abort();

  await assert.rejects(
    loadEmployeeAssistantContext(pool, {
      userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      message: 'show my DTR today',
      signal: controller.signal,
    }),
    (error) =>
      error.statusCode === 499 && error.code === 'ASSISTANT_REQUEST_ABORTED'
  );
  assert.equal(queryCount, 0);
});

test('DTR assistant loads and exports more than 70 saved rows without truncation', async () => {
  const dates = Array.from({ length: 80 }, (_, index) =>
    new Date(Date.UTC(2026, 0, index + 1)).toISOString().slice(0, 10)
  );
  const calls = [];
  const pool = {
    query: async (query) => {
      const sql = typeof query === 'string' ? query : query.text;
      calls.push(sql);

      if (/FROM dtr_daily_summary/i.test(sql)) {
        return {
          rows: [...dates].reverse().map((attendanceDate, index) => ({
            id: `dtr-${index + 1}`,
            attendance_date: attendanceDate,
            time_in: `${attendanceDate}T08:00:00+08:00`,
            time_out: `${attendanceDate}T17:00:00+08:00`,
            total_hours: 8,
            late_minutes: 0,
            undertime_minutes: 0,
            overtime_minutes: 0,
            status: 'present',
            source: 'biometric',
          })),
        };
      }

      if (/FROM generate_series/i.test(sql)) {
        return {
          rows: dates.map((attendanceDate) => ({
            attendance_date: attendanceDate,
            assignment_id: 'assignment-1',
            shift_id: 'shift-1',
            shift_name: 'Morning Shift',
            start_time: '08:00:00',
            end_time: '17:00:00',
            punch_mode: 'four_punch',
            working_days: [1, 2, 3, 4, 5],
          })),
        };
      }

      return { rows: [] };
    },
  };

  const context = await loadEmployeeAssistantContext(pool, {
    userId: '99999999-9999-4999-8999-999999999999',
    message: 'export my DTR from January 1 to March 21, 2026',
    dateRange: {
      label: 'January 1 to March 21, 2026',
      startDate: '2026-01-01',
      endDate: '2026-03-21',
    },
  });

  const savedDtrSql = calls.find((sql) => /FROM dtr_daily_summary/i.test(sql));
  assert.doesNotMatch(savedDtrSql, /LIMIT\s+70/i);
  assert.equal(context.dtr_records.length, 80);
  assert.equal(context.data_completeness.dtr_records.complete, true);
  assert.equal(context.data_completeness.dtr_records.capped, false);
  assert.equal(context.data_completeness.dtr_records.returned_count, 80);
  assert.equal(context.data_completeness.dtr_calendar_days.returned_count, 80);
  assert.equal(context.data_completeness.dtr_export.complete, true);

  const exported = dtrExportRows(context);
  const statusIndex = exported.header.indexOf('Status');
  assert.equal(exported.rows.length, 80);
  assert.equal(exported.rows[0][0], '2026-01-01');
  assert.equal(exported.rows[0][statusIndex], 'present');
});

test('DTR assistant query timeout is configurable and bounded', () => {
  assert.equal(dataServiceTest.assistantQueryTimeoutMs({}), 10000);
  assert.equal(
    dataServiceTest.assistantQueryTimeoutMs({ DTR_ASSISTANT_QUERY_TIMEOUT_MS: '250' }),
    1000
  );
  assert.equal(
    dataServiceTest.assistantQueryTimeoutMs({ DTR_ASSISTANT_QUERY_TIMEOUT_MS: '120000' }),
    60000
  );
  assert.equal(
    dataServiceTest.assistantQueryTimeoutMs({ DTR_ASSISTANT_QUERY_TIMEOUT_MS: '8000' }),
    8000
  );
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
