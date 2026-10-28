const test = require('node:test');
const assert = require('node:assert/strict');
const { evaluatePaperRevocation, assertPaperRevocationActor, restorePaperLeaveCredits } = require('../src/services/paperApprovalRevocation');

test('paper revocation uses encoding time, requires a reason and retains the three-day limit', () => {
  const input = {status:'approved', paperRecord:{approval_date:'2020-01-01',encoded_at:'2026-10-28T02:00:00Z'}, reason:'The signed record was entered twice.', now:new Date('2026-10-29T02:00:00Z')};
  assert.equal(evaluatePaperRevocation(input).ok,true);
  assert.equal(evaluatePaperRevocation({...input,reason:'short'}).statusCode,400);
  assert.equal(evaluatePaperRevocation({...input,status:'cancelled'}).statusCode,409);
  assert.equal(evaluatePaperRevocation({...input,now:new Date('2026-11-01T02:00:00Z')}).code,'paper_revoke_window_expired');
  assert.equal(evaluatePaperRevocation({...input,paperRecord:{}}).code,'paper_recording_time_missing');
});

test('paper revocation is limited to active HR or authorized admin, excluding self review', async () => {
  const db = {query:async(sql)=>({rows: sql.includes('FROM users')?[{id:'hr',role:'hr',full_name:'HR Encoder'}]:[{leave_allowed:false}]})};
  assert.equal((await assertPaperRevocationActor(db,{actor:{id:'hr',role:'hr'},employeeId:'employee',module:'leave'})).full_name,'HR Encoder');
  for(const actor of [{id:'employee',role:'hr'},{id:'hr',role:'employee'},{id:'hr',role:'mayor'}]){
    await assert.rejects(assertPaperRevocationActor(db,{actor,employeeId:'employee',module:'leave'}),{statusCode:403});
  }
  await assert.rejects(assertPaperRevocationActor({query:async()=>({rows:[]})},{actor:{id:'hr',role:'hr'},employeeId:'employee',module:'leave'}),{statusCode:403});
  const adminDb={query:async(sql)=>({rows:sql.includes('FROM users')?[{id:'admin',role:'admin'}]:[{leave_allowed:false}]})};
  await assert.rejects(assertPaperRevocationActor(adminDb,{actor:{id:'admin',role:'admin'},employeeId:'employee',module:'leave'}),{statusCode:403});
});

test('paper credit reversal follows actual ledger charges and never guesses from requested paid days or current type rules',async()=>{
  const writes=[],ledger=[];
  const db={query:async(sql,args)=>{
    if(sql.includes('FROM leave_balance_ledger'))return {rows:[{leave_type:'originalBucket',deducted_days:'0.5'}]};
    if(sql.includes('FOR UPDATE'))return {rows:[{used_days:'3'}]};
    writes.push({sql,args});return {rowCount:1,rows:[]};
  }};
  const result=await restorePaperLeaveCredits(db,{requestId:'request',employeeId:'employee',actorId:'hr',reason:'Wrong dates were entered.',insertLeaveBalanceLedger:async(_db,row)=>ledger.push(row)});
  assert.equal(result.restoredDays,0.5);
  assert.deepEqual(writes[0].args,['employee','originalBucket',0.5]);
  assert.equal(ledger[0].daysChanged,-0.5);
  assert.equal(ledger[0].action,'leave_revoked');
  assert.equal(ledger[0].oldValue,3);assert.equal(ledger[0].newValue,2.5);
  const noCreditDb={query:async()=>({rows:[]})};
  assert.equal((await restorePaperLeaveCredits(noCreditDb,{requestId:'free',employeeId:'employee'})).restoredDays,0);
  await assert.rejects(restorePaperLeaveCredits({query:async(sql)=>({rows:sql.includes('FROM leave_balance_ledger')?[{leave_type:'originalBucket',deducted_days:'4'}]:[{used_days:'1'}]})},
    {requestId:'request',employeeId:'employee'}),{statusCode:409},'An inconsistent balance must roll back rather than consume another request’s credit');
});
