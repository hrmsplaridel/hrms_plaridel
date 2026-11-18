const test = require('node:test');
const assert = require('node:assert/strict');
const {clearModule, withMockedModule} = require('./helpers/moduleMocks');

const actions = {
  leave_paper_allowed: 'leave_allowed', leave_types_allowed: 'leave_allowed',
  leave_ledger_allowed: 'leave_allowed', leave_card_allowed: 'leave_allowed',
  leave_balances_allowed: 'leave_allowed', leave_month_end_allowed: 'leave_allowed',
  leave_year_end_allowed: 'leave_allowed', locator_file_allowed: 'locator_allowed',
  locator_corrections_allowed: 'locator_allowed', locator_paper_allowed: 'locator_allowed',
  locator_types_allowed: 'locator_allowed',
};
const response = () => ({statusCode: 200, status(n) {this.statusCode=n;return this;}, json(body) {this.body=body;return this;}});

test('each More action requires both its own grant and its module; missing grants fail closed', async () => {
  let access = {};
  const restore = withMockedModule('../src/config/db', {pool:{query:async()=>({rows:[access]})}});
  clearModule('../src/middleware/dtrAccess');
  try {
    const {requireDtrActionIfAdmin} = require('../src/middleware/dtrAccess');
    for (const [field, parent] of Object.entries(actions)) {
      const check = requireDtrActionIfAdmin(field);
      for (const row of [{}, {[parent]:true}, {[field]:true}]) {
        access=row;const res=response();let next=false;
        await check({user:{id:'admin',role:'admin'}},res,()=>{next=true;});
        assert.equal(res.statusCode,403,field);assert.equal(next,false);
      }
      access={[parent]:true,[field]:true};let next=false;
      await check({user:{id:'admin',role:'admin'}},response(),()=>{next=true;});
      assert.equal(next,true,field);
    }
    assert.throws(()=>requireDtrActionIfAdmin('not_a_permission'));
    // Existing role/owner/reviewer checks on routes continue to handle other roles.
    for(const role of ['hr','employee','supervisor']) {
      let next=false;await requireDtrActionIfAdmin('leave_balances_allowed')({user:{role}},response(),()=>{next=true;});
      assert.equal(next,true);
    }
  } finally {clearModule('../src/middleware/dtrAccess');restore();}
});

test('permissions are checked again after revocation and a failed database check never grants access', async () => {
  let access={leave_allowed:true,leave_balances_allowed:true}, fail=false;
  const restore=withMockedModule('../src/config/db',{pool:{query:async()=>{if(fail)throw Error('offline');return {rows:[access]};}}});
  clearModule('../src/middleware/dtrAccess');
  const original=console.error;console.error=()=>{};
  try {
    const check=require('../src/middleware/dtrAccess').requireDtrActionIfAdmin('leave_balances_allowed');
    const req={user:{id:'admin',role:'admin'}};let calls=0;
    await check(req,response(),()=>calls++);
    access.leave_balances_allowed=false;const revoked=response();await check(req,revoked,()=>calls++);
    assert.equal(revoked.statusCode,403);assert.equal(calls,1);
    fail=true;const unavailable=response();await check(req,unavailable,()=>calls++);
    assert.equal(unavailable.statusCode,503);assert.equal(calls,1);
  }finally{console.error=original;clearModule('../src/middleware/dtrAccess');restore();}
});

test('More actions endpoints enforce the corresponding permission without adding approval restrictions', () => {
  const restore=withMockedModule('../src/config/db',{pool:{query:async()=>({rows:[]}),connect:async()=>({query:async()=>({rows:[]}),release(){}})}});
  clearModule('../src/middleware/dtrAccess');clearModule('../src/routes/leaveRoutes');clearModule('../src/routes/locatorSlips');
  try {
    const leave=require('../src/routes/leaveRoutes'), locator=require('../src/routes/locatorSlips');
    const expected=[
      [leave,'/admin/file','post','leave_paper_allowed'],
      [leave,'/types','post','leave_types_allowed'],[leave,'/types/:id','put','leave_types_allowed'],
      [leave,'/admin/opening-balances/import','post','leave_balances_allowed'],
      [leave,'/admin/opening-balances/:userId','post','leave_balances_allowed'],
      [leave,'/balances/:userId/adjustments','post','leave_balances_allowed'],
      [leave,'/admin/monthly-accrual','post','leave_month_end_allowed'],
      [leave,'/admin/year-end-forced-leave','get','leave_year_end_allowed'],
      [leave,'/admin/year-end-forced-leave/apply','post','leave_year_end_allowed'],
      [leave,'/admin/forced-leave-deduction','post','leave_year_end_allowed'],
      [leave,'/admin/leave-card/:userId/ledger','get','leave_card_allowed'],
      [locator,'/admin/file','post','locator_file_allowed'],
      [locator,'/admin/approved-paper','post','locator_paper_allowed'],
      [locator,'/admin/corrections','post','locator_corrections_allowed'],
      [locator,'/types','post','locator_types_allowed'],[locator,'/types/:id','put','locator_types_allowed'],
      [locator,'/types/:id','delete','locator_types_allowed'],
    ];
    for(const [router,path,method,field] of expected) {
      const route=router.stack.find(e=>e.route?.path===path&&e.route.methods[method])?.route;
      assert.ok(route,`${method} ${path}`);
      assert.ok(route.stack.some(l=>l.handle.dtrAction===field),`${method} ${path} requires ${field}`);
    }
    for(const router of [leave,locator]) {
      for(const path of ['/:id/approve','/:id/reject','/:id/revoke']) {
        const route=router.stack.find(e=>e.route?.path===path)?.route;
        assert.ok(route);assert.ok(!route.stack.some(l=>l.handle.dtrAction));
      }
    }
  }finally{clearModule('../src/routes/leaveRoutes');clearModule('../src/routes/locatorSlips');clearModule('../src/middleware/dtrAccess');restore();}
});

test('personal ledger survives denied tools while other employee and all-user history require Ledger access', async () => {
  const restore=withMockedModule('../src/config/db',{pool:{query:async()=>({rows:[{}]})}});
  clearModule('../src/middleware/dtrAccess');
  try {
    const guard=require('../src/middleware/dtrAccess').requireLeaveLedgerIfAdmin;
    for(const query of [{},{user_id:'admin'}]) {
      let next=false;await guard({user:{id:'admin',role:'admin'},query},response(),()=>{next=true;});assert.equal(next,true);
    }
    for(const query of [{user_id:'other'},{all_users:'true'},{include_all_users:'yes'},{user_id:'admin',all_users:'1'}]) {
      const res=response();await guard({user:{id:'admin',role:'admin'},query},res,()=>assert.fail('Unauthorized ledger read'));
      assert.equal(res.statusCode,403);
    }
  }finally{clearModule('../src/middleware/dtrAccess');restore();}
});

test('Manage Access validates action booleans, preserves omitted grants, and audits changed actions', async () => {
  const previous={leave_allowed:true,locator_allowed:true,leave_balances_allowed:true,revision:'r1'};
  let saved, audit, writes=0;
  const client={query:async(sql,params)=>{
    if(sql.includes('FROM users WHERE id'))return {rows:[{role:'admin'}]};
    if(sql.includes('FROM dtr_admin_access WHERE'))return {rows:[previous]};
    if(sql.includes('INSERT INTO dtr_admin_access')){saved={sql,params};writes++;return {rows:[{revision:'r2'}]};}
    if(sql.includes('INSERT INTO audit_logs'))audit=JSON.parse(params[2]);
    return {rows:[]};
  },release(){}};
  const restore=withMockedModule('../src/config/db',{pool:{connect:async()=>client}});
  clearModule('../src/routes/dtrAccess');
  try {
    const handle=require('../src/routes/dtrAccess').stack.find(e=>e.route?.methods.put).route.stack.at(-1).handle;
    const req={user:{id:'00000000-0000-4000-8000-000000000002'},params:{adminId:'00000000-0000-4000-8000-000000000001'},
      body:{reports_allowed:false,manage_allowed:false,expected_revision:'r1'}};
    for(const value of ['false',null,0,{},[]]) {
      const res=response();await handle({...req,body:{...req.body,leave_balances_allowed:value}},res);
      assert.equal(res.statusCode,400);assert.equal(writes,0);
    }
    const res=response();await handle({...req,body:{...req.body,locator_file_allowed:true}},res);
    assert.equal(res.statusCode,200);assert.equal(res.body.leave_balances_allowed,true);
    assert.equal(res.body.locator_file_allowed,true);assert.equal(res.body.leave_year_end_allowed,false);
    assert.match(saved.sql,/leave_balances_allowed/);assert.equal(saved.params.length,19);
    assert.equal(audit.after.locator_file_allowed,true);assert.equal(audit.before.locator_file_allowed,false);
  }finally{clearModule('../src/routes/dtrAccess');restore();}
});

test('Leave Card ledger is limited to its selected employee and rejects invalid IDs', async () => {
  const queries=[];
  const restore=withMockedModule('../src/config/db',{pool:{
    query:async(sql,params)=>{queries.push({sql,params});return {rows:[]};},
    connect:async()=>({query:async()=>({rows:[]}),release(){}}),
  }});
  clearModule('../src/routes/leaveRoutes');
  try {
    const handler=require('../src/routes/leaveRoutes').stack.find(e=>e.route?.path==='/admin/leave-card/:userId/ledger').route.stack.at(-1).handle;
    await new Promise(resolve=>setImmediate(resolve));
    queries.length=0;
    const bad=response();await handler({params:{userId:'invalid'},query:{},user:{id:'admin',role:'admin'}},bad);
    assert.equal(bad.statusCode,400);assert.equal(queries.length,0);
    const employee='00000000-0000-4000-8000-000000000001';
    const req={params:{userId:employee},user:{id:'admin',role:'admin'},
      query:{user_id:'other',all_users:'true',include_all_users:'true'}};
    const res=response();await handler(req,res);
    assert.equal(res.statusCode,200);assert.equal(req.query.user_id,employee);
    assert.equal(req.query.all_users,'false');assert.equal(req.query.include_all_users,'false');
    for(const call of queries)assert.ok(call.params.includes(employee));
  }finally{clearModule('../src/routes/leaveRoutes');restore();}
});
