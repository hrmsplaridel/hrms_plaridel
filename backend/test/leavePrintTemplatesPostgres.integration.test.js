const test=require('node:test'); const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');const {randomUUID}=require('node:crypto');const {Client}=require('pg');
test('migration snapshots submitted forms, updates drafts, preserves versions on rerun',
 {skip:!process.env.LEAVE_PRINT_TEST_DATABASE_URL},async()=>{
 const db=new Client({connectionString:process.env.LEAVE_PRINT_TEST_DATABASE_URL});await db.connect();
 const schema='leave_print_test_'+randomUUID().replaceAll('-','');
 try{
 await db.query(`CREATE SCHEMA ${schema}`);await db.query(`SET search_path TO ${schema},public`);
 await db.query(`CREATE TABLE users(id UUID PRIMARY KEY);
 CREATE TABLE leave_types(id UUID PRIMARY KEY DEFAULT gen_random_uuid());
 CREATE TABLE leave_requests(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),leave_type_id UUID REFERENCES leave_types(id),status TEXT);`);
 const type=(await db.query('INSERT INTO leave_types DEFAULT VALUES RETURNING id')).rows[0].id;
 const old=(await db.query("INSERT INTO leave_requests(leave_type_id,status)VALUES($1,'approved')RETURNING id",[type])).rows[0].id;
 const sql=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261010_leave_print_templates.sql'),'utf8');
 await db.query(sql);
 const v1=(await db.query('SELECT print_template_version_id FROM leave_types WHERE id=$1',[type])).rows[0].print_template_version_id;
 const draft=(await db.query("INSERT INTO leave_requests(leave_type_id,status)VALUES($1,'draft')RETURNING id",[type])).rows[0].id;
 const v2=(await db.query("INSERT INTO leave_print_template_versions(leave_type_id,layout)VALUES($1,'wellness')RETURNING id",[type])).rows[0].id;
 await db.query('UPDATE leave_types SET print_template_version_id=$1 WHERE id=$2',[v2,type]);
 await db.query("UPDATE leave_requests SET status='pending_hr' WHERE id=$1",[draft]);
 await db.query(sql);
 const rows=(await db.query('SELECT * FROM leave_requests')).rows;
 assert.equal(rows.find(r=>r.id===old).print_template_version_id,v1);
 assert.equal(rows.find(r=>r.id===draft).print_template_version_id,v2);
 await db.query("UPDATE leave_requests SET status='approved' WHERE id=$1",[draft]);
 assert.equal((await db.query('SELECT print_template_version_id FROM leave_requests WHERE id=$1',[draft])).rows[0].print_template_version_id,v2);
 const next=(await db.query('INSERT INTO leave_types DEFAULT VALUES RETURNING id')).rows[0].id;
 assert.ok((await db.query('SELECT print_template_version_id FROM leave_types WHERE id=$1',[next])).rows[0].print_template_version_id);
 }finally{await db.query('ROLLBACK');await db.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);await db.end();}
});
