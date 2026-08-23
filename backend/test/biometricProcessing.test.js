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
    restore() {
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
    if (/ALTER TABLE shifts/i.test(text)) return { rows: [], rowCount: 0 };
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
    throw new Error(`Unexpected query after deleted-date suppression: ${sql}`);
  });

  try {
    const result = await service.processBiometricLogsToSummary(
      [employeeId],
      '2026-06-01',
      '2026-06-30',
    );

    assert.deepEqual(result, { inserted: 0, updated: 0 });
    assert.equal(queries.length, 2);
  } finally {
    restore();
  }
});
