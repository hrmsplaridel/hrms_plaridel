'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  loadHolidayOverlayMap,
  resolveAttendanceHolidayOverlay,
} = require('../src/services/holidayOverlay');

function suspension(coverage, overrides = {}) {
  return {
    id: coverage,
    name: `${coverage} suspension`,
    date_from: '2026-09-09',
    date_to: '2026-09-09',
    holiday_type: 'work_suspension',
    recurring: false,
    coverage,
    ...overrides,
  };
}

for (const first of ['am_only', 'pm_only', 'whole_day']) {
  for (const second of ['am_only', 'pm_only', 'whole_day']) {
    test(`overlapping ${first} and ${second} coverage is combined without double counting`, async () => {
      const rows = [suspension(first), suspension(second, { id: 'second' })];
      const original = JSON.stringify(rows);
      const overlays = await loadHolidayOverlayMap(
        { query: async () => ({ rows }) }, '2026-09-09', '2026-09-09',
      );
      assert.equal(overlays.size, 1);
      const holiday = overlays.get('2026-09-09');
      assert.equal(holiday.coverage, first === second ? first : 'whole_day');
      assert.equal(holiday.id, rows[0].id);
      assert.equal(holiday.name, rows[0].name);
      assert.equal(JSON.stringify(rows), original);
    });
  }
}

test('coverage combines only on dates where the ranges overlap', async () => {
  const rows = [
    suspension('am_only', { date_from: '2026-09-08' }),
    suspension('pm_only', { date_to: '2026-09-10' }),
  ];
  const overlays = await loadHolidayOverlayMap(
    { query: async () => ({ rows }) }, '2026-09-08', '2026-09-10',
  );
  assert.deepEqual([...overlays.values()].map((row) => row.coverage),
    ['am_only', 'whole_day', 'pm_only']);
});

test('recurring whole-day coverage is retained under a dated partial suspension label', async () => {
  const rows = [
    suspension('am_only', { id: 'dated' }),
    suspension('whole_day', {
      id: 'recurring', recurring: true, holiday_type: 'regular',
      date_from: '2020-09-09', date_to: '2020-09-09',
    }),
  ];
  const overlays = await loadHolidayOverlayMap(
    { query: async () => ({ rows }) }, '2026-09-09', '2026-09-09',
  );
  assert.equal(overlays.get('2026-09-09').id, 'dated');
  assert.equal(overlays.get('2026-09-09').coverage, 'whole_day');
});

test('removing one overlapping suspension restores only the remaining exemption', async () => {
  let rows = [suspension('am_only'), suspension('pm_only')];
  const client = { query: async () => ({ rows }) };
  const before = await loadHolidayOverlayMap(client, '2026-09-09', '2026-09-09');
  rows = [suspension('pm_only')];
  const after = await loadHolidayOverlayMap(client, '2026-09-09', '2026-09-09');
  assert.equal(before.get('2026-09-09').coverage, 'whole_day');
  assert.equal(after.get('2026-09-09').coverage, 'pm_only');
});

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
