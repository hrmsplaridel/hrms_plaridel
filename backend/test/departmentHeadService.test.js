const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getDepartmentReviewSnapshot,
  getDepartmentReviewSnapshotForDate,
} = require('../src/services/departmentHeadService');
const { todayInHrmsTimezone } = require('../src/utils/dateRangeParser');

const EMPLOYEE_ID = '00000000-0000-0000-0000-000000000101';
const DEPARTMENT_ID = '00000000-0000-0000-0000-000000000201';
const HEAD_ID = '00000000-0000-0000-0000-000000000301';
const BACKUP_ID = '00000000-0000-0000-0000-000000000302';

function reviewerClient({ primary = true, backup = true, excludePrimary = false } = {}) {
  const calls = [];
  return {
    calls,
    async query(sql, params) {
      const text = String(sql);
      calls.push({ text, params });
      if (text.includes('LEFT JOIN departments d')) {
        return {
          rows: [{
            department_id: DEPARTMENT_ID,
            department_name: 'Human Resources',
          }],
        };
      }
      if (text.includes('p.is_department_head = true')) {
        return primary && !excludePrimary
          ? { rows: [{ reviewer_id: HEAD_ID, reviewer_name: 'HR Head' }] }
          : { rows: [] };
      }
      if (text.includes('FROM department_reviewer_backups b')) {
        return backup
          ? {
              rows: [{
                reviewer_id: BACKUP_ID,
                reviewer_name: 'Backup Reviewer',
                backup_rank: 1,
              }],
            }
          : { rows: [] };
      }
      throw new Error(`Unexpected query: ${text.slice(0, 100)}`);
    },
  };
}

test('review snapshot resolves the explicit Head and effective backups', async () => {
  const client = reviewerClient();
  const snapshot = await getDepartmentReviewSnapshot(client, EMPLOYEE_ID);

  assert.equal(snapshot.departmentHeadUserId, HEAD_ID);
  assert.equal(snapshot.departmentId, DEPARTMENT_ID);
  assert.deepEqual(snapshot.reviewerUserIds, [HEAD_ID, BACKUP_ID]);
  assert.deepEqual(snapshot.reviewers.map((reviewer) => reviewer.reviewerRole), [
    'primary',
    'backup',
  ]);
  assert.equal(
    client.calls.every(({ text }) => !/LOWER\(p\.name\)|ILIKE/i.test(text)),
    true
  );
});

test('review snapshot retains the department when no reviewers are configured', async () => {
  const snapshot = await getDepartmentReviewSnapshot(
    reviewerClient({ primary: false, backup: false }),
    EMPLOYEE_ID
  );

  assert.equal(snapshot.departmentHeadUserId, null);
  assert.equal(snapshot.departmentId, DEPARTMENT_ID);
  assert.deepEqual(snapshot.reviewerUserIds, []);
  assert.deepEqual(snapshot.reviewers, []);
});

test('historical snapshot uses reviewers effective on the request date', async () => {
  const client = reviewerClient();
  const snapshot = await getDepartmentReviewSnapshotForDate(
    client,
    EMPLOYEE_ID,
    '2026-06-20'
  );

  assert.equal(snapshot.departmentHeadUserId, HEAD_ID);
  assert.deepEqual(client.calls[0].params, [EMPLOYEE_ID, '2026-06-20']);
  assert.equal(
    client.calls.slice(1).every(({ params }) => params[1] === '2026-06-20'),
    true
  );
});

test('a backup becomes the routing reviewer when the requester is the Head', async () => {
  const snapshot = await getDepartmentReviewSnapshotForDate(
    reviewerClient({ excludePrimary: true }),
    HEAD_ID,
    '2026-08-30'
  );

  assert.equal(snapshot.departmentHeadUserId, BACKUP_ID);
  assert.deepEqual(snapshot.reviewerUserIds, [BACKUP_ID]);
});

test('Department Head resolution uses the Manila date across the UTC boundary', async () => {
  const instant = new Date('2026-08-29T16:30:00.000Z');
  const manilaDate = todayInHrmsTimezone(instant, 'Asia/Manila');
  const utcDate = todayInHrmsTimezone(instant, 'UTC');
  assert.equal(manilaDate, '2026-08-30');
  assert.equal(utcDate, '2026-08-29');

  const client = reviewerClient();
  await getDepartmentReviewSnapshot(client, EMPLOYEE_ID, manilaDate);

  assert.equal(
    client.calls.every(({ params }) => params[1] === '2026-08-30'),
    true
  );
});
