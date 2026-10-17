const test = require('node:test');
const assert = require('node:assert/strict');
const service = require('../src/services/docutrackerLeaveSignatureService');
const applicant = '11111111-1111-4111-8111-111111111111';
const asset = '22222222-2222-4222-8222-222222222222';

test('explicit applicant confirmation signs the final submitted revision and writes an audit entry', async () => {
  const writes = [];
  const db = {query: async (sql, values) => {
    writes.push({sql, values});
    if (sql.includes('INSERT INTO docutracker_leave_signatures')) {
      assert.match(sql, /lr\.signature_revision/);
      assert.match(sql, /a\.owner_user_id = u\.id/);
      assert.match(sql, /COALESCE\(lr\.user_id, lr\.employee_id\) = u\.id/);
      return {rows: [{revision: 3}], rowCount: 1};
    }
    return {rows: [], rowCount: 1};
  }};
  await service.confirmSubmittedApplicantSignature(db, {id: applicant}, 'request', asset);
  assert.deepEqual(writes[0].values, ['request', applicant, asset]);
  const audit = writes.find(w => w.sql.includes('INSERT INTO leave_request_history'));
  assert.ok(audit);
  assert.equal(JSON.parse(audit.values.at(-1)).revision, 3);
});

test('submission confirmation rejects foreign assets or an unauthorized request without writing history', async () => {
  let writes = 0;
  const db = {query: async () => {writes++; return {rows: [], rowCount: 0};}};
  await assert.rejects(service.confirmSubmittedApplicantSignature(db, {id: applicant}, 'request', asset), {statusCode: 403});
  assert.equal(writes, 1);
});

test('old applicant ink is never copied without explicit submission confirmation', async () => {
  const db = {query: async () => {throw Error('Must not use historical ink');}};
  await service.confirmSubmittedApplicantSignature(db, {id: applicant}, 'request', null);
});

test('PostgreSQL keeps old applicant confirmation separate and signs only the explicitly submitted revision',
  {skip: !process.env.LEAVE_APPLICANT_SIGNATURE_TEST_DATABASE_URL}, async () => {
  const {Client} = require('pg');
  const db = new Client({connectionString: process.env.LEAVE_APPLICANT_SIGNATURE_TEST_DATABASE_URL});
  await db.connect();
  const request = '33333333-3333-4333-8333-333333333333';
  try {
    await db.query('BEGIN');
    await db.query(`CREATE TEMP TABLE users(id uuid,full_name text,is_active boolean);
      CREATE TEMP TABLE docutracker_signature_assets(id uuid,owner_user_id uuid);
      CREATE TEMP TABLE leave_requests(id uuid,user_id uuid,employee_id uuid,status text,signature_revision int);
      CREATE TEMP TABLE docutracker_leave_signatures(leave_request_id uuid,slot_key text,assigned_signer_id uuid,
        signature_asset_id uuid,signed_by uuid,signer_name_snapshot text,signed_at timestamptz,created_by uuid,
        revision int,updated_at timestamptz,UNIQUE(leave_request_id,revision,slot_key));
      CREATE TEMP TABLE leave_request_history(leave_request_id uuid,action text,from_status text,to_status text,
        acted_by uuid,remarks text,metadata_json jsonb,acted_at timestamptz);`);
    await db.query("INSERT INTO users VALUES($1,'Applicant',true)", [applicant]);
    await db.query('INSERT INTO docutracker_signature_assets VALUES($1,$2)', [asset,applicant]);
    await db.query("INSERT INTO leave_requests VALUES($1,$2,$2,'pending_hr',3)",[request,applicant]);
    await db.query("INSERT INTO docutracker_leave_signatures(leave_request_id,slot_key,signed_by,revision) VALUES($1,'applicant',$2,1)",[request,applicant]);
    await service.confirmSubmittedApplicantSignature(db,{id:applicant},request,null);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM docutracker_leave_signatures WHERE revision=3')).rows[0].n,0);
    await service.confirmSubmittedApplicantSignature(db,{id:applicant},request,asset);
    assert.deepEqual((await db.query('SELECT revision FROM docutracker_leave_signatures ORDER BY revision')).rows.map(r=>r.revision),[1,3]);
    assert.equal((await db.query('SELECT metadata_json FROM leave_request_history')).rows[0].metadata_json.revision,3);
    await db.query('SAVEPOINT foreign_asset');
    await assert.rejects(service.confirmSubmittedApplicantSignature(db,{id:asset},request,asset),{statusCode:403});
    await db.query('ROLLBACK TO SAVEPOINT foreign_asset');
    await db.query("UPDATE leave_requests SET status='approved'");
    await assert.rejects(service.confirmSubmittedApplicantSignature(db,{id:applicant},request,asset),{statusCode:403});
  } finally {await db.query('ROLLBACK');await db.end();}
});
