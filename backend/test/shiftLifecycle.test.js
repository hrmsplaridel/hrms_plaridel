'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ShiftLifecycleError,
  changedShiftScheduleFields,
  deleteUnusedShift,
  ensureShiftDeactivationAllowed,
  ensureShiftScheduleChangeAllowed,
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
