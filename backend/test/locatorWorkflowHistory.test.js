const test = require('node:test');
const assert = require('node:assert/strict');

const {
  listLocatorWorkflowEvents,
  locatorHistoryTitle,
  normalizeLocatorRejectionReason,
  recordLocatorWorkflowEvent,
  mapLocatorWorkflowEvent,
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

  assert.equal(calls.length, 2);
  assert.match(calls[1].sql, /UPDATE user_notifications/);
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
      assert.match(sql, /JOIN locator_slips slip/);
      assert.match(sql, /ORDER BY history.created_at ASC, history.id ASC/);
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
  assert.equal(locatorHistoryTitle('mayor_reassigned'), 'Reassigned to Current Mayor');
});

for (const [action, decision, outcome] of [
  ['hr_approved', 'approve', 'Approved'],
  ['hr_rejected', 'reject', 'Rejected'],
  ['hr_returned', 'return', 'Returned'],
]) {
  test(`specific-person history uses the saved step and actual actor: ${action}`, () => {
    const event = mapLocatorWorkflowEvent({
      id: 'specific-event', action, actor_id: ACTOR_ID,
      actor_name_snapshot: 'Records Reviewer', actor_role: 'employee',
      workflow_snapshot: {
        steps: [{label: 'Records verification', assignee_source: 'specific_users'}],
        decisions: [{step: 0, action: decision, actor_id: ACTOR_ID}],
      },
    });
    assert.equal(event.title, `Records verification · ${outcome}`);
    assert.equal(event.actor_name, 'Records Reviewer');
    assert.equal(event.action, action, 'The stored audit action remains unchanged');
  });
}

test('ambiguous old-cycle history stays neutral rather than inventing an HR step', () => {
  const event = mapLocatorWorkflowEvent({
    action: 'hr_approved', actor_id: ACTOR_ID, actor_role: 'employee',
    workflow_snapshot: {
      steps: [{label: 'Current step', assignee_source: 'specific_users'}],
      decisions: [{step: 0, action: 'approve', actor_id: ACTOR_ID}],
      cycles: [{
        steps: [{label: 'Previous step', assignee_source: 'specific_users'}],
        decisions: [{step: 0, action: 'approve', actor_id: ACTOR_ID}],
      }],
    },
  });
  assert.equal(event.title, 'Approved');
});

test('history without a matching decision never attributes a custom step to HR', () => {
  const event = mapLocatorWorkflowEvent({
    action: 'hr_approved', actor_id: ACTOR_ID, actor_role: 'admin',
    workflow_snapshot: {
      steps: [{label: 'Records verification', assignee_source: 'specific_users'}],
      decisions: [],
    },
  });
  assert.equal(event.title, 'Approved');
});

test('legacy history does not describe an employee actor as HR', () => {
  assert.equal(mapLocatorWorkflowEvent({
    action: 'hr_approved', actor_role: 'employee',
  }).title, 'Approved');
});
