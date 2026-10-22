'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

test('legacy Locator management rows, totals and filters defer pending shared workflows to the assigned inbox', async () => {
  const calls = [];
  const query = async (sql, params) => {
    calls.push({sql, params});
    return {rows: sql.includes('COUNT(*)') ? [{total: 0}] : []};
  };
  const restore = withMockedModule('../src/config/db', {pool: {query, connect: async () => ({query,release(){}})}});
  clearModule('../src/routes/locatorSlips');
  try {
    const router = require('../src/routes/locatorSlips');
    const handler = router.stack.find(l => l.route?.path === '/admin' && l.route.methods.get).route.stack.at(-1).handle;
    const res = {code: 200, status(n) {this.code=n;return this;}, json(body) {this.body=body;}};
    await handler({user: {id:'reviewer',role:'hr'},query:{}},res);
    assert.equal(res.code,200);
    const reads = calls.filter(c => c.sql.includes('FROM locator_slips ls'));
    assert.equal(reads.length,4);
    for (const {sql} of reads) {
      assert.match(sql, /jsonb_typeof\(ls.workflow_snapshot->'steps'->0\) IS DISTINCT FROM 'object'/);
      assert.match(sql, /OR ls.status NOT IN \('pending_department_head', 'pending_hr', 'pending_mayor', 'pending'\)/);
    }
  } finally {clearModule('../src/routes/locatorSlips');restore();}
});

test('Leave rows, totals, pending endpoint and filters also defer shared workflow requests to the assigned inbox',async()=>{
  const calls=[];
  const query=async(sql,params)=>{calls.push({sql,params});return{rows:sql.includes('COUNT(*)')?[{total:0}]:[]};};
  const restore=withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
  clearModule('../src/routes/leaveRoutes');
  try{
    const router=require('../src/routes/leaveRoutes');
    for(const path of ['/','/pending','/filter-options']){
      calls.length=0;
      const res={code:200,status(n){this.code=n;return this;},json(body){this.body=body;}};
      await router.stack.find(l=>l.route?.path===path&&l.route.methods.get).route.stack.at(-1).handle({user:{id:'reviewer',role:'hr'},query:{paginated:'true'}},res);
      assert.equal(res.code,200);
      const reads=calls.filter(c=>c.sql.includes('FROM leave_requests lr'));
      assert.ok(reads.length>0);
      for(const {sql} of reads){
        assert.match(sql,/jsonb_typeof\(lr.workflow_snapshot->'steps'->0\) IS DISTINCT FROM 'object'/,path);
        assert.match(sql,/OR lr.status NOT IN \('pending_department_head', 'pending_hr', 'pending_mayor', 'pending'\)/,path);
      }
    }
  }finally{clearModule('../src/routes/leaveRoutes');restore();}
});
