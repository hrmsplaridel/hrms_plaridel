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
