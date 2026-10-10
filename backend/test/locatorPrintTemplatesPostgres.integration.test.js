const test=require('node:test');const assert=require('node:assert/strict');
const {Client}=require('pg');const {randomUUID}=require('node:crypto');const fs=require('node:fs');const path=require('node:path');
test('locator templates are pinned at filing, retained on review/resubmission and migration rerun',
 {skip:!process.env.LOCATOR_PRINT_TEST_DATABASE_URL},async()=>{
 const db=new Client({connectionString:process.env.LOCATOR_PRINT_TEST_DATABASE_URL});await db.connect();
 const schema='locator_print_test_'+randomUUID().replaceAll('-','');
 try {
  await db.query(`CREATE SCHEMA ${schema}`);await db.query(`SET search_path TO ${schema},public`);
  await db.query(`CREATE TABLE users(id UUID PRIMARY KEY);
   CREATE TABLE locator_request_types(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),code TEXT UNIQUE);
   CREATE TABLE locator_slips(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),request_type TEXT,status TEXT,updated_at TIMESTAMPTZ DEFAULT '2020-01-01T00:00:00Z');
   CREATE FUNCTION set_updated_at() RETURNS trigger AS $$ BEGIN NEW.updated_at=now(); RETURN NEW; END; $$ LANGUAGE plpgsql;
   CREATE TRIGGER updated_at BEFORE UPDATE ON locator_slips FOR EACH ROW EXECUTE FUNCTION set_updated_at();`);
  const type=(await db.query("INSERT INTO locator_request_types(code)VALUES('locator')RETURNING id")).rows[0].id;
  const old=(await db.query("INSERT INTO locator_slips(request_type,status)VALUES('locator','approved')RETURNING id")).rows[0].id;
  const sql=fs.readFileSync(path.join(__dirname,'../scripts/migrations/dtr/20261010_locator_print_templates.sql'),'utf8');
  await db.query(sql);
  assert.equal((await db.query('SELECT updated_at FROM locator_slips WHERE id=$1',[old])).rows[0].updated_at.toISOString(),'2020-01-01T00:00:00.000Z');
  const v1=(await db.query('SELECT print_template_version_id FROM locator_request_types WHERE id=$1',[type])).rows[0].print_template_version_id;
  const v2=(await db.query('INSERT INTO locator_print_template_versions(locator_type_id,background_name)VALUES($1,$2)RETURNING id',[type,'header.pdf'])).rows[0].id;
  await db.query('UPDATE locator_request_types SET print_template_version_id=$1 WHERE id=$2',[v2,type]);
  const filed=(await db.query("INSERT INTO locator_slips(request_type,status)VALUES('locator','pending_department_head')RETURNING id")).rows[0].id;
  await db.query("UPDATE locator_slips SET status='returned_for_correction' WHERE id=$1",[filed]);
  await db.query('UPDATE locator_request_types SET print_template_version_id=$1 WHERE id=$2',[v1,type]);
  await db.query("UPDATE locator_slips SET status='pending_department_head' WHERE id=$1",[filed]);
  await db.query(sql);
  assert.equal((await db.query('SELECT print_template_version_id FROM locator_slips WHERE id=$1',[old])).rows[0].print_template_version_id,null);
  assert.equal((await db.query('SELECT print_template_version_id FROM locator_slips WHERE id=$1',[filed])).rows[0].print_template_version_id,v2);
  await db.query("INSERT INTO locator_request_types(code)VALUES('new')");
  // AFTER INSERT updates the pointer after RETURNING has been evaluated.
  assert.ok((await db.query("SELECT print_template_version_id FROM locator_request_types WHERE code='new'")).rows[0].print_template_version_id);
 }finally{await db.query('ROLLBACK');await db.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);await db.end();}
});
