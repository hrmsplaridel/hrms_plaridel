'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  endDepartmentHeadPeriod,
  saveDepartmentHeadPeriod,
} = require('../src/services/positionDepartmentHeadPeriods');

const IDS = {
  actor: '11111111-1111-4111-8111-111111111111',
  position: '22222222-2222-4222-8222-222222222222',
  department: '33333333-3333-4333-8333-333333333333',
  period: '44444444-4444-4444-8444-444444444444',
};

test('creating a Department Head period preserves its effective range', async () => {
  const calls = [];
  const db = {
    async query(sql, params) {
      const text = String(sql);
      calls.push({ text, params });
      if (text.includes('SELECT id FROM departments')) {
        return { rowCount: 1, rows: [{ id: IDS.department }] };
      }
      if (text.includes('INSERT INTO position_department_head_periods')) {
        return {
          rowCount: 1,
          rows: [{
            id: IDS.period,
            position_id: IDS.position,
            department_id: IDS.department,
            effective_from: '2026-08-01',
            effective_to: null,
            is_active: true,
          }],
        };
      }
      if (text.startsWith('UPDATE positions p')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const period = await saveDepartmentHeadPeriod(db, {
    actorId: IDS.actor,
    positionId: IDS.position,
    departmentId: IDS.department,
    effectiveFrom: '2026-08-01',
  });

  assert.equal(period.id, IDS.period);
  const insert = calls.find(({ text }) =>
    text.includes('INSERT INTO position_department_head_periods')
  );
  assert.deepEqual(insert.params, [
    IDS.position,
    IDS.department,
    '2026-08-01',
    null,
    IDS.actor,
  ]);
});

test('ending a current designation closes it on the previous day', async () => {
  const calls = [];
  const db = {
    async query(sql, params) {
      const text = String(sql);
      calls.push({ text, params });
      if (text.startsWith('SELECT id, effective_from')) {
        return {
          rowCount: 1,
          rows: [{ id: IDS.period, effective_from: '2026-01-01' }],
        };
      }
      if (text.includes('SET effective_to')) {
        return { rowCount: 1, rows: [] };
      }
      if (text.startsWith('UPDATE positions p')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  await endDepartmentHeadPeriod(db, {
    positionId: IDS.position,
    periodId: IDS.period,
    effectiveDate: '2026-08-31',
  });

  const close = calls.find(({ text }) => text.includes('SET effective_to'));
  assert.deepEqual(close.params, [IDS.period, '2026-08-30']);
});

test('cancelling a future designation archives it without inventing history', async () => {
  const calls = [];
  const db = {
    async query(sql, params) {
      const text = String(sql);
      calls.push({ text, params });
      if (text.startsWith('SELECT id, effective_from')) {
        return {
          rowCount: 1,
          rows: [{ id: IDS.period, effective_from: '2026-09-15' }],
        };
      }
      if (text.includes('SET is_active = false')) {
        return { rowCount: 1, rows: [] };
      }
      if (text.startsWith('UPDATE positions p')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  await endDepartmentHeadPeriod(db, {
    positionId: IDS.position,
    periodId: IDS.period,
    effectiveDate: '2026-08-31',
  });

  assert.equal(
    calls.some(({ text }) => text.includes('SET is_active = false')),
    true
  );
  assert.equal(calls.some(({ text }) => text.includes('SET effective_to')), false);
});
