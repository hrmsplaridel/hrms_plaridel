'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ShiftLifecycleError,
  MAX_SHIFT_GRACE_PERIOD_MINUTES,
  changedShiftScheduleFields,
  deleteUnusedShift,
  ensureCompatiblePunchModeSchedule,
  ensureShiftDeactivationAllowed,
  ensureShiftScheduleChangeAllowed,
  ensureSupportedShiftRange,
  parseShiftActiveInput,
  parseShiftGracePeriodInput,
  parseShiftTimeInput,
  parseShiftWorkingDaysInput,
  resolvedPunchModeForSchedule,
  shiftDeactivationCountsSql,
  shiftDependencyCountsSql,
} = require('../src/services/shiftLifecycle');

const SHIFT_ID = '22222222-2222-4222-8222-222222222222';

function shiftRow() {
  return {
    id: SHIFT_ID,
    shift_number: 1,
    name: 'Morning Shift',
    start_time: '08:00:00',
    end_time: '17:00:00',
    break_end: '13:00:00',
    punch_mode: 'full_day',
    grace_period_minutes: 10,
    working_days: [1, 2, 3, 4, 5],
    is_active: true,
  };
}

test('shift schedule comparison ignores equivalent time and weekday formats', () => {
  assert.deepEqual(
    changedShiftScheduleFields(shiftRow(), {
      start_time: '08:00:00.000000',
      end_time: '17:00:00',
      break_end: '13:00:00',
      punch_mode: 'FULL_DAY',
      grace_period_minutes: '10',
      working_days: [5, 4, 3, 2, 1, 1],
    }),
    []
  );
});

test('shift schedule comparison reports only changed schedule fields', () => {
  assert.deepEqual(
    changedShiftScheduleFields(shiftRow(), {
      start_time: '09:00:00',
      grace_period_minutes: 15,
      working_days: [1, 2, 3, 4, 5],
    }),
    ['start_time', 'grace_period_minutes']
  );
});

test('same-day shift range accepts an end time later than its start time', () => {
  assert.doesNotThrow(() => ensureSupportedShiftRange('08:00:00', '17:00:00'));
});

test('overnight shift range is rejected with a field-specific error', () => {
  assert.throws(
    () => ensureSupportedShiftRange('22:00:00', '06:00:00'),
    (error) => {
      assert.ok(error instanceof ShiftLifecycleError);
      assert.equal(error.statusCode, 400);
      assert.equal(
        error.details.fields.end_time,
        'End Time must be later than Start Time.'
      );
      assert.match(error.message, /overnight shifts are not currently supported/i);
      return true;
    }
  );
});

test('equal shift start and end times are rejected', () => {
  assert.throws(
    () => ensureSupportedShiftRange('08:00:00', '08:00:00'),
    (error) => error instanceof ShiftLifecycleError && error.statusCode === 400
  );
});

test('shift time input normalizes valid 24-hour values', () => {
  assert.equal(
    parseShiftTimeInput('08:30', {
      field: 'start_time',
      label: 'Start Time',
    }),
    '08:30:00'
  );
  assert.equal(
    parseShiftTimeInput('17:15:45', {
      field: 'end_time',
      label: 'End Time',
    }),
    '17:15:45'
  );
});

test('missing required shift time is rejected instead of defaulted', () => {
  assert.throws(
    () => parseShiftTimeInput(null, {
      field: 'start_time',
      label: 'Start Time',
    }),
    (error) => {
      assert.ok(error instanceof ShiftLifecycleError);
      assert.equal(error.statusCode, 400);
      assert.equal(error.details.fields.start_time, 'Start Time is required.');
      return true;
    }
  );
});

test('malformed shift time is rejected instead of defaulted', () => {
  assert.throws(
    () => parseShiftTimeInput('8am', {
      field: 'start_time',
      label: 'Start Time',
    }),
    (error) => {
      assert.ok(error instanceof ShiftLifecycleError);
      assert.equal(error.statusCode, 400);
      assert.match(error.details.fields.start_time, /24-hour format/);
      return true;
    }
  );
});

test('empty optional PM Start is preserved as null', () => {
  assert.equal(
    parseShiftTimeInput('', {
      field: 'break_end',
      label: 'PM Start',
      required: false,
    }),
    null
  );
});

test('working days require unique JSON integers from 1 through 7', () => {
  assert.deepEqual(parseShiftWorkingDaysInput([5, 1, 3]), [1, 3, 5]);
  for (const invalid of [[], [1, 1], [0, 1], [1, 8], ['1', 2], 'weekdays']) {
    assert.throws(
      () => parseShiftWorkingDaysInput(invalid),
      (error) => {
        assert.ok(error instanceof ShiftLifecycleError);
        assert.equal(error.statusCode, 400);
        assert.ok(error.details.fields.working_days);
        return true;
      }
    );
  }
});

test('grace period requires a bounded whole JSON number', () => {
  assert.equal(parseShiftGracePeriodInput(15), 15);
  for (const invalid of [-1, 2.5, '15', 'abc', MAX_SHIFT_GRACE_PERIOD_MINUTES + 1]) {
    assert.throws(
      () => parseShiftGracePeriodInput(invalid),
      (error) => {
        assert.ok(error instanceof ShiftLifecycleError);
        assert.equal(error.statusCode, 400);
        assert.ok(error.details.fields.grace_period_minutes);
        return true;
      }
    );
  }
});

test('active status accepts only JSON booleans', () => {
  assert.equal(parseShiftActiveInput(true), true);
  assert.equal(parseShiftActiveInput(false), false);
  for (const invalid of ['false', 0, 1, null]) {
    assert.throws(
      () => parseShiftActiveInput(invalid),
      (error) => {
        assert.ok(error instanceof ShiftLifecycleError);
        assert.equal(error.statusCode, 400);
        assert.ok(error.details.fields.is_active);
        return true;
      }
    );
  }
});

test('full-day shift requires a PM Start', () => {
  assert.throws(
    () => ensureCompatiblePunchModeSchedule({
      startTime: '08:00:00',
      endTime: '17:00:00',
      breakEnd: null,
      punchMode: 'full_day',
    }),
    (error) => {
      assert.ok(error instanceof ShiftLifecycleError);
      assert.equal(error.statusCode, 400);
      assert.match(error.details.fields.break_end, /return time after lunch/i);
      return true;
    }
  );
});

test('full-day shift accepts a PM Start between noon and End Time', () => {
  assert.equal(
    ensureCompatiblePunchModeSchedule({
      startTime: '08:00:00',
      endTime: '17:00:00',
      breakEnd: '13:00:00',
      punchMode: 'full_day',
    }),
    'full_day'
  );
});

test('non-full-day punch modes reject PM Start', () => {
  for (const punchMode of ['am_only', 'pm_only', 'single_session']) {
    assert.throws(
      () => ensureCompatiblePunchModeSchedule({
        startTime: punchMode === 'pm_only' ? '13:00:00' : '08:00:00',
        endTime: punchMode === 'pm_only' ? '17:00:00' : '12:00:00',
        breakEnd: '11:00:00',
        punchMode,
      }),
      (error) => error instanceof ShiftLifecycleError && error.statusCode === 400
    );
  }
});

test('PM-only shift requires an afternoon Start Time', () => {
  assert.throws(
    () => ensureCompatiblePunchModeSchedule({
      startTime: '08:00:00',
      endTime: '12:00:00',
      breakEnd: null,
      punchMode: 'pm_only',
    }),
    (error) => {
      assert.ok(error instanceof ShiftLifecycleError);
      assert.match(error.details.fields.start_time, /12:00 PM/);
      return true;
    }
  );
});

test('auto mode resolves before PM Start compatibility is validated', () => {
  assert.equal(
    resolvedPunchModeForSchedule({
      startTime: '13:00:00',
      endTime: '17:00:00',
      breakEnd: null,
      punchMode: 'auto',
    }),
    'pm_only'
  );
  assert.equal(
    resolvedPunchModeForSchedule({
      startTime: '08:00:00',
      endTime: '17:00:00',
      breakEnd: '13:00:00',
      punchMode: 'auto',
    }),
    'full_day'
  );
});

test('used shift rejects a schedule change with actionable details', async () => {
  const db = {
    async query(sql, params) {
      assert.match(String(sql), /FROM assignments/);
      assert.deepEqual(params, [SHIFT_ID]);
      return { rows: [{ assignment_history_count: 3 }], rowCount: 1 };
    },
  };

  await assert.rejects(
    ensureShiftScheduleChangeAllowed(db, {
      shiftId: SHIFT_ID,
      lockedShift: shiftRow(),
      changes: { end_time: '18:00:00' },
    }),
    (error) => {
      assert.ok(error instanceof ShiftLifecycleError);
      assert.equal(error.statusCode, 409);
      assert.equal(error.details.assignment_history_count, 3);
      assert.deepEqual(error.details.changed_fields, ['end_time']);
      assert.match(error.message, /create a new shift/i);
      return true;
    }
  );
});

test('used shift permits updates that do not change its schedule', async () => {
  let queryCount = 0;
  const db = {
    async query() {
      queryCount += 1;
      throw new Error('Assignment history should not be queried');
    },
  };

  const result = await ensureShiftScheduleChangeAllowed(db, {
    shiftId: SHIFT_ID,
    lockedShift: shiftRow(),
    changes: { start_time: '08:00:00', working_days: [1, 2, 3, 4, 5] },
  });

  assert.equal(result.id, SHIFT_ID);
  assert.equal(queryCount, 0);
});

test('unused shift permits schedule changes', async () => {
  const db = {
    async query() {
      return { rows: [{ assignment_history_count: 0 }], rowCount: 1 };
    },
  };

  const result = await ensureShiftScheduleChangeAllowed(db, {
    shiftId: SHIFT_ID,
    lockedShift: shiftRow(),
    changes: { working_days: [2, 3, 4, 5, 6] },
  });

  assert.equal(result.id, SHIFT_ID);
});

test('shift deactivation dependency SQL is bounded by the official date', () => {
  const sql = shiftDeactivationCountsSql('shift.id', '$4');
  assert.match(sql, /assignment\.effective_to >= \$4::date/);
  assert.match(sql, /policy_period\.effective_to >= \$4::date/);
  assert.match(sql, /assignment\.is_active = true/);
  assert.match(sql, /policy_period\.is_active = true/);
});

test('current or future dependencies block shift deactivation', async () => {
  const db = {
    async query(sql, params) {
      assert.match(String(sql), /deactivation_assignments/);
      assert.deepEqual(params, [SHIFT_ID, '2026-09-03']);
      return {
        rows: [{
          deactivation_assignments: 2,
          deactivation_policy_periods: 1,
        }],
        rowCount: 1,
      };
    },
  };

  await assert.rejects(
    ensureShiftDeactivationAllowed(db, {
      shiftId: SHIFT_ID,
      effectiveDate: '2026-09-03',
      lockedShift: shiftRow(),
    }),
    (error) => {
      assert.ok(error instanceof ShiftLifecycleError);
      assert.equal(error.statusCode, 409);
      assert.deepEqual(error.details.dependencies, {
        assignments: 2,
        policy_periods: 1,
      });
      assert.equal(error.details.official_date, '2026-09-03');
      assert.equal(error.details.blockers.length, 2);
      return true;
    }
  );
});

test('expired or inactive dependencies allow shift deactivation', async () => {
  const db = {
    async query() {
      return {
        rows: [{
          deactivation_assignments: 0,
          deactivation_policy_periods: 0,
        }],
        rowCount: 1,
      };
    },
  };

  const result = await ensureShiftDeactivationAllowed(db, {
    shiftId: SHIFT_ID,
    effectiveDate: '2026-09-03',
    lockedShift: shiftRow(),
  });

  assert.equal(result.id, SHIFT_ID);
});

test('permanent deletion dependency SQL checks all historical references', () => {
  const sql = shiftDependencyCountsSql('shift.id');
  assert.match(sql, /FROM assignments dependency/);
  assert.match(sql, /FROM dtr_daily_summary dependency/);
  assert.match(sql, /FROM policy_assignments dependency/);
  assert.match(sql, /dependency\.shift_id = shift\.id/);
});

test('used shift cannot be permanently deleted', async () => {
  let deleteCalled = false;
  const db = {
    async query(sql, params) {
      assert.deepEqual(params, [SHIFT_ID]);
      if (/^DELETE FROM shifts/.test(String(sql))) {
        deleteCalled = true;
      }
      return {
        rows: [{
          dependency_assignments: 2,
          dependency_dtr_records: 5,
          dependency_policy_periods: 1,
        }],
        rowCount: 1,
      };
    },
  };

  await assert.rejects(
    deleteUnusedShift(db, {
      shiftId: SHIFT_ID,
      lockedShift: shiftRow(),
    }),
    (error) => {
      assert.ok(error instanceof ShiftLifecycleError);
      assert.equal(error.statusCode, 409);
      assert.deepEqual(error.details.dependencies, {
        assignments: 2,
        dtr_records: 5,
        policy_periods: 1,
      });
      assert.equal(error.details.blockers.length, 3);
      return true;
    }
  );
  assert.equal(deleteCalled, false);
});

test('completely unused shift can be permanently deleted', async () => {
  const queries = [];
  const db = {
    async query(sql, params) {
      queries.push({ sql: String(sql), params });
      if (/^DELETE FROM shifts/.test(String(sql))) {
        return { rows: [], rowCount: 1 };
      }
      return {
        rows: [{
          dependency_assignments: 0,
          dependency_dtr_records: 0,
          dependency_policy_periods: 0,
        }],
        rowCount: 1,
      };
    },
  };

  const result = await deleteUnusedShift(db, {
    shiftId: SHIFT_ID,
    lockedShift: shiftRow(),
  });

  assert.equal(result.id, SHIFT_ID);
  assert.equal(queries.length, 2);
  assert.match(queries[1].sql, /^DELETE FROM shifts/);
  assert.deepEqual(queries[1].params, [SHIFT_ID]);
});
