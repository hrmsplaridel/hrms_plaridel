'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test.after(async () => {
  if (process.env.EMPLOYEE_SERVICE_RETURN_DB_TEST === '1') await require('../src/config/db').pool.end();
});

for (const separationStatus of ['resigned', 'contract_expired', 'deceased']) {
test(`PostgreSQL ${separationStatus}: preserves history and enforces return eligibility`, {
  skip: process.env.EMPLOYEE_SERVICE_RETURN_DB_TEST !== '1',
}, async () => {
  require('dotenv').config({ quiet: true });
  const { pool } = require('../src/config/db');
  const { returnEmployeeToService } = require('../src/services/employeeReturnToService');
  const { loadServicePeriods, serviceMonthCredit } = require('../src/services/employeeServicePeriods');
  const db = await pool.connect();
  const employee = randomUUID(), actor = randomUUID(), department = randomUUID(), position = randomUUID();
  const shift = randomUUID(), policy = randomUUID(), assignment = randomUUID();
  try {
    await db.query('BEGIN');
    for (const [id, role] of [[actor, 'admin'], [employee, 'employee']]) {
      await db.query(`INSERT INTO users(id,email,password_hash,full_name,role,date_hired,employment_type,
        employment_status,is_active,leave_credit_eligible,separation_date,leave_credit_eligible_until)
        VALUES($1,$2,'test-only','Return test',$3,'2025-01-01','permanent',$4,$5,$5,$6,$6)`,
      [id, `${id}@return-test.invalid`, role, id === employee ? separationStatus : 'active', id !== employee,
        id === employee ? '2026-09-15' : null]);
    }
    await db.query('INSERT INTO departments(id,name) VALUES($1,$2)', [department, `Return department ${department}`]);
    await db.query('INSERT INTO positions(id,name,department_id) VALUES($1,$2,$3)', [position, `Return position ${position}`, department]);
    await db.query("INSERT INTO shifts(id,name,start_time,end_time,break_start,break_end) VALUES($1,$2,'08:00','17:00','12:00','13:00')", [shift, `Return shift ${shift}`]);
    await db.query('INSERT INTO attendance_policies(id,name) VALUES($1,$2)', [policy, `Return policy ${policy}`]);
    await db.query(`INSERT INTO assignments(id,employee_id,department_id,position_id,shift_id,effective_from,effective_to)
      VALUES($1,$2,$3,$4,$5,'2025-01-01','2026-09-15')`, [assignment, employee, department, position, shift]);
    await db.query("INSERT INTO leave_balances(user_id,leave_type,earned_days,used_days,pending_days) VALUES($1,'vacationLeave',10,2,1)", [employee]);
    await db.query("INSERT INTO auth_refresh_tokens(user_id,token_hash,expires_at) VALUES($1,$2,now()+interval '1 day')", [employee, randomUUID()]);
    const proxy = { async query(sql, values) {
      if (sql === 'BEGIN') return db.query('SAVEPOINT service_return_test');
      if (sql === 'COMMIT') return db.query('RELEASE SAVEPOINT service_return_test');
      if (sql === 'ROLLBACK') return db.query('ROLLBACK TO SAVEPOINT service_return_test');
      return db.query(sql, values);
    }, release() {} };
    const scopedPool = { query: (sql, values) => db.query(sql, values), connect: async () => proxy };
    const request = { employeeId: employee, actorId: actor, today: '2026-11-16', payload: {
      returned_on: '2026-11-16', reason: 'Approved return to municipal service', leave_credit_eligible: true,
      assignment: { department_id: department, position_id: position, shift_id: shift }, attendance_policy_id: policy,
    } };
    if (separationStatus === 'deceased') {
      await assert.rejects(returnEmployeeToService(scopedPool, request), /deceased/i);
      const saved = (await db.query('SELECT employment_status,is_active,leave_credit_eligible FROM users WHERE id=$1', [employee])).rows[0];
      assert.deepEqual(saved, { employment_status: 'deceased', is_active: false, leave_credit_eligible: false });
      assert.equal((await db.query('SELECT count(*)::int AS n FROM employee_service_returns WHERE employee_id=$1', [employee])).rows[0].n, 0);
      return;
    }
    await db.query('UPDATE positions SET is_active=false WHERE id=$1', [position]);
    await assert.rejects(returnEmployeeToService(scopedPool, request), /inactive/i);
    assert.equal((await db.query('SELECT employment_status FROM users WHERE id=$1', [employee])).rows[0].employment_status, separationStatus);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM employee_service_returns WHERE employee_id=$1', [employee])).rows[0].n, 0);
    await db.query('UPDATE positions SET is_active=true WHERE id=$1', [position]);
    const result = await returnEmployeeToService(scopedPool, request);
    assert.equal(result.date_hired, '2025-01-01');
    assert.equal(result.is_active, true);
    assert.equal(result.employment_status, 'active');
    const periods = (await db.query(`SELECT id,last_service_return_date::text,separation_date::text,
      leave_credit_eligible,leave_credit_eligible_until FROM users WHERE id=$1`, [employee])).rows;
    const history = await loadServicePeriods(db, periods);
    assert.equal(serviceMonthCredit(history.get(employee), '2026-09-01', 1.25).expectedDays, 0.625);
    assert.equal(serviceMonthCredit(history.get(employee), '2026-10-01', 1.25).expectedDays, 0);
    assert.equal(serviceMonthCredit(history.get(employee), '2026-11-01', 1.25).expectedDays, 0.625);
    assert.equal((await db.query('SELECT effective_to::text FROM assignments WHERE id=$1', [assignment])).rows[0].effective_to, '2026-09-15');
    const balances = (await db.query('SELECT earned_days,used_days,pending_days FROM leave_balances WHERE user_id=$1', [employee])).rows[0];
    assert.deepEqual(Object.values(balances).map(Number), [10, 2, 1]);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM assignments WHERE employee_id=$1', [employee])).rows[0].n, 2);
    assert.equal((await db.query('SELECT revoked_at IS NOT NULL AS revoked FROM auth_refresh_tokens WHERE user_id=$1', [employee])).rows[0].revoked, true);
    await assert.rejects(returnEmployeeToService(scopedPool, request), /Only separated/);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM employee_service_returns WHERE employee_id=$1', [employee])).rows[0].n, 1);
    await db.query("UPDATE leave_balances SET last_accrual_date='2026-10-01' WHERE user_id=$1", [employee]);
    const { runLeaveMonthlyAccrual } = require('../src/services/leaveMonthlyAccrual');
    const preview = await runLeaveMonthlyAccrual(scopedPool, { dryRun: true, targetMonth: '2026-11', now: '2026-12-01' });
    const credit = preview.details.find(row => row.user_id === employee && row.leave_type === 'vacationLeave');
    assert.ok(credit);
    assert.equal(credit.days_added, Math.round(credit.accrual_rate * 0.5 * 1000) / 1000);
  } finally { await db.query('ROLLBACK'); db.release(); }
});
}
