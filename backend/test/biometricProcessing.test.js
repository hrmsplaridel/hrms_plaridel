const test = require('node:test');
const assert = require('node:assert/strict');

function withMockedModule(modulePath, exportsValue) {
  const resolved = require.resolve(modulePath);
  const previous = require.cache[resolved];
  require.cache[resolved] = {
    id: resolved,
    filename: resolved,
    loaded: true,
    exports: exportsValue,
  };
  return () => {
    if (previous) {
      require.cache[resolved] = previous;
    } else {
      delete require.cache[resolved];
    }
  };
}

function loadBiometricProcessing(query) {
  const reconciliations = [];
  const restoreReconciliation = withMockedModule('../src/services/dtrMonthEndReconciliation', {
    enqueueBiometricReconciliation: async (_, changes) => { reconciliations.push(...changes); },
  });
  const restoreDb = withMockedModule('../src/config/db', {
    pool: {
      query: query || (async () => {
        throw new Error('Unexpected database query in biometricProcessing unit test');
      }),
    },
  });
  const restoreWs = withMockedModule('../src/websockets/biometricStream', {
    broadcastBiometricUpdate: () => 0,
  });

  const modulePath = require.resolve('../src/services/biometricProcessing');
  delete require.cache[modulePath];
  const service = require('../src/services/biometricProcessing');

  return {
    service,
    reconciliations,
    restore() {
      restoreReconciliation();
      delete require.cache[modulePath];
      restoreWs();
      restoreDb();
    },
  };
}

test('AM-only biometric punches compute total hours from AM In to AM Out', () => {
  const { service, restore } = loadBiometricProcessing();
  try {
    const amIn = '2026-05-22T00:00:00.000Z';
    const amOut = '2026-05-22T04:00:00.000Z';

    const interpreted = service.interpretPunchesForDay(
      [amIn, amOut],
      'am_only'
    );

    assert.equal(interpreted.timeIn, amIn);
    assert.equal(interpreted.breakOut, amOut);
    assert.equal(interpreted.breakIn, null);
    assert.equal(interpreted.timeOut, null);
    assert.equal(interpreted.status, 'present');
    assert.equal(interpreted.totalHours, 4);
  } finally {
    restore();
  }
});

test('first punch after shift end is rejected for same-day shifts', () => {
  const { service, restore } = loadBiometricProcessing();
  try {
    const shiftInfo = {
      startMinutes: 8 * 60,
      endMinutes: 17 * 60,
      graceMinutes: 0,
      breakEndMinutes: 13 * 60,
      punchMode: 'auto',
    };

    assert.equal(
      service.isPunchAfterShiftEnd(
        '2026-06-22T12:57:00.000Z',
        shiftInfo,
        'Asia/Manila'
      ),
      true
    );
    assert.equal(
      service.isFirstPunchAfterShiftEnd(
        ['2026-06-22T12:57:00.000Z'],
        shiftInfo,
        'Asia/Manila'
      ),
      true
    );
    assert.equal(
      service.isPunchAfterShiftEnd(
        '2026-06-22T09:00:00.000Z',
        shiftInfo,
        'Asia/Manila'
      ),
      false
    );
  } finally {
    restore();
  }
});

test('after-shift guard does not reject overnight shifts', () => {
  const { service, restore } = loadBiometricProcessing();
  try {
    const overnightShift = {
      startMinutes: 22 * 60,
      endMinutes: 6 * 60,
      graceMinutes: 0,
      breakEndMinutes: null,
      punchMode: 'single_session',
    };

    assert.equal(
      service.isPunchAfterShiftEnd(
        '2026-06-22T13:00:00.000Z',
        overnightShift,
        'Asia/Manila'
      ),
      false
    );
  } finally {
    restore();
  }
});

test('completed system summary changes when a corrected final punch arrives', () => {
  const { service, restore } = loadBiometricProcessing();
  try {
    const existing = {
      time_in: '2026-08-14T00:00:00.000Z',
      break_out: '2026-08-14T04:00:00.000Z',
      break_in: '2026-08-14T05:00:00.000Z',
      time_out: '2026-08-14T09:00:00.000Z',
      status: 'present',
      total_hours: '8.00',
      late_minutes: 0,
      undertime_minutes: 0,
    };

    assert.equal(
      service.hasBiometricSummaryChanged(existing, {
        timeIn: existing.time_in,
        breakOut: existing.break_out,
        breakIn: existing.break_in,
        timeOut: existing.time_out,
        status: 'present',
        totalHours: 8,
        lateMinutes: 0,
        undertimeMinutes: 0,
      }),
      false,
    );

    assert.equal(
      service.hasBiometricSummaryChanged(existing, {
        timeIn: existing.time_in,
        breakOut: existing.break_out,
        breakIn: existing.break_in,
        timeOut: '2026-08-14T09:30:00.000Z',
        status: 'present',
        totalHours: 8.5,
        lateMinutes: 0,
        undertimeMinutes: 0,
      }),
      true,
    );
  } finally {
    restore();
  }
});

test('processing rebuilds a completed system row from a later biometric punch', async () => {
  const employeeId = '85082d28-c26c-441d-a215-67851a5b8721';
  let updateParams = null;
  const punches = [
    '2026-08-14T00:00:00.000Z',
    '2026-08-14T04:00:00.000Z',
    '2026-08-14T05:00:00.000Z',
    '2026-08-14T09:30:00.000Z',
  ];
  const { service, restore } = loadBiometricProcessing(async (sql, params) => {
    const text = String(sql);
    assert.doesNotMatch(text, /ALTER TABLE shifts/i);
    if (/FROM biometric_attendance_logs/i.test(text)) {
      return {
        rows: [{
          user_id: employeeId,
          attendance_date: '2026-08-14',
          punches,
        }],
      };
    }
    if (/FROM dtr_daily_summary_deletions/i.test(text)) {
      return { rows: [] };
    }
    if (/FROM assignments a/i.test(text)) {
      return {
        rows: [{
          shift_start: '08:00:00',
          shift_end: '17:00:00',
          shift_break_end: '13:00:00',
          punch_mode: 'full_day',
          grace_period_minutes: 0,
        }],
      };
    }
    if (/FROM holidays/i.test(text) || /FROM leave_requests/i.test(text)) {
      return { rows: [] };
    }
    if (/FROM policy_assignments/i.test(text)) {
      return {
        rows: [{
          id: 'policy-1',
          work_hours_per_day: '8',
          deduct_late: true,
          deduct_undertime: true,
          deduction_multiplier: '1',
        }],
      };
    }
    if (/SELECT id, source, time_in, break_out/i.test(text)) {
      return {
        rows: [{
          id: 'summary-1',
          source: 'system',
          time_in: punches[0],
          break_out: punches[1],
          break_in: punches[2],
          time_out: '2026-08-14T09:00:00.000Z',
          status: 'present',
          total_hours: '8.00',
          late_minutes: 0,
          undertime_minutes: 0,
        }],
      };
    }
    if (/UPDATE dtr_daily_summary SET/i.test(text)) {
      updateParams = params;
      return { rows: [{ id: 'summary-1' }], rowCount: 1 };
    }
    throw new Error(`Unexpected biometric rebuild query: ${text}`);
  });

  try {
    const result = await service.processBiometricLogsToSummary(
      [employeeId],
      '2026-08-14',
      '2026-08-14',
    );

    assert.deepEqual(result, { inserted: 0, updated: 1 });
    assert.ok(updateParams);
    assert.equal(new Date(updateParams[5]).toISOString(), punches[3]);
  } finally {
    restore();
  }
});

test('deleted processed DTR date is not recreated from preserved biometric punches', async () => {
  const employeeId = '5b9fe943-4700-4ff6-a84e-66ef793ecfc4';
  const queries = [];
  const { service, restore } = loadBiometricProcessing(async (sql) => {
    queries.push(String(sql));
    if (/FROM biometric_attendance_logs/i.test(String(sql))) {
      return {
        rows: [
          {
            user_id: employeeId,
            attendance_date: '2026-06-16',
            punches: ['2026-06-16T00:00:00.000Z'],
          },
        ],
      };
    }
    if (/FROM dtr_daily_summary_deletions/i.test(String(sql))) {
      return {
        rows: [
          {
            employee_id: employeeId,
            attendance_date: '2026-06-16',
          },
        ],
      };
    }
    if (/FROM assignments a/i.test(String(sql))) return { rows: [] };
    throw new Error(`Unexpected query after deleted-date suppression: ${sql}`);
  });

  try {
    const result = await service.processBiometricLogsToSummary(
      [employeeId],
      '2026-06-01',
      '2026-06-30',
    );

    assert.deepEqual(result, { inserted: 0, updated: 0 });
    assert.equal(queries.filter((sql) => sql.includes('INSERT INTO dtr_daily_summary')).length, 0);
  } finally {
    restore();
  }
});

for (const source of ['system', 'manual', 'adjusted']) {
  test(`cross-month night processing preserves the saved schedule and protects ${source} ownership`, async () => {
    const employee = '85082d28-c26c-441d-a215-67851a5b8721';
    const snapshot = { startMinutes: 1200, endMinutes: 420, graceMinutes: 0,
      punchMode: 'single_session',
      captureWindowMinutes: 120, workingDays: [1, 2, 3, 4, 5], isWorkingDay: true };
    const start = '2026-09-30T20:00:00+08:00';
    const end = '2026-10-01T07:00:00+08:00';
    let update = null;
    const { service, restore, reconciliations } = loadBiometricProcessing(async (sql, params) => {
      if (/FROM biometric_attendance_logs/.test(sql)) return { rows: [
        { user_id: employee, attendance_date: '2026-09-30', punches: [start] },
        { user_id: employee, attendance_date: '2026-10-01', punches: [end] },
      ] };
      if (/FROM assignments a/.test(sql)) return { rows: [{
        shift_start: '08:00:00', shift_end: '17:00:00', punch_mode: 'full_day',
        shift_snapshot: params[1] === '2026-09-30' ? snapshot : null,
      }] };
      if (/FROM dtr_daily_summary_deletions|FROM holidays|FROM leave_requests/.test(sql)) return { rows: [] };
      if (/FROM policy_assignments|FROM attendance_policies/.test(sql)) return { rows: [{ work_hours_per_day: 8, deduct_undertime: true, deduct_late: true, deduction_multiplier: 1 }] };
      if (/SELECT id, source, time_in/.test(sql)) return { rows: [{ source, time_in: start, time_out: null, status: 'incomplete', total_hours: 0 }] };
      if (/UPDATE dtr_daily_summary/.test(sql)) { update = params; return { rows: [{ id: 'summary' }], rowCount: 1 }; }
      throw new Error(`Unexpected overnight query: ${sql}`);
    });
    try {
      const result = await service.processBiometricLogsToSummary([employee], '2026-10-01', '2026-10-01');
      assert.equal(result.updated, source === 'system' ? 1 : 0);
      assert.deepEqual(reconciliations.map(({ userId, date }) => ({ userId, date })),
        source === 'system' ? [{ userId: employee, date: '2026-09-30' }] : []);
      if (source === 'system') {
        assert.equal(update[1], '2026-09-30');
        assert.equal(update[7], 11);
        assert.equal(new Date(update[5]).toISOString(), new Date(end).toISOString());
        assert.deepEqual(JSON.parse(update[10]), snapshot);
      } else assert.equal(update, null);
    } finally { restore(); }
  });
}
