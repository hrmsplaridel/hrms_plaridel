'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
for(const scenario of ['create','edit','stale','invalid'])test(`workflow publishing: ${scenario}`,async()=>{
  const calls=[];
  const query=async(sql,params=[])=>{
    calls.push({sql,params});
    if(sql.startsWith('SELECT * FROM approval_workflows'))return {rows:[{id:'workflow',current_version:2}]};
    if(sql.startsWith('INSERT INTO approval_workflows') || sql.startsWith('UPDATE approval_workflows'))return {rows:[{id:'workflow',name:'Full approval',current_version:scenario==='create'?1:3}]};
    return {rows:[]};
  };
  const restore=withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
  clearModule('../src/routes/approvalWorkflows');
  try {
    const router=require('../src/routes/approvalWorkflows');
    const path=scenario==='create'?'/':'/:id';
    const handler=router.stack.find(s=>s.route?.path===path && (s.route.methods.post || s.route.methods.put)).route.stack.at(-1).handle;
    const res={code:200,status(c){this.code=c;return this;},json(data){this.data=data;return this;}};
    await handler({user:{id:'admin'},params:scenario==='create'?{}:{id:'workflow'},body:{name:'Full approval',
      steps:scenario==='invalid'?['mayor','hr']:['department','hr','mayor'],current_version:scenario==='stale'?1:2,
      employment_types:['job_order']}},res);
    if(scenario==='stale' || scenario==='invalid') {
      assert.equal(res.code,scenario==='stale'?409:400);
      assert.ok(!calls.some(c=>c.sql.startsWith('INSERT INTO approval_workflow_versions')));
    }else {
      assert.equal(res.code,scenario==='create'?201:200);
      const insert=calls.find(c=>c.sql.startsWith('INSERT INTO approval_workflow_versions'));
      assert.equal(insert.params[1],scenario==='create'?1:3);
      assert.deepEqual(JSON.parse(insert.params[2]),['department','hr','mayor']);
      assert.equal(insert.params[3],null,'Workflow versions do not store filing eligibility from old clients');
      assert.equal(res.data.employment_types,null);
      assert.ok(calls.some(c=>c.sql==='COMMIT'));
    }
  }finally{clearModule('../src/routes/approvalWorkflows');restore();}
});
