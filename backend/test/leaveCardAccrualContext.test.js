const test=require('node:test');
const assert=require('node:assert/strict');
const {buildLeaveBalanceHistoryFilters}=require('../src/services/leaveBalanceLedger');

test('authorized card context supplies actual monthly postings only for the selected employee and first page',async()=>{
  const calls=[];
  const controllers=require('../src/modules/leave/controllers/balances.controller')({
    buildLeaveBalanceHistoryFilters,
    pool:{query:async(sql,params)=>{
      calls.push({sql,params});
      return {rows:sql.includes('FROM leave_monthly_accrual_postings')
        ? [{leave_type:'vacationLeave',service_month:'2026-08-01',credited_days:1.25}] : []};
    }},
  });
  for(const [card,offset,expected] of [[true,'0',1],[true,'200',0],[false,'0',0]]) {
    calls.length=0;
    const res={statusCode:200,status(n){this.statusCode=n;return this;},json(data){this.body=data;return this;}};
    await controllers.getLedger({user:{id:'actor',role:'admin'},leaveCardContext:card,
      query:{user_id:'employee',offset}},res);
    assert.equal(res.statusCode,200);
    const postings=calls.filter(c=>c.sql.includes('FROM leave_monthly_accrual_postings'));
    assert.equal(postings.length,expected);
    if(expected) {
      assert.deepEqual(postings[0].params,['employee']);
      assert.match(postings[0].sql,/leave_type IN \('vacationLeave', 'sickLeave'\)/);
      assert.equal(res.body.accrual_postings[0].credited_days,1.25);
    } else assert.equal(res.body.accrual_postings,undefined);
  }
});
