const test = require('node:test');
const assert = require('node:assert/strict');

const {
  listLocatorWorkflowEvents,
  locatorHistoryTitle,
  normalizeLocatorRejectionReason,
  recordLocatorWorkflowEvent,
} = require('../src/services/locatorWorkflowHistory');

const SLIP_ID = '00000000-0000-0000-0000-000000000101';
const ACTOR_ID = '00000000-0000-0000-0000-000000000201';

test('locator rejection reasons are required, trimmed, and bounded', () => {
  assert.deepEqual(normalizeLocatorRejectionReason('   '), {
    valid: false,
    error: 'Rejection reason is required.',
  });
  assert.deepEqual(normalizeLocatorRejectionReason('  Missing itinerary  '), {
    valid: true,
    value: 'Missing itinerary',
  });
  assert.equal(normalizeLocatorRejectionReason('x'.repeat(1001)).valid, false);
});

test('recordLocatorWorkflowEvent writes a complete append-only event payload', async () => {
  const calls = [];
  const client = {
    async query(sql, params) {
      calls.push({ sql, params });
      return {
        rows: [{
          id: 'event-1',
          locator_slip_id: params[0],
          action: params[1],
        }],
      };
    },
  };

  await recordLocatorWorkflowEvent(client, {
    locatorSlipId: SLIP_ID,
    action: 'hr_rejected',
    fromStatus: 'pending_hr',
    toStatus: 'rejected_by_hr',
    actorId: ACTOR_ID,
    actorRole: 'hr',
    remarks: 'Missing supporting document.',
    metadata: { source: 'review' },
  });

  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /INSERT INTO locator_slip_history/);
  assert.deepEqual(calls[0].params, [
    SLIP_ID,
    'hr_rejected',
    'pending_hr',
    'rejected_by_hr',
    ACTOR_ID,
    null,
    'hr',
    'Missing supporting document.',
    '{"source":"review"}',
  ]);
});

test('history listing preserves database order and exposes readable titles', async () => {
  const client = {
    async query(sql, params) {
      assert.match(sql, /ORDER BY created_at ASC, id ASC/);
      assert.deepEqual(params, [SLIP_ID]);
      return {
        rows: [
          {
            id: 'event-1',
            locator_slip_id: SLIP_ID,
            action: 'submitted',
            actor_name_snapshot: 'Employee One',
            metadata: {},
            created_at: '2026-08-12T01:00:00.000Z',
          },
          {
            id: 'event-2',
            locator_slip_id: SLIP_ID,
            action: 'department_head_returned',
            actor_name_snapshot: 'Department Head',
            remarks: 'Correct the destination.',
            metadata: {},
            created_at: '2026-08-12T02:00:00.000Z',
          },
        ],
      };
    },
  };

  const events = await listLocatorWorkflowEvents(client, SLIP_ID);
  assert.equal(events.length, 2);
  assert.equal(events[0].title, 'Submitted');
  assert.equal(events[1].title, 'Returned by Department Head');
  assert.equal(locatorHistoryTitle('custom_action'), 'Custom Action');
});
