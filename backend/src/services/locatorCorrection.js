const CORRECTABLE_LOCATOR_FIELDS = Object.freeze([
  ['slip_date', 'slipDate'],
  ['request_type', 'requestType'],
  ['office', 'office'],
  ['reason', 'reason'],
  ['am_in', 'amIn'],
  ['am_out', 'amOut'],
  ['pm_in', 'pmIn'],
  ['pm_out', 'pmOut'],
]);

function hasOwn(object, key) {
  return Object.prototype.hasOwnProperty.call(object || {}, key);
}

function textValue(value) {
  return (value ?? '').toString().trim();
}

function boolValue(value, fallback = false) {
  if (value === true || value === 'true' || value === 1 || value === '1') {
    return true;
  }
  if (value === false || value === 'false' || value === 0 || value === '0') {
    return false;
  }
  return fallback === true;
}

function normalizeRequestType(value) {
  const type = textValue(value).toLowerCase();
  return /^[a-z0-9_][a-z0-9_-]{1,63}$/.test(type) ? type : null;
}

function normalizeLocatorCorrection(current = {}, input = {}) {
  const currentDate = current.slip_date_text || current.slip_date;
  return {
    slipDate: textValue(
      hasOwn(input, 'slip_date') ? input.slip_date : currentDate
    ).slice(0, 10),
    requestType: normalizeRequestType(
      hasOwn(input, 'request_type')
        ? input.request_type
        : current.request_type
    ),
    office: textValue(
      hasOwn(input, 'office') ? input.office : current.office
    ),
    reason: textValue(
      hasOwn(input, 'reason') ? input.reason : current.reason
    ),
    amIn: boolValue(
      hasOwn(input, 'am_in') ? input.am_in : current.am_in,
      current.am_in
    ),
    amOut: boolValue(
      hasOwn(input, 'am_out') ? input.am_out : current.am_out,
      current.am_out
    ),
    pmIn: boolValue(
      hasOwn(input, 'pm_in') ? input.pm_in : current.pm_in,
      current.pm_in
    ),
    pmOut: boolValue(
      hasOwn(input, 'pm_out') ? input.pm_out : current.pm_out,
      current.pm_out
    ),
  };
}

function locatorCorrectionChanges(current = {}, corrected = {}) {
  const normalizedCurrent = normalizeLocatorCorrection(current);
  const changes = {};
  for (const [databaseField, correctionField] of CORRECTABLE_LOCATOR_FIELDS) {
    const before = normalizedCurrent[correctionField];
    const after = corrected[correctionField];
    if (before !== after) {
      changes[databaseField] = { from: before, to: after };
    }
  }
  return changes;
}

module.exports = {
  CORRECTABLE_LOCATOR_FIELDS,
  locatorCorrectionChanges,
  normalizeLocatorCorrection,
};
