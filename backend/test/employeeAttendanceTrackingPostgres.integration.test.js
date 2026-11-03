const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
test('PostgreSQL tracking start preserves employment dates and audits changes; test data rolls back',{
 skip:process.env.EMPLOYEE_TRACKING_DB_TEST!=='1',
},async()=>{
 require('dotenv').config({quiet:true});const {pool}=require('../src/config/db');const db=await pool.connect();
 try {
  await db.query('BEGIN');
  const employeeId=randomUUID(),actorId=randomUUID();
  for(const [id,role] of [[employeeId,'employee'],[actorId,'hr']])await db.query(`INSERT INTO users(id,email,password_hash,full_name,role,date_hired,employment_type)
    VALUES($1,$2,'not-a-login-credential','Tracking rollback test',$3,'2025-01-01','permanent')`,[id,`${id}@rollback.invalid`,role]);
  const service=require('../src/services/employeeAttendanceTracking');
  await service.updateEmployeeTrackingStart(db,{employeeId,value:'2026-11-01',actorId});
  assert.equal((await service.loadTrackingStarts(db,[employeeId])).get(employeeId).start,'2026-11-01');
  assert.equal((await db.query('SELECT date_hired::text FROM users WHERE id=$1',[employeeId])).rows[0].date_hired,'2025-01-01');
  assert.equal((await db.query("SELECT count(*)::int AS n FROM audit_logs WHERE entity_id=$1 AND action='attendance_tracking_start_updated'",[employeeId])).rows[0].n,1);
  await service.updateEmployeeTrackingStart(db,{employeeId,value:undefined,actorId});
  assert.equal((await service.loadTrackingStarts(db,[employeeId])).get(employeeId).start,'2026-11-01');
  await db.query(`INSERT INTO leave_attendance_deductions(user_id,service_month,leave_type,computed_days,deducted_days,without_pay_days)
    VALUES($1,'2026-11-01','vacationLeave',1,0,1)`,[employeeId]);
  await assert.rejects(service.updateEmployeeTrackingStart(db,{employeeId,value:'2026-12-01',actorId}),e=>e.statusCode===409);
 }finally{await db.query('ROLLBACK');db.release();await pool.end();}
});
