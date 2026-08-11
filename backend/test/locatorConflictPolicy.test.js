const test = require('node:test');
const assert = require('node:assert/strict');

const {
  conflictingDtrPunchSlots,
  findLocatorRequestConflicts,
  overlappingLocatorSlots,
} = require('../src/services/locatorConflictPolicy');

const EMPLOYEE_ID = '00000000-0000-0000-0000-000000000101';
const SLIP_ID = '00000000-0000-0000-0000-000000000201';

function conflictClient({
  locators = [],
  leaves = [],
  dtr = [],
} = {}) {
  return {
    async query(sql) {
      const text = String(sql);
      if (text.includes('pg_advisory_xact_lock')) {
        return { rows: [], rowCount: 1 };
      }
      if (text.includes('FROM locator_slips')) {
        return { rows: locators, rowCount: locators.length };
      }
      if (text.includes('FROM dtr_leave_coverage')) {
        return { rows: leaves, rowCount: leaves.length };
      }
      if (text.includes('FROM dtr_daily_summary')) {
        return { rows: dtr, rowCount: dtr.length };
      }
      throw new Error('Unexpected query: ' + text);
    },
  };
}

test('locator slot overlap is detected while complementary slots remain valid', () => {
  assert.deepEqual(
    overlappingLocatorSlots(
      { pm_in: true, pm_out: true },
      { am_in: true, am_out: true, pm_in: true }
    ),
    ['pm_in']
  );
  assert.deepEqual(
    overlappingLocatorSlots(
      { pm_in: true, pm_out: true },
      { am_in: true, am_out: true }
    ),
    []
  );
});

test('DTR conflict checks only physical punches in locator-covered slots', () => {
  assert.deepEqual(
    conflictingDtrPunchSlots(
      { pm_in: true, pm_out: true },
      {
        time_in: '2026-08-04T00:00:00.000Z',
        break_in: null,
        time_out: '2026-08-04T09:00:00.000Z',
      }
    ),
    ['pm_out']
  );
});

test('submission blocks overlapping active locator slots', async () => {
  const result = await findLocatorRequestConflicts(
    conflictClient({
      locators: [{
        id: SLIP_ID,
        status: 'pending_hr',
        request_type: 'locator',
        am_in: false,
        am_out: false,
        pm_in: true,
        pm_out: true,
      }],
    }),
    {
      employeeId: EMPLOYEE_ID,
      slipDate: '2026-08-04',
      slots: { pm_in: true, pm_out: true },
    }
  );

  assert.equal(result.ok, false);
  assert.equal(result.code, 'locator_slot_conflict');
  assert.deepEqual(result.conflicts.locator[0].slots, ['pm_in', 'pm_out']);
});

test('submission permits complementary AM and PM locator requests', async () => {
  const result = await findLocatorRequestConflicts(
    conflictClient({
      locators: [{
        id: SLIP_ID,
        status: 'approved',
        request_type: 'locator',
        am_in: true,
        am_out: true,
        pm_in: false,
        pm_out: false,
      }],
    }),
    {
      employeeId: EMPLOYEE_ID,
      slipDate: '2026-08-04',
      slots: { pm_in: true, pm_out: true },
    }
  );

  assert.equal(result.ok, true);
  assert.deepEqual(result.conflicts.locator, []);
});

test('submission blocks exact approved leave coverage and covered DTR punches', async () => {
  const leaveResult = await findLocatorRequestConflicts(
    conflictClient({
      leaves: [{ id: 'leave-1', leave_type: 'Vacation Leave' }],
    }),
    {
      employeeId: EMPLOYEE_ID,
      slipDate: '2026-08-04',
      slots: { am_in: true, am_out: true },
    }
  );
  assert.equal(leaveResult.code, 'approved_leave_conflict');

  const dtrResult = await findLocatorRequestConflicts(
    conflictClient({
      dtr: [{
        id: 'dtr-1',
        status: 'late',
        time_in: '2026-08-04T00:30:00.000Z',
        break_out: null,
        break_in: null,
        time_out: null,
        late_minutes: 30,
        undertime_minutes: 0,
      }],
    }),
    {
      employeeId: EMPLOYEE_ID,
      slipDate: '2026-08-04',
      slots: { am_in: true },
    }
  );
  assert.equal(dtrResult.code, 'dtr_punch_conflict');
  assert.deepEqual(dtrResult.conflicts.attendance[0].slots, ['am_in']);
});
