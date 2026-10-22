'use strict';
module.exports = function createDtrComponent({}) {
  function normalizeLocatorRequestType(value) {
    const type = (value || 'locator').toString().trim().toLowerCase();
    return /^[a-z0-9_][a-z0-9_-]{1,63}$/.test(type) ? type : 'locator';
  }

  function locatorRequestTypeLabel(value) {
    switch (normalizeLocatorRequestType(value)) {
      case 'pass_slip':
        return 'Pass Slip';
      case 'locator':
        return 'Locator Slip';
      default:
        return (
          normalizeLocatorRequestType(value)
            .split(/[_-]+/)
            .filter(Boolean)
            .map((part) => `${part.charAt(0).toUpperCase()}${part.slice(1)}`)
            .join(' ') || 'Locator Slip'
        );
    }
  }

  function locatorAttendanceRemark(locator) {
    const dtrLabel = String(locator?.dtr_slot_label || '').trim();
    if (locator?.coverage_mode === 'wfh') {
      return dtrLabel || 'WFH';
    }
    const segText =
      locator?.segments && locator.segments.length > 0 ? ` (${locator.segments.join(', ')})` : '';
    return `${dtrLabel || locatorRequestTypeLabel(locator?.request_type)}${segText}`;
  }
  return { normalizeLocatorRequestType, locatorRequestTypeLabel, locatorAttendanceRemark };
};
