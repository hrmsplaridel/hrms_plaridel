'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  loadHolidayOverlayMap,
  resolveAttendanceHolidayOverlay,
} = require('../src/services/holidayOverlay');

test('holiday overlay expands ranges and gives dated holidays priority over recurring templates', async () => {
  const client = {
    async query(sql, params) {
      assert.match(String(sql), /is_active = true/);
      assert.deepEqual(params, ['2026-08-01', '2026-08-31']);
      return {
        rows: [
          {
            id: 'dated',
            name: 'Local Foundation Day',
            holiday_type: 'local',
            date_from: '2026-08-12',
            date_to: '2026-08-12',
            recurring: false,
            coverage: 'whole_day',
          },
          {
            id: 'recurring',
            name: 'Recurring Template',
            holiday_type: 'regular',
            date_from: '2020-08-12',
            date_to: '2020-08-13',
            recurring: true,
            coverage: 'whole_day',
          },
        ],
      };
    },
  };

  const overlays = await loadHolidayOverlayMap(
    client,
    '2026-08-01',
    '2026-08-31'
  );

  assert.equal(overlays.get('2026-08-12').id, 'dated');
  assert.equal(overlays.get('2026-08-13').id, 'recurring');
});

test('holiday overlay defaults to whole-day coverage on a pre-coverage schema', async () => {
  let calls = 0;
  const client = {
    async query(sql) {
      calls += 1;
      if (calls === 1) {
        const error = new Error('column coverage does not exist');
        error.code = '42703';
        throw error;
      }
      assert.match(String(sql), /whole_day/);
      return {
        rows: [{
          id: 'legacy',
          name: 'Legacy Holiday',
          holiday_type: 'regular',
          date_from: '2026-08-21',
          date_to: '2026-08-21',
          recurring: false,
          coverage: 'whole_day',
        }],
      };
    },
  };

  const overlays = await loadHolidayOverlayMap(
    client,
    '2026-08-21',
    '2026-08-21'
  );

  assert.equal(calls, 2);
  assert.equal(overlays.get('2026-08-21').coverage, 'whole_day');
});

test('current holiday configuration overrides stored attendance status without erasing punches', () => {
  const record = {
    status: 'late',
    time_in: '2026-08-21T00:15:00.000Z',
  };
  const resolved = resolveAttendanceHolidayOverlay(record, {
    id: 'holiday-id',
    name: 'Ninoy Aquino Day',
    holiday_type: 'special',
    coverage: 'whole_day',
  });

  assert.equal(resolved.status, 'holiday');
  assert.equal(resolved.holidayId, 'holiday-id');
  assert.equal(record.time_in, '2026-08-21T00:15:00.000Z');
});

test('deleted holiday restores legacy rows from their physical punches', () => {
  assert.deepEqual(
    resolveAttendanceHolidayOverlay(
      { status: 'holiday', time_in: '2026-08-21T00:00:00.000Z' },
      null
    ),
    {
      status: 'present',
      holidayId: null,
      holidayName: null,
      holidayType: null,
      coverage: null,
      staleStoredHoliday: true,
    }
  );
  assert.equal(
    resolveAttendanceHolidayOverlay({ status: 'holiday' }, null).status,
    'absent'
  );
});
