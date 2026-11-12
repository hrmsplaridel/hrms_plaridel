const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const path = require('node:path');
const {parseArgs, repairStep4ForApplication} = require('../scripts/repair-rsp-bypass-step4');

const applicationId = '11111111-1111-4111-8111-111111111111';
test('repair CLI requires one exact application and explicitly confirmed database for writes', () => {
  assert.equal(parseArgs([`--application-id=${applicationId}`]).apply, false);
  assert.equal(parseArgs([`--application-id=${applicationId}`, '--dry-run']).apply, false);
  assert.throws(() => parseArgs([]), /application-id/);
  assert.throws(() => parseArgs(['--application-id=all']), /UUID/);
  assert.throws(() => parseArgs([`--application-id=${applicationId}`, '--apply']), /expect-database/);
  assert.throws(() => parseArgs([`--application-id=${applicationId}`, '--apply', '--dry-run', '--expect-database=test']), /both/);
  assert.throws(() => parseArgs([`--application-id=${applicationId}`, '--force']), /Unknown/);
});

test('repair and assessment SQL preserve real PostgreSQL records and all advancement guards', {
  skip:process.env.RSP_BYPASS_DB_TEST !== '1',
}, async () => {
  require('dotenv').config({path:path.join(__dirname,'../.env')});
  const url = new URL(process.env.DATABASE_URL);
  assert.ok(['localhost','127.0.0.1','[::1]'].includes(url.hostname), 'Local PostgreSQL only');
  const {Pool} = require('pg');
  const {buildPoolOptions} = require('../src/config/databasePoolOptions');
  const pool = new Pool(buildPoolOptions());
  const db = await pool.connect();
  const schema = `rsp_bypass_test_${randomUUID().replaceAll('-','')}`;
  const adapter = {connect:async () => ({
    query:(sql, params) => db.query(String(sql).replaceAll('public.', `"${schema}".`),params),
    release() {},
  })};
  try {
    await db.query(`CREATE SCHEMA "${schema}"`);
    await db.query(`CREATE TABLE "${schema}".recruitment_applications (
      id uuid PRIMARY KEY, applicant_number text, status text, deleted_at timestamptz,
      step4_gate_required boolean DEFAULT false, final_interview_at timestamptz,
      final_interview_passed boolean, hired_user_id uuid, final_requirements_approved boolean DEFAULT false,
      hr_account_setup_done boolean DEFAULT false, step5_gate_required boolean DEFAULT false,
      wes_status text, applicants_profile_status text, selection_lineup_status text,
      updated_at timestamptz DEFAULT now())`);
    await db.query(`CREATE TABLE "${schema}".recruitment_exam_results (
      application_id uuid UNIQUE, passed boolean, answers_json jsonb)`);
    const override = {general:{admin_override:true},math:{admin_override:true},general_info:{admin_override:true}};
    const make = async (overrides = {}, exam = {passed:true,answers_json:override}) => {
      const row = {id:randomUUID(),applicant_number:'PLR-TEST2345',status:'passed',...overrides};
      const keys = Object.keys(row);
      await db.query(`INSERT INTO "${schema}".recruitment_applications (${keys.join(',')})
        VALUES (${keys.map((_,i)=>`$${i+1}`).join(',')})`,Object.values(row));
      if (exam) await db.query(`INSERT INTO "${schema}".recruitment_exam_results VALUES ($1,$2,$3)`,[row.id,exam.passed,exam.answers_json]);
      return row.id;
    };
    const get = async id => (await db.query(`SELECT * FROM "${schema}".recruitment_applications WHERE id=$1`,[id])).rows[0];
    const id = await make({wes_status:'needs_revision',applicants_profile_status:'completed'});
    const before = await get(id);
    const preview = await repairStep4ForApplication(adapter,{applicationId:id});
    assert.equal(preview.outcome,'would_repair');
    assert.deepEqual(await get(id),before,'Preview does not modify the application');
    const database = (await db.query('SELECT current_database() AS name')).rows[0].name;
    await assert.rejects(repairStep4ForApplication(adapter,{applicationId:id,apply:true,expectedDatabase:'wrong-database'}),/database/i);
    assert.deepEqual(await get(id),before);
    const repaired = await repairStep4ForApplication(adapter,{applicationId:id,apply:true,expectedDatabase:database});
    assert.equal(repaired.outcome,'repaired');
    const after = await get(id);
    assert.equal(after.step4_gate_required,true);
    assert.equal(after.wes_status,'needs_revision');
    assert.equal(after.applicants_profile_status,'completed');
    assert.equal(after.selection_lineup_status,'waiting');
    assert.equal(after.status,'passed');
    assert.equal((await repairStep4ForApplication(adapter,{applicationId:id,apply:true,expectedDatabase:database})).outcome,'already_enabled');
    const pending = await make();
    await repairStep4ForApplication(adapter,{applicationId:pending,apply:true,expectedDatabase:database});
    assert.equal((await get(pending)).wes_status,'waiting_for_work_experience_sheet');
    for (const guard of [
      {status:'failed'}, {status:'registered'}, {status:'submitted'},
      {final_interview_at:new Date()}, {final_interview_passed:true}, {final_interview_passed:false},
      {hired_user_id:randomUUID()}, {deleted_at:new Date()},
      {final_requirements_approved:true}, {hr_account_setup_done:true}, {step5_gate_required:true},
    ]) {
      const protectedId = await make(guard);
      const snapshot = await get(protectedId);
      const result = await repairStep4ForApplication(adapter,{applicationId:protectedId,apply:true,expectedDatabase:database});
      assert.equal(result.outcome,'not_eligible',JSON.stringify(guard));
      assert.deepEqual(await get(protectedId),snapshot);
    }
    for (const exam of [null,{passed:false,answers_json:override},{passed:true,answers_json:{}},
      {passed:true,answers_json:{general:{admin_override:true}}}]) {
      const protectedId = await make({},exam);
      assert.equal((await repairStep4ForApplication(adapter,{applicationId:protectedId,apply:true,expectedDatabase:database})).outcome,'not_eligible');
      assert.equal((await get(protectedId)).step4_gate_required,false);
    }
    const {withMockedModule,clearModule} = require('./helpers/moduleMocks');
    const restore = withMockedModule('../src/config/db', {pool:{query:async (sql, params) => {
      if (String(sql).includes('information_schema.columns')) return {rows:[{gate_column:true,wes_link:true,profile_link:true,lineup_link:true}]};
      return db.query(String(sql).replaceAll('public.', `"${schema}".`),params);
    }}});
    clearModule('../src/services/rspPreDeliberation');
    try {
      const service = require('../src/services/rspPreDeliberation');
      const failedId = await make({status:'failed'},{passed:false,answers_json:{}});
      await service.recordAssessmentOutcome(failedId,'passed');
      const newlyPassed = await get(failedId);
      assert.equal(newlyPassed.status,'passed');
      assert.equal(newlyPassed.step4_gate_required,true);
      assert.equal(newlyPassed.wes_status,'waiting_for_work_experience_sheet');
      assert.equal(newlyPassed.applicants_profile_status,'waiting');
      assert.equal(newlyPassed.selection_lineup_status,'waiting');
    } finally {
      clearModule('../src/services/rspPreDeliberation');
      restore();
    }
  } finally {
    await db.query('ROLLBACK');
    await db.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    db.release();
    await pool.end();
  }
});
