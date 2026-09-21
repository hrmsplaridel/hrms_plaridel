'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  assertFinalLeaveReviewer,
  assertLeaveSubmissionReviewer,
  resolveFinalLeaveReviewers,
} = require('../src/services/leaveFinalReviewerService');

const applicant = '11111111-1111-4111-8111-111111111111';
const primary = '22222222-2222-4222-8222-222222222222';
const backup = '33333333-3333-4333-8333-333333333333';

function dbWithReviewers(ids) {
  return {
    async query(sql) {
      if (String(sql).includes('FROM positions p')) {
        return { rows: ids.filter((id) => id === primary).map((id) => ({ id, name: 'Primary' })) };
      }
      if (String(sql).includes('FROM leave_final_reviewer_backups')) {
        return { rows: ids.filter((id) => id === backup).map((id) => ({ id, name: 'Backup' })) };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    },
  };
}

test('final review resolves the official position holder and configured backups', async () => {
  const reviewers = await resolveFinalLeaveReviewers(dbWithReviewers([primary, backup]));
  assert.deepEqual(reviewers.map((reviewer) => reviewer.id), [primary, backup]);
});

test('an applicant cannot sign or decide their own leave', async () => {
  await assert.rejects(
    assertFinalLeaveReviewer(dbWithReviewers([primary]), applicant, applicant),
    (error) => error.statusCode === 403
  );
});

test('only an assigned final reviewer may decide leave', async () => {
  await assert.rejects(
    assertFinalLeaveReviewer(dbWithReviewers([primary, backup]), applicant, '44444444-4444-4444-8444-444444444444'),
    (error) => error.statusCode === 403
  );
  await assertFinalLeaveReviewer(dbWithReviewers([primary, backup]), applicant, backup);
});

test('approval stays pending when no final reviewer is configured', async () => {
  await assert.rejects(
    assertFinalLeaveReviewer(dbWithReviewers([]), applicant, primary),
    (error) => error.statusCode === 409
  );
});

test('submission needs a final reviewer other than the applicant', async () => {
  await assert.rejects(
    assertLeaveSubmissionReviewer(dbWithReviewers([]), applicant),
    (error) => error.statusCode === 409 && /final leave reviewer/i.test(error.message)
  );
  await assert.rejects(
    assertLeaveSubmissionReviewer(dbWithReviewers([primary]), primary),
    (error) => error.statusCode === 409 && /final leave reviewer/i.test(error.message)
  );
  await assertLeaveSubmissionReviewer(dbWithReviewers([primary, backup]), primary);
  await assertLeaveSubmissionReviewer(dbWithReviewers([backup]), applicant);
});
