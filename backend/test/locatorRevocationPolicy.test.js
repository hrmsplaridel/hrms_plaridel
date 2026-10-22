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

test('revocation errors describe final approval independently of the reviewer role', () => {
  const input = {status:'approved',reason:'The requested date was incorrect.',now:new Date('2026-10-22T12:00:00Z')};
  assert.equal(evaluateLocatorRevocation(input).error,
    'Cannot determine the approval time for this locator request.');
  assert.equal(evaluateLocatorRevocation({...input,approvedAt:'2026-10-18T12:00:00Z'}).error,
    'The revoke period has expired. Locator approval can only be revoked within 3 days after final approval.');
});
