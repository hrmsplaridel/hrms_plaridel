const test = require('node:test');
const assert = require('node:assert/strict');

const {
  enqueueHolidayReconciliation,
  listPendingReconciliationMonths,
  monthsInRange,
  resolveReconciliationMonth,
  serviceMonthForDate,
} = require('../src/services/dtrMonthEndReconciliation');

test('attendance dates resolve to their first-of-month reconciliation key', () => {
  assert.equal(serviceMonthForDate('2026-07-31'), '2026-07-01');
  assert.equal(serviceMonthForDate('invalid'), null);
  assert.deepEqual(monthsInRange('2026-11-20', '2027-02-03'), [11, 12, 1, 2]);
});

test('holiday changes enqueue only completed months with existing DTR postings', async () => {
  const calls = [];
  const db = {
    async query(sql, params = []) {
      calls.push({ sql: String(sql), params });
      return {
        rows: [],
        rowCount: String(sql).includes('INSERT INTO dtr_month_end_reconciliation_queue')
          ? 3
          : 0,
      };
    },
  };

  const queued = await enqueueHolidayReconciliation(db, {
    dateFrom: '2026-07-12',
    dateTo: '2026-07-12',
    reason: 'holiday_created',
    metadata: { holiday_id: 'holiday-1' },
  });

  assert.equal(queued, 3);
  const insert = calls.find(({ sql }) =>
    sql.includes('INSERT INTO dtr_month_end_reconciliation_queue')
  );
  assert.ok(insert);
  assert.match(insert.sql, /FROM leave_attendance_deductions lad/);
  assert.match(insert.sql, /lad\.service_month </);
  assert.deepEqual(insert.params.slice(0, 2), ['2026-07-12', '2026-07-12']);
});

test('queued months expose a cutoff and reconciliation clears only older markers', async () => {
  const calls = [];
  const cutoff = new Date('2026-08-20T04:00:00.000Z');
  const db = {
    async query(sql, params = []) {
      const text = String(sql);
      calls.push({ sql: text, params });
      if (text.includes('SELECT service_month::text')) {
        return {
          rows: [{
            service_month: '2026-07-01',
            employee_count: 2,
            cutoff,
          }],
          rowCount: 1,
        };
      }
      if (text.includes('UPDATE dtr_month_end_reconciliation_queue')) {
        return { rows: [], rowCount: 2 };
      }
      return { rows: [], rowCount: 0 };
    },
  };

  const pending = await listPendingReconciliationMonths(db, {
    excludeServiceMonth: '2026-08-01',
  });
  assert.deepEqual(pending, [{
    serviceMonth: '2026-07-01',
    targetMonth: '2026-07',
    employeeCount: 2,
    cutoff,
  }]);

  const cleared = await resolveReconciliationMonth(db, {
    serviceMonth: '2026-07-01',
    cutoff,
  });
  assert.equal(cleared, 2);
  const update = calls.find(({ sql }) =>
    sql.includes('UPDATE dtr_month_end_reconciliation_queue')
  );
  assert.match(update.sql, /required_at <= \$2::timestamptz/);
  assert.equal(update.params[1], cutoff);
});
