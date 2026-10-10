const test=require('node:test');const assert=require('node:assert/strict');const fs=require('fs');const {randomUUID}=require('crypto');const {Client}=require('pg');
test('routing migration keeps old HR routes and snapshots conditional Mayor routes', {skip:!process.env.LEAVE_ROUTING_TEST_DATABASE_URL}, async()=>{
 const db=new Client({connectionString:process.env.LEAVE_ROUTING_TEST_DATABASE_URL});await db.connect();const schema='routing_test_'+randomUUID().replaceAll('-','');
 try{await db.query(`CREATE SCHEMA ${schema}`);await db.query(`SET search_path TO ${schema},public`);
 await db.query(`CREATE TABLE users(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),role TEXT,is_active BOOLEAN DEFAULT true,employment_type TEXT,employment_status TEXT DEFAULT 'active',date_hired DATE,separation_date DATE,created_at TIMESTAMPTZ DEFAULT now());
 CREATE TABLE leave_types(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),print_template_version_id UUID);
 CREATE TABLE leave_requests(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),user_id UUID,employee_id UUID,leave_type_id UUID,status TEXT,assigned_department_head_id UUID,print_template_version_id UUID);`);
 const mayor=(await db.query("INSERT INTO users(role)VALUES('mayor')RETURNING id")).rows[0].id;
 const jo=(await db.query("INSERT INTO users(role,employment_type)VALUES('employee','job_order')RETURNING id")).rows[0].id;
 const permanent=(await db.query("INSERT INTO users(role,employment_type)VALUES('employee','permanent')RETURNING id")).rows[0].id;
 await db.query("ALTER TABLE leave_requests ADD CONSTRAINT chk_leave_requests_status CHECK(status IN ('draft','pending_hr','pending_department_head','approved','returned','rejected_by_hr'))");
 const type=(await db.query('INSERT INTO leave_types DEFAULT VALUES RETURNING id')).rows[0].id;
 const old=(await db.query("INSERT INTO leave_requests(user_id,leave_type_id,status)VALUES($1,$2,'pending_hr')RETURNING id",[jo,type])).rows[0].id;
 const sql=fs.readFileSync('scripts/migrations/dtr/20261010_leave_approval_routing.sql','utf8');await db.query(sql);
 await db.query("UPDATE leave_types SET approval_route='mayor',mayor_employment_types=ARRAY['job_order','contract_of_service'] WHERE id=$1",[type]);
 assert.equal((await db.query('SELECT final_review_route FROM leave_requests WHERE id=$1',[old])).rows[0].final_review_route,'hr');
 const request=(await db.query("INSERT INTO leave_requests(user_id,leave_type_id,status,assigned_department_head_id)VALUES($1,$2,'pending_department_head',$3)RETURNING *",[jo,type,permanent])).rows[0];
 assert.equal(request.final_review_route,'mayor');assert.equal(request.final_reviewer_user_id,mayor);
 await db.query("UPDATE leave_types SET approval_route='hr' WHERE id=$1",[type]);
 await assert.rejects(db.query("UPDATE leave_requests SET status='pending_hr' WHERE id=$1",[request.id]),/department approval/i);
 assert.equal((await db.query('SELECT final_reviewer_user_id FROM leave_requests WHERE id=$1',[request.id])).rows[0].final_reviewer_user_id,mayor);
 await db.query("UPDATE leave_types SET approval_route='mayor' WHERE id=$1",[type]);
 const regular=(await db.query("INSERT INTO leave_requests(user_id,leave_type_id,status,assigned_department_head_id)VALUES($1,$2,'pending_department_head',$3)RETURNING *",[permanent,type,jo])).rows[0];assert.equal(regular.final_review_route,'hr');
 await assert.rejects(db.query("INSERT INTO leave_requests(user_id,leave_type_id,status)VALUES($1,$2,'pending_hr')",[jo,type]),/different department reviewer/);
 // Emulate a request from the unreleased electronic-Mayor implementation.
 await db.query('ALTER TABLE leave_requests DISABLE TRIGGER trg_snapshot_leave_approval_route');
 await db.query("UPDATE leave_requests SET status='pending_mayor' WHERE id=$1",[request.id]);
 await db.query('ALTER TABLE leave_requests ENABLE TRIGGER trg_snapshot_leave_approval_route');
 await db.query(sql);
 assert.equal((await db.query('SELECT status FROM leave_requests WHERE id=$1',[request.id])).rows[0].status,'pending_department_head');
 const approved=(await db.query("UPDATE leave_requests SET status='approved' WHERE id=$1 RETURNING *",[request.id])).rows[0];
 assert.equal(approved.status,'approved');
 await assert.rejects(db.query("UPDATE leave_requests SET status='pending_hr' WHERE id=$1",[request.id]),/department approval/i);
 await db.query(sql);
 assert.equal((await db.query('SELECT status FROM leave_requests WHERE id=$1',[request.id])).rows[0].status,'approved');
 }finally{await db.query('ROLLBACK');await db.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);await db.end();}
});
