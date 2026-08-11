const test = require('node:test');
const assert = require('node:assert/strict');

const {
  assertCoverageMatchesRequestedDays,
  normalizeCoverageDates,
  removeApprovedLeaveCoverage,
  replaceApprovedLeaveCoverage,
} = require('../src/services/leaveDtrCoverage');

const EMPLOYEE_ID = '00000000-0000-0000-0000-000000000101';
const REQUEST_ID = '00000000-0000-0000-0000-000000000201';
const ACTOR_ID = '00000000-0000-0000-0000-000000000301';

test('coverage dates are unique, sorted, and must match the reserved request days', () => {
  assert.deepEqual(
    normalizeCoverageDates(['2026-08-05', '2026-08-04', '2026-08-05T00:00:00Z']),
    ['2026-08-04', '2026-08-05']
  );
  assert.deepEqual(
    assertCoverageMatchesRequestedDays(['2026-08-04', '2026-08-05'], 2),
    { dates: ['2026-08-04', '2026-08-05'], days: 2 }
  );
  assert.throws(
    () => assertCoverageMatchesRequestedDays(['2026-08-04'], 2),
    /server now counts 1 working day/
  );
});

test('approval coverage rejects a date with real attendance before writing coverage', async () => {
  const queries = [];
  const client = {
    async query(sql) {
      const text = String(sql);
      queries.push(text);
      if (text.includes('pg_advisory_xact_lock')) return { rows: [], rowCount: 1 };
      if (text.includes('FROM locator_slips')) return { rows: [], rowCount: 0 };
      if (!text.includes('FROM dtr_daily_summary')) {
        throw new Error('Unexpected query: ' + text);
      }
      return {
        rows: [{ attendance_date: '2026-08-04', status: 'present', has_time_in: true }],
        rowCount: 1,
      };
    },
  };

  await assert.rejects(
    () => replaceApprovedLeaveCoverage(client, {
      employeeId: EMPLOYEE_ID,
      leaveRequestId: REQUEST_ID,
      dates: ['2026-08-04'],
      actorUserId: ACTOR_ID,
    }),
    /attendance already exists on 2026-08-04/
  );
  assert.equal(queries.some((sql) => /FROM dtr_daily_summary/.test(sql)), true);
  assert.equal(queries.some((sql) => /INSERT INTO dtr_leave_coverage/.test(sql)), false);
});

test('approval coverage rejects a date already covered by an approved locator', async () => {
  const queries = [];
  const client = {
    async query(sql) {
      const text = String(sql);
      queries.push(text);
      if (text.includes('pg_advisory_xact_lock')) return { rows: [], rowCount: 1 };
      if (text.includes('FROM locator_slips')) {
        return {
          rows: [{
            id: '00000000-0000-0000-0000-000000000401',
            slip_date: '2026-08-04',
            request_type: 'locator',
            am_in: true,
            am_out: true,
            pm_in: false,
            pm_out: false,
          }],
          rowCount: 1,
        };
      }
      throw new Error('Unexpected query: ' + text);
    },
  };

  await assert.rejects(
    () => replaceApprovedLeaveCoverage(client, {
      employeeId: EMPLOYEE_ID,
      leaveRequestId: REQUEST_ID,
      dates: ['2026-08-04'],
      actorUserId: ACTOR_ID,
    }),
    /approved locator coverage already exists on 2026-08-04/
  );
  assert.equal(queries.some((sql) => /FROM dtr_daily_summary/.test(sql)), false);
  assert.equal(queries.some((sql) => /INSERT INTO dtr_leave_coverage/.test(sql)), false);
});

test('approval stores coverage without inserting or updating the underlying DTR row', async () => {
  const queries = [];
  const client = {
    async query(sql) {
      const text = String(sql);
      queries.push(text);
      if (text.includes('pg_advisory_xact_lock')) return { rows: [], rowCount: 1 };
      if (text.includes('FROM locator_slips')) return { rows: [], rowCount: 0 };
      if (text.includes('FROM dtr_daily_summary')) return { rows: [], rowCount: 0 };
      if (text.includes('FROM dtr_leave_coverage') && text.includes('leave_request_id <>')) {
        return { rows: [], rowCount: 0 };
      }
      if (text.startsWith('DELETE FROM dtr_leave_coverage')) {
        return { rows: [], rowCount: 0 };
      }
      if (text.includes('INSERT INTO dtr_leave_coverage')) {
        return {
          rows: [
            { attendance_date: '2026-08-04' },
            { attendance_date: '2026-08-05' },
          ],
          rowCount: 2,
        };
      }
      throw new Error(`Unexpected query: ${text}`);
    },
  };

  const inserted = await replaceApprovedLeaveCoverage(client, {
    employeeId: EMPLOYEE_ID,
    leaveRequestId: REQUEST_ID,
    dates: ['2026-08-04', '2026-08-05'],
    actorUserId: ACTOR_ID,
  });

  assert.deepEqual(inserted, ['2026-08-04', '2026-08-05']);
  assert.equal(
    queries.some((sql) => /(?:INSERT INTO|UPDATE) dtr_daily_summary/.test(sql)),
    false
  );
});

test('revocation removes only leave coverage', async () => {
  let executedSql = '';
  const client = {
    async query(sql) {
      executedSql = String(sql);
      return { rows: [], rowCount: 2 };
    },
  };

  const removed = await removeApprovedLeaveCoverage(client, REQUEST_ID);
  assert.equal(removed, 2);
  assert.match(executedSql, /^DELETE FROM dtr_leave_coverage/);
  assert.doesNotMatch(executedSql, /dtr_daily_summary/);
});
