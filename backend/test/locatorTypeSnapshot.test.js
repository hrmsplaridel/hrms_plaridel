const test = require('node:test');
const assert = require('node:assert/strict');

const {
  captureLocatorTypeSnapshot,
  resolveLocatorTypeMetadata,
} = require('../src/services/locatorTypeSnapshot');

test('locator type snapshots preserve filing-time metadata after live edits', () => {
  const captured = captureLocatorTypeSnapshot({
    label: 'Work From Home',
    short_label: 'WFH',
    location_label: 'Work Location',
    location_hint: 'Enter work location',
    dtr_slot_label: 'WFH',
    dtr_print_label: 'WFH',
    requires_attachment: true,
    coverage_mode: 'wfh',
  });
  const resolved = resolveLocatorTypeMetadata({
    request_type_label_snapshot: captured.label,
    request_type_short_label_snapshot: captured.shortLabel,
    request_type_location_label_snapshot: captured.locationLabel,
    request_type_location_hint_snapshot: captured.locationHint,
    request_type_dtr_slot_label_snapshot: captured.dtrSlotLabel,
    request_type_dtr_print_label_snapshot: captured.dtrPrintLabel,
    request_type_requires_attachment_snapshot: captured.requiresAttachment,
    request_type_coverage_mode_snapshot: captured.coverageMode,
    request_type_label: 'Remote Work',
    request_type_dtr_slot_label: 'REMOTE',
    request_type_requires_attachment: false,
    request_type_coverage_mode: 'manual',
  });

  assert.equal(resolved.label, 'Work From Home');
  assert.equal(resolved.dtrSlotLabel, 'WFH');
  assert.equal(resolved.requiresAttachment, true);
  assert.equal(resolved.coverageMode, 'wfh');
});

test('legacy locator rows fall back to the current type metadata', () => {
  const resolved = resolveLocatorTypeMetadata({
    request_type_label: 'Pass Slip',
    request_type_dtr_print_label: 'PASS SLIP',
    request_type_requires_attachment: false,
    request_type_coverage_mode: 'manual',
  });

  assert.equal(resolved.label, 'Pass Slip');
  assert.equal(resolved.dtrPrintLabel, 'PASS SLIP');
  assert.equal(resolved.requiresAttachment, false);
  assert.equal(resolved.coverageMode, 'manual');
});
