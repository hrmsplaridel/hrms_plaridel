'use strict';
module.exports = function createLocatorComponent({}) {
  function boolField(value, fallback = false) {
    if (value === true || value === 'true' || value === 1 || value === '1') return true;
    if (value === false || value === 'false' || value === 0 || value === '0') return false;
    return fallback;
  }

  function isValidStatus(status) {
    return [
      'pending',
      'pending_department_head',
      'pending_hr',
      'pending_mayor',
      'returned_for_correction',
      'approved',
      'revoked',
      'rejected_by_department_head',
      'rejected_by_hr',
      'cancelled',
    ].includes(status);
  }
  return { boolField, isValidStatus };
};
