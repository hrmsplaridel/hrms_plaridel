'use strict';

// Each tool needs its module grant as well as its own grant.
const dtrActionParents = Object.freeze({
  leave_paper_allowed: 'leave_allowed',
  leave_types_allowed: 'leave_allowed',
  leave_ledger_allowed: 'leave_allowed',
  leave_card_allowed: 'leave_allowed',
  leave_balances_allowed: 'leave_allowed',
  leave_month_end_allowed: 'leave_allowed',
  leave_year_end_allowed: 'leave_allowed',
  locator_file_allowed: 'locator_allowed',
  locator_corrections_allowed: 'locator_allowed',
  locator_paper_allowed: 'locator_allowed',
  locator_types_allowed: 'locator_allowed',
});
const dtrActionFields = Object.freeze(Object.keys(dtrActionParents));
module.exports = { dtrActionParents, dtrActionFields };
