const test = require('node:test');
const assert = require('node:assert/strict');

const {
  evaluateLocatorRevocation,
} = require('../src/services/locatorRevocationPolicy');

test('approved locator can be revoked within three days with a reason', () => {
  const result = evaluateLocatorRevocation({
    status: 'approved',
    approvedAt: '2026-08-10T08:00:00.000Z',
    reason: 'Approved the wrong employee request.',
    now: new Date('2026-08-12T08:00:00.000Z'),
  });

  assert.equal(result.ok, true);
  assert.equal(result.revocationReason, 'Approved the wrong employee request.');
});

test('locator revocation rejects missing reasons and expired approvals', () => {
  assert.equal(
    evaluateLocatorRevocation({
      status: 'approved',
      approvedAt: '2026-08-10T08:00:00.000Z',
      reason: 'short',
      now: new Date('2026-08-11T08:00:00.000Z'),
    }).code,
    'locator_revocation_reason_required'
  );
  assert.equal(
    evaluateLocatorRevocation({
      status: 'approved',
      approvedAt: '2026-08-10T08:00:00.000Z',
      reason: 'Approved the wrong employee request.',
      now: new Date('2026-08-13T08:00:00.001Z'),
    }).code,
    'locator_revoke_window_expired'
  );
});

test('only approved locator requests can be revoked', () => {
  assert.equal(
    evaluateLocatorRevocation({
      status: 'pending_hr',
      approvedAt: '2026-08-10T08:00:00.000Z',
      reason: 'This request should not be approved.',
      now: new Date('2026-08-11T08:00:00.000Z'),
    }).code,
    'locator_not_approved'
  );
});
