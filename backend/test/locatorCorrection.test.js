const test = require('node:test');
const assert = require('node:assert/strict');

const {
  locatorCorrectionChanges,
  normalizeLocatorCorrection,
} = require('../src/services/locatorCorrection');

const current = {
  slip_date_text: '2026-09-21',
  request_type: 'locator',
  office: 'Municipal Hall',
  reason: 'Attend a meeting',
  am_in: true,
  am_out: false,
  pm_in: false,
  pm_out: false,
};

test('returned locator corrections preserve omitted fields', () => {
  assert.deepEqual(normalizeLocatorCorrection(current, {}), {
    slipDate: '2026-09-21',
    requestType: 'locator',
    office: 'Municipal Hall',
    reason: 'Attend a meeting',
    amIn: true,
    amOut: false,
    pmIn: false,
    pmOut: false,
  });
});

test('returned locator corrections normalize editable fields', () => {
  assert.deepEqual(
    normalizeLocatorCorrection(current, {
      slip_date: '2026-09-22',
      request_type: 'PASS_SLIP',
      office: ' Provincial Office ',
      reason: ' Submit documents ',
      am_in: false,
      pm_in: 'true',
    }),
    {
      slipDate: '2026-09-22',
      requestType: 'pass_slip',
      office: 'Provincial Office',
      reason: 'Submit documents',
      amIn: false,
      amOut: false,
      pmIn: true,
      pmOut: false,
    }
  );
});

test('returned locator history records only fields that changed', () => {
  const corrected = normalizeLocatorCorrection(current, {
    office: 'Provincial Office',
    am_in: false,
    pm_in: true,
  });

  assert.deepEqual(locatorCorrectionChanges(current, corrected), {
    office: { from: 'Municipal Hall', to: 'Provincial Office' },
    am_in: { from: true, to: false },
    pm_in: { from: false, to: true },
  });
});
