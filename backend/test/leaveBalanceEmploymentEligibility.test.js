'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');
for (const employmentType of ['job_order', 'contract_of_service', 'permanent']) {
 test(`annual balances respect employment eligibility for ${employmentType}`, async () => {
  const query = async (sql) => {
   const text = String(sql).replace(/\s+/g, ' ').trim();
   if (text.startsWith('SELECT lb.*')) return {rows:[{leave_type:'sickLeave',earned_days:2,used_days:2}]};
   if (text.startsWith('SELECT name,')) return {rows:[
    {name:'specialPrivilegeLeave',max_days:3,sex_eligibility:'any',eligible_employment_types:['permanent']},
    {name:'customAnnual',max_days:4,sex_eligibility:'any',eligible_employment_types:null},
   ]};
   if (text.startsWith('SELECT sex')) return {rows:[{sex:'male',employment_type:employmentType}]};
   return {rows:[]};
  };
  const restore = withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
  clearModule('../src/routes/leaveRoutes');
  try {
   const router=require('../src/routes/leaveRoutes');
   const handler=router.stack.find(e=>e.route?.path==='/balances/:userId'&&e.route.methods.get).route.stack.at(-1).handle;
   const res={statusCode:200,status(n){this.statusCode=n;return this;},json(body){this.body=body;return this;}};
   await handler({user:{id:'user',role:'employee'},params:{userId:'user'}},res);
   assert.equal(res.statusCode,200);
   assert.equal(res.body.some(b=>b.leave_type==='specialPrivilegeLeave'),employmentType==='permanent');
   assert.ok(res.body.some(b=>b.leave_type==='customAnnual'));
   assert.ok(res.body.some(b=>b.leave_type==='sickLeave'&&b.used_days===2));
  } finally {clearModule('../src/routes/leaveRoutes');restore();}
 });
}
