const test=require('node:test');
const assert=require('node:assert/strict');
const {validateCreateEmployeePayload,validateEmploymentType}=require('../src/utils/employeeAccountValidation');
const valid={email:'test@example.test',first_name:'Test',last_name:'Employee',full_name:'Test Employee',date_hired:'2026-10-09'};
const types=['permanent','temporary','casual','contractual','coterminous','job_order','contract_of_service'];
test('legacy Regular is preserved only on an existing legacy account',()=>{
  assert.equal(validateEmploymentType('regular','regular'),null);
  assert.match(validateEmploymentType('regular','permanent'),/employment type/i);
  assert.equal(validateEmploymentType(null,'regular'),null);
  assert.equal(validateEmploymentType('permanent','regular'),null);
});
for(const type of types) test(`employee creation accepts ${type}`,()=>{
  assert.equal(validateCreateEmployeePayload({...valid,employment_type:type}),null);
});
for(const type of ['invalid','regular',123]) test(`employee creation rejects invalid or legacy type ${type}`,()=>{
  assert.match(validateCreateEmployeePayload({...valid,employment_type:type})||'',/employment type/i);
});

const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
for(const method of ['post','put']) {
  for(const type of types) test(`${method} employee persists ${type}`,async()=>{
    let stored;
    const query=async(sql,params=[])=>{
      if(sql.includes('SELECT biometric_user_id')) return {rowCount:1,rows:[{employment_type:'regular',employment_status:'active',date_hired:'2026-10-09',leave_credit_eligible:true}]};
      if(sql.includes('nextval')) return {rows:[{n:99}]};
      if(sql.startsWith('SELECT 1 FROM users')) return {rowCount:0,rows:[]};
      if(sql.includes('INSERT INTO users')) {
        stored=params[16]; return {rowCount:1,rows:[{id:'11111111-1111-4111-8111-111111111111',is_active:true,employment_type:stored}]};
      }
      if(sql.startsWith('UPDATE users SET')) {
        const match=sql.match(/employment_type = \$(\d+)/);stored=match?params[Number(match[1])-1]:undefined;
        return {rowCount:1,rows:[{id:'11111111-1111-4111-8111-111111111111',employment_type:stored}]};
      }
      return {rowCount:0,rows:[]};
    };
    const restores=[withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}}),
      withMockedModule('../src/services/employeeAccountSecurity',{
        ...require('../src/services/employeeAccountSecurity'),lockAndValidateAccountTransition:async()=>({changed:false,revokeSessions:false}),
      })];
    const path='../src/routes/employees';clearModule(path);
    try{
      const router=require(path);
      const route=router.stack.find(r=>r.route?.path===(method==='post'?'/':'/:id')&&r.route.methods[method]);
      const res={code:200,status(n){this.code=n;return this;},json(v){this.body=v;}};
      await route.route.stack.at(-1).handle({user:{id:'22222222-2222-4222-8222-222222222222',role:'admin'},params:{id:'11111111-1111-4111-8111-111111111111'},body:{...valid,employment_type:type,skip_account_email:true}},res);
      assert.equal(res.code,method==='post'?201:200);
      assert.equal(stored,type);
    }finally{clearModule(path);restores.reverse().forEach(r=>r());}
  });
}
