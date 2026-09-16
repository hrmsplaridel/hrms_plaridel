const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ROLE_KEYS,
  resolveActiveMayor,
  resolveOfficialSignatory,
} = require('../src/services/officialSignatoryService');

test('effective official signatory is resolved for the requested historical date', async () => {
  const db = {
    async query(sql, params) {
      assert.match(sql, /effective_from <= \$2::date/);
      assert.deepEqual(params, [ROLE_KEYS.LEAVE_CREDIT_CERTIFIER, '2026-07-31']);
      return {
        rows: [{
          id: 'period-1',
          role_key: ROLE_KEYS.LEAVE_CREDIT_CERTIFIER,
          employee_id: 'employee-1',
          employee_name_snapshot: 'Maria Certifier',
          position_title_snapshot: 'Administrative Officer IV',
          department_name_snapshot: 'Human Resources',
          effective_from: '2026-07-01',
          effective_to: null,
        }],
      };
    },
  };
  const result = await resolveOfficialSignatory(
    db,
    ROLE_KEYS.LEAVE_CREDIT_CERTIFIER,
    '2026-07-31'
  );
  assert.equal(result.name, 'Maria Certifier');
  assert.equal(result.position_title, 'Administrative Officer IV');
});

test('latest active Mayor is resolved with the effective assignment title', async () => {
  const db = {
    async query(sql, params) {
      assert.match(sql, /LOWER\(COALESCE\(u\.role, ''\)\) = 'mayor'/);
      assert.deepEqual(params, ['2026-09-15']);
      return {
        rows: [{
          employee_id: 'official-user',
          name: 'Hon. Maria Santos',
          position_title: 'Municipal Mayor',
          department_name: "Mayor's Office",
        }],
      };
    },
  };
  const result = await resolveActiveMayor(db, '2026-09-15');
  assert.equal(result.name, 'Hon. Maria Santos');
  assert.equal(result.position_title, 'Municipal Mayor');
});
