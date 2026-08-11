const test = require('node:test');
const assert = require('node:assert/strict');

const {
  evaluateLocatorCoverage,
  expectedLocatorSlotsForShift,
  locatorCoverageSegments,
  locatorCoversExpectedShiftSlots,
} = require('../src/services/locatorCoverage');

const REGULAR_SHIFT = {
  punchMode: 'full_day',
  startMinutes: 8 * 60,
  endMinutes: 17 * 60,
  breakEndMinutes: 13 * 60,
  workingDays: [1, 2, 3, 4, 5],
};

test('locator coverage requires the expected slots for the assigned shift', () => {
  assert.deepEqual(
    expectedLocatorSlotsForShift(REGULAR_SHIFT),
    ['am_in', 'am_out', 'pm_in', 'pm_out']
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(
      { am_in: true, am_out: true, pm_in: true, pm_out: true },
      REGULAR_SHIFT
    ),
    true
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(
      { pm_in: true, pm_out: true },
      REGULAR_SHIFT
    ),
    false
  );
});

test('PM-only and AM-only locator coverage follows the shift punch mode', () => {
  assert.equal(
    locatorCoversExpectedShiftSlots(
      { coverage: { pm_in: true, pm_out: true } },
      {
        punch_mode: 'auto',
        start_time: '18:00:00',
        end_time: '19:00:00',
      }
    ),
    true
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(
      { am_in: true, am_out: true },
      { punchMode: 'am_only' }
    ),
    true
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(
      { pm_in: true, pm_out: true },
      { punchMode: 'am_only' }
    ),
    false
  );
});

test('single-session shifts require their configured in and out locator slots', () => {
  assert.deepEqual(
    expectedLocatorSlotsForShift({ punchMode: 'single_session' }),
    ['am_in', 'pm_out']
  );
  assert.equal(
    locatorCoversExpectedShiftSlots(
      { segments: ['AM IN', 'PM OUT'] },
      { punchMode: 'single_session' }
    ),
    true
  );
});

test('approved locator slips on the same date can jointly cover a shift', () => {
  const result = evaluateLocatorCoverage({
    locators: [
      { coverage: { pm_in: true } },
      { coverage: { pm_out: true } },
    ],
    shiftInfo: { punchMode: 'pm_only' },
  });

  assert.equal(result.isFullCoverage, true);
  assert.deepEqual(result.missingSlots, []);
  assert.deepEqual(locatorCoverageSegments(result.coverage), ['PM in', 'PM out']);
});

test('holiday and working-day context changes the expected locator slots', () => {
  assert.deepEqual(
    expectedLocatorSlotsForShift(
      REGULAR_SHIFT,
      { coverage: 'am_only' },
      '2026-06-16'
    ),
    ['pm_in', 'pm_out']
  );
  assert.deepEqual(
    expectedLocatorSlotsForShift(REGULAR_SHIFT, null, '2026-06-14'),
    [],
    'Sunday is not a working date for a Monday-Friday shift'
  );
  assert.equal(
    evaluateLocatorCoverage({
      locator: { am_in: true, am_out: true, pm_in: true, pm_out: true },
      shiftInfo: REGULAR_SHIFT,
      date: '2026-06-14',
    }).isFullCoverage,
    false,
    'locator slots must not create full coverage on a rest day'
  );
});
