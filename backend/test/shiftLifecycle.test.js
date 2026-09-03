'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ShiftLifecycleError,
  changedShiftScheduleFields,
  ensureShiftScheduleChangeAllowed,
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
