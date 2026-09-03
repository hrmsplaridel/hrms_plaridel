const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseLocatorDateOnly,
  validateLocatorWorkingDayForEmployee,
} = require('../src/services/locatorFilingRules');

const EMPLOYEE_ID = '00000000-0000-0000-0000-000000000101';

test('locator filing accepts a closed assignment effective on the locator date', async () => {
  let executedSql = '';
  let executedParams = null;
  const client = {
    async query(sql, params) {
      executedSql = String(sql);
      executedParams = params;
      return {
        rows: [{
          id: 'historical-assignment',
          shift_id: 'historical-shift',
          shift_name: 'Regular Shift',
          working_days: [1, 2, 3, 4, 5],
          is_active: false,
        }],
      };
    },
  };

  const result = await validateLocatorWorkingDayForEmployee(
    client,
    EMPLOYEE_ID,
    parseLocatorDateOnly('2026-06-19')
  );

  assert.deepEqual(result, { ok: true });
  assert.deepEqual(executedParams, [EMPLOYEE_ID, '2026-06-19']);
  assert.match(executedSql, /a\.effective_from <= \$2::date/);
  assert.doesNotMatch(executedSql, /a\.is_active/i);
});
