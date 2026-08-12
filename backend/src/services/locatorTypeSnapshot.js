function textOrNull(value) {
  const text = String(value ?? '').trim();
  return text || null;
}

function normalizeCoverageMode(value) {
  const mode = textOrNull(value);
  return mode === 'wfh' ? 'wfh' : 'manual';
}

function captureLocatorTypeSnapshot(locatorType = {}) {
  return {
    label: textOrNull(locatorType.label),
    shortLabel: textOrNull(locatorType.short_label),
    locationLabel: textOrNull(locatorType.location_label),
    locationHint: textOrNull(locatorType.location_hint),
    dtrSlotLabel: textOrNull(locatorType.dtr_slot_label),
    dtrPrintLabel: textOrNull(locatorType.dtr_print_label),
    requiresAttachment: locatorType.requires_attachment === true,
    coverageMode: normalizeCoverageMode(locatorType.coverage_mode),
  };
}

function snapshotText(row, snapshotKey, fallbackKey) {
  return textOrNull(row?.[snapshotKey]) || textOrNull(row?.[fallbackKey]);
}

function resolveLocatorTypeMetadata(row = {}) {
  const hasAttachmentSnapshot =
    row.request_type_requires_attachment_snapshot != null;
  return {
    label: snapshotText(
      row,
      'request_type_label_snapshot',
      'request_type_label'
    ),
    shortLabel: snapshotText(
      row,
      'request_type_short_label_snapshot',
      'request_type_short_label'
    ),
    locationLabel: snapshotText(
      row,
      'request_type_location_label_snapshot',
      'request_type_location_label'
    ),
    locationHint: snapshotText(
      row,
      'request_type_location_hint_snapshot',
      'request_type_location_hint'
    ),
    dtrSlotLabel: snapshotText(
      row,
      'request_type_dtr_slot_label_snapshot',
      'request_type_dtr_slot_label'
    ),
    dtrPrintLabel: snapshotText(
      row,
      'request_type_dtr_print_label_snapshot',
      'request_type_dtr_print_label'
    ),
    requiresAttachment: hasAttachmentSnapshot
      ? row.request_type_requires_attachment_snapshot === true
      : row.request_type_requires_attachment === true,
    coverageMode: snapshotText(
      row,
      'request_type_coverage_mode_snapshot',
      'request_type_coverage_mode'
    ),
    capturedAt: row.request_type_snapshot_at || null,
  };
}

module.exports = {
  captureLocatorTypeSnapshot,
  resolveLocatorTypeMetadata,
};
