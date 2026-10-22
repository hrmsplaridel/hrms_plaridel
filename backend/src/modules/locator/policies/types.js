'use strict';
module.exports = function createLocatorComponent({
  normalizeLocatorFieldSchema,
  normalizeLocatorRouting,
}) {
  const LOCATOR_TYPE_TEXT_LIMITS = Object.freeze({
    label: 100,
    shortLabel: 40,
    locationLabel: 100,
    locationHint: 200,
    dtrSlotLabel: 40,
    dtrPrintLabel: 40,
  });

  const DEFAULT_LOCATOR_TYPES = [
    {
      code: 'locator',
      label: 'Locator / Official Business',
      short_label: 'Locator',
      location_label: 'Office / Destination',
      location_hint: 'Enter office or destination',
      dtr_slot_label: 'On Field',
      dtr_print_label: 'ON FIELD',
      requires_attachment: false,
      coverage_mode: 'manual',
      sort_order: 10,
    },
    {
      code: 'pass_slip',
      label: 'Pass Slip',
      short_label: 'Pass Slip',
      location_label: 'Destination / Location',
      location_hint: 'Enter destination or location',
      dtr_slot_label: 'Pass Slip',
      dtr_print_label: 'PASS SLIP',
      requires_attachment: false,
      coverage_mode: 'manual',
      sort_order: 20,
    },
  ];

  const DEFAULT_LOCATOR_TYPE_CODES = new Set(DEFAULT_LOCATOR_TYPES.map((t) => t.code));

  function normalizeRequestType(value) {
    const type = (value || 'locator').toString().trim().toLowerCase();
    return /^[a-z0-9_][a-z0-9_-]{1,63}$/.test(type) ? type : null;
  }

  function locatorTypeValidationError(message) {
    const error = new Error(message);
    error.statusCode = 400;
    throw error;
  }

  function locatorTypeBooleanField(value, fallback, label) {
    if (value === undefined || value === null) return fallback;
    if (value === true || value === 'true' || value === 1 || value === '1') return true;
    if (value === false || value === 'false' || value === 0 || value === '0') return false;
    return locatorTypeValidationError(`${label} must be a boolean.`);
  }

  function locatorTypeTextField(value, fallback, label, maximumLength) {
    const source = value === undefined || value === null ? fallback : value;
    const text = (source ?? '').toString().trim();
    if (!text) {
      return locatorTypeValidationError(`${label} is required.`);
    }
    if (text.length > maximumLength) {
      return locatorTypeValidationError(`${label} must be ${maximumLength} characters or less.`);
    }
    return text;
  }

  function intField(value, fallback = 0) {
    if (value === undefined || value === null) return fallback;
    const text = String(value).trim();
    if (!/^\d+$/.test(text)) {
      return locatorTypeValidationError(
        'Sort order must be a whole number between 0 and 2147483647.'
      );
    }
    const parsed = Number(text);
    if (!Number.isSafeInteger(parsed) || parsed > 2147483647) {
      return locatorTypeValidationError(
        'Sort order must be a whole number between 0 and 2147483647.'
      );
    }
    return parsed;
  }

  function normalizeCoverageMode(value) {
    if (value === undefined || value === null) return 'manual';
    const mode = value.toString().trim().toLowerCase();
    if (mode === 'manual' || mode === 'wfh') return mode;
    return locatorTypeValidationError('Coverage mode must be manual or wfh.');
  }

  function locatorTypePayloadFromBody(body, existing = null) {
    const filingAccess = body.filing_access ?? existing?.filing_access ?? 'employee';
    if (!['employee', 'admin', 'both'].includes(filingAccess))
      locatorTypeValidationError('Filing access must be employee, admin, or both.');
    const autoApproveAdmin = locatorTypeBooleanField(
      body.auto_approve_admin,
      existing?.auto_approve_admin === true,
      'Auto approve staff filing'
    );
    if (filingAccess === 'employee' && autoApproveAdmin)
      locatorTypeValidationError('Auto approval requires HR/admin filing.');
    const rawCode = existing?.code ?? body.code;
    if (rawCode === undefined || rawCode === null || !String(rawCode).trim()) {
      return locatorTypeValidationError('System code is required.');
    }
    const code = normalizeRequestType(rawCode);
    if (!code) {
      return locatorTypeValidationError(
        'System code must be 2 to 64 letters, numbers, underscores, or hyphens.'
      );
    }
    const label = locatorTypeTextField(
      body.label,
      existing?.label,
      'Request type name',
      LOCATOR_TYPE_TEXT_LIMITS.label
    );
    return {
      filing_access: filingAccess,
      auto_approve_admin: autoApproveAdmin,
      employee_detail_schema: normalizeLocatorFieldSchema(
        body.employee_detail_schema ?? existing?.employee_detail_schema,
        { strict: true }
      ),
      ...normalizeLocatorRouting({ ...body, auto_approve_admin: autoApproveAdmin }, existing || {}),
      code,
      label,
      short_label: locatorTypeTextField(
        body.short_label ?? body.shortLabel,
        existing?.short_label ?? label,
        'Short display name',
        LOCATOR_TYPE_TEXT_LIMITS.shortLabel
      ),
      location_label: locatorTypeTextField(
        body.location_label ?? body.locationLabel,
        existing?.location_label ?? 'Office / Destination',
        'Destination field name',
        LOCATOR_TYPE_TEXT_LIMITS.locationLabel
      ),
      location_hint: locatorTypeTextField(
        body.location_hint ?? body.locationHint,
        existing?.location_hint ?? 'Enter office or destination',
        'Destination placeholder',
        LOCATOR_TYPE_TEXT_LIMITS.locationHint
      ),
      dtr_slot_label: locatorTypeTextField(
        body.dtr_slot_label ?? body.dtrSlotLabel,
        existing?.dtr_slot_label ?? label,
        'DTR display text',
        LOCATOR_TYPE_TEXT_LIMITS.dtrSlotLabel
      ),
      dtr_print_label: locatorTypeTextField(
        body.dtr_print_label ?? body.dtrPrintLabel,
        existing?.dtr_print_label ?? label.toUpperCase(),
        'DTR print text',
        LOCATOR_TYPE_TEXT_LIMITS.dtrPrintLabel
      ),
      requires_attachment: locatorTypeBooleanField(
        body.requires_attachment ?? body.requiresAttachment,
        existing?.requires_attachment === true,
        'Requires attachment'
      ),
      coverage_mode: normalizeCoverageMode(
        body.coverage_mode ?? body.coverageMode ?? existing?.coverage_mode
      ),
      is_active: locatorTypeBooleanField(
        body.is_active ?? body.isActive,
        existing?.is_active !== false,
        'Available for filing'
      ),
      sort_order: intField(body.sort_order ?? body.sortOrder, existing?.sort_order ?? 0),
    };
  }
  return {
    LOCATOR_TYPE_TEXT_LIMITS,
    DEFAULT_LOCATOR_TYPES,
    DEFAULT_LOCATOR_TYPE_CODES,
    normalizeRequestType,
    locatorTypeValidationError,
    locatorTypeBooleanField,
    locatorTypeTextField,
    intField,
    normalizeCoverageMode,
    locatorTypePayloadFromBody,
  };
};
