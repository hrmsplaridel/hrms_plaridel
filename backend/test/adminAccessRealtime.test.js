const test=require('node:test');const assert=require('node:assert/strict');
const {withMockedModule,clearModule}=require('./helpers/moduleMocks');
for(const module of ['dtrAccess','accountCreationAccess']) for(const fail of [false,true]) {
 test(`${module} publishes targeted access update only after commit (failure=${fail})`,async()=>{
 const queries=[];const events=[];const target='00000000-0000-4000-8000-000000000001';
 const client={release(){},async query(sql){queries.push(sql);if(sql.includes('FROM users WHERE id'))return{rows:[{role:'admin'}]};if(sql.includes('COALESCE')&&module==='accountCreationAccess')return{rows:[{allowed:true}]};if(sql.includes('FROM dtr_admin_access WHERE'))return{rows:[{reports_allowed:true,manage_allowed:true,revision:'r1'}]};if(sql.includes('INSERT INTO audit_logs')&&fail)throw Error('test audit failure');if(sql.includes('INSERT INTO dtr_admin_access'))return{rows:[{revision:'r2'}]};return{rows:[]}}};
 const db=withMockedModule('../src/config/db',{pool:{connect:async()=>client}});
 const socket=withMockedModule('../src/websockets/appEvents',{broadcastAppEvent:(name,payload,options)=>{assert.equal(queries.at(-1),'COMMIT');events.push({name,payload,options})}});
 const routePath=`../src/routes/${module}`;clearModule(routePath);
 try {const route=require(routePath).stack.find(l=>l.route?.methods.put).route;const res={code:200,status(n){this.code=n;return this},json(v){this.body=v}};await route.stack[2].handle({user:{id:'actor'},params:{adminId:target},body:module==='dtrAccess'?{reports_allowed:false,manage_allowed:true,expected_revision:'r1'}:{allowed:false}},res);
 if(fail){assert.equal(res.code,500);assert.equal(events.length,0)}else{assert.equal(res.code,200);assert.deepEqual(events,[{name:'admin_access_changed',payload:{},options:{userIds:[target]}}])}
 }finally{clearModule(routePath);socket();db()}
 });
}
