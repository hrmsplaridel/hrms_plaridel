const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('crypto');
const {Client} = require('pg');
const {leaveCardEligibilitySql} = require('../src/services/leaveCardEligibility');

test('Leave Card eligibility preserves VL/SL history and excludes unrelated annual entitlements',
  {skip:!process.env.LEAVE_CARD_TEST_DATABASE_URL}, async () => {
  const db = new Client({connectionString:process.env.LEAVE_CARD_TEST_DATABASE_URL});
  await db.connect();
  const schema = `card_test_${randomUUID().replaceAll('-','')}`;
  try {
    await db.query('BEGIN');
    await db.query(`CREATE SCHEMA ${schema}; SET LOCAL search_path TO ${schema},public`);
    await db.query(`CREATE TABLE users(id UUID PRIMARY KEY,full_name TEXT,leave_credit_eligible BOOLEAN,employment_type TEXT);
      CREATE TABLE assignments(employee_id UUID,is_active BOOLEAN,effective_from DATE,effective_to DATE);
      CREATE TABLE leave_balances(user_id UUID,leave_type TEXT,earned_days NUMERIC,used_days NUMERIC,pending_days NUMERIC,adjusted_days NUMERIC);
      CREATE TABLE leave_balance_ledger(user_id UUID,leave_type TEXT);
      CREATE TABLE leave_types(id UUID PRIMARY KEY,name TEXT,balance_ledger_type TEXT);
      CREATE TABLE leave_requests(user_id UUID,employee_id UUID,status TEXT,leave_type_id UUID);`);
    const customType = randomUUID();
    await db.query("INSERT INTO leave_types VALUES($1,'customPaidLeave','sickLeave')",[customType]);
    const cases = [
      {name:'eligible zero balance',eligible:true,type:'permanent',include:true},
      {name:'JO no credits',eligible:false,type:'job_order',include:false},
      {name:'COS no credits',eligible:false,type:'contract_of_service',include:false},
      {name:'JO explicit credit override',eligible:true,type:'job_order',include:true},
      {name:'former earner',eligible:false,type:'contract_of_service',include:true,balance:['vacationLeave',2,2,0,0]},
      {name:'empty VL balance row',eligible:false,type:'job_order',include:false,balance:['vacationLeave',0,0,0,0]},
      {name:'pending SL reservation',eligible:false,type:'job_order',include:true,balance:['sickLeave',0,0,1,0]},
      {name:'Wellness annual entitlement only',eligible:false,type:'job_order',include:false,balance:['Wellness',5,1,0,0]},
      {name:'reversed historical ledger',eligible:false,type:'job_order',include:true,ledger:'vacationLeave'},
      {name:'Wellness ledger only',eligible:false,type:'job_order',include:false,ledger:'Wellness'},
      {name:'approved custom paid request',eligible:false,type:'job_order',include:true,request:true},
      {name:'eligible but unassigned',eligible:true,type:'permanent',include:false,unassigned:true},
      {name:'historical credits but unassigned',eligible:false,type:'permanent',include:false,unassigned:true,balance:['vacationLeave',2,0,0,0]},
      {name:'future assignment',eligible:true,type:'permanent',include:false,assignmentStart:1},
      {name:'expired assignment',eligible:true,type:'permanent',include:false,assignmentEnd:-1},
      {name:'inactive assignment',eligible:true,type:'permanent',include:false,assignmentActive:false},
      {name:'assignment starts and ends today',eligible:true,type:'permanent',include:true,assignmentStart:0,assignmentEnd:0},
    ];
    for (const c of cases) {
      const id = randomUUID();
      await db.query('INSERT INTO users VALUES($1,$2,$3,$4)',[id,c.name,c.eligible,c.type]);
      if(!c.unassigned) await db.query(`INSERT INTO assignments VALUES($1,$2,
        (now() AT TIME ZONE 'Asia/Manila')::date + $3::int,
        (now() AT TIME ZONE 'Asia/Manila')::date + $4::int)`,
        [id,c.assignmentActive ?? true,c.assignmentStart ?? -2,c.assignmentEnd ?? null]);
      if(c.balance) await db.query('INSERT INTO leave_balances VALUES($1,$2,$3,$4,$5,$6)',[id,...c.balance]);
      if(c.ledger) await db.query('INSERT INTO leave_balance_ledger VALUES($1,$2)',[id,c.ledger]);
      if(c.request) await db.query("INSERT INTO leave_requests VALUES($1,$1,'approved',$2)",[id,customType]);
    }
    const selected = (await db.query(`SELECT u.full_name FROM users u WHERE ${leaveCardEligibilitySql}`)).rows.map(r=>r.full_name).sort();
    assert.deepEqual(selected,cases.filter(c=>c.include).map(c=>c.name).sort());
  } finally {await db.query('ROLLBACK');await db.end();}
});
