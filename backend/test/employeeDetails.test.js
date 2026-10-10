const test=require('node:test');const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
for(const scenario of [
 {role:'admin',access:true,status:200}, {role:'admin',access:false,status:403},
 {role:'employee',status:403}, {role:'super_admin',status:200},
 {role:'admin',access:true,missing:true,status:404},
]) {
 test(`full employee details enforce access and omit secrets: ${JSON.stringify(scenario)}`,async()=>{
  const queries=[];
  const restore=withMockedModule('../src/config/db',{pool:{query:async(sql)=>{
    queries.push(sql);
    if(sql.includes('FROM dtr_admin_access'))return {rows:[{employees_allowed:scenario.access}]};
    if(sql.includes('FROM users u'))return {rows:scenario.missing?[]:[{id:'employee',full_name:'Test Employee',civil_status:'Single',nationality:'Filipino',biometric_user_id:'123',password_hash:'DO_NOT_EXPOSE',reset_token:'DO_NOT_EXPOSE'}]};
    if(sql.includes('FROM leave_balances'))return {rows:[{leave_type:'vacationLeave',earned_days:'10',used_days:'2',pending_days:'1',adjusted_days:'0.5'}]};
    if(sql.includes('FROM assignments'))return {rows:[{department_name:'Human Resources',position_name:'Staff',shift_name:'Regular',effective_from:'2026-01-01',effective_to:null}]};
    throw Error('Unexpected query');
  }}});
  clearModule('../src/middleware/dtrAccess');clearModule('../src/routes/employees');
  try {
    const route=require('../src/routes/employees').stack.find(l=>l.route?.path==='/:id/details').route;
    const req={user:{id:'viewer',role:scenario.role},params:{id:'employee'}};
    const res={code:200,status(c){this.code=c;return this;},json(b){this.body=b;}};
    async function dispatch(i) {
      if(i>=route.stack.length)return;
      let downstream;
      await route.stack[i].handle(req,res,()=>{downstream=dispatch(i+1);return downstream;});
      if(downstream)await downstream;
    }
    await dispatch(1); // Authentication is supplied by this test; exercise all authorization.
    assert.equal(res.code,scenario.status);
    if(res.code===200){
      assert.equal(res.body.full_name,'Test Employee');
      assert.equal(res.body.biometric_user_id,'123');
      assert.equal(res.body.assignment_history.length,1);
      assert.equal(res.body.credit_balances.length,1);
      assert.equal(res.body.credit_balances[0].earned_days,'10');
      assert.equal(JSON.stringify(res.body).includes('DO_NOT_EXPOSE'),false);
    } else assert.equal(queries.some(s=>s.trim().startsWith('SELECT a.id')),false);
    assert.equal(queries.some(s=>/INSERT|UPDATE|DELETE/.test(s)),false);
  }finally{clearModule('../src/routes/employees');clearModule('../src/middleware/dtrAccess');restore();}
 });
}
