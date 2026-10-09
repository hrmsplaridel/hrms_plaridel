const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const employeeId = '11111111-1111-4111-8111-111111111111';
const departmentId = '22222222-2222-4222-8222-222222222222';

for (const activeBackup of [true, false]) {
  test(`locator approvals recognize current backup assignment without pending requests (active=${activeBackup})`, async () => {
    const query = async sql => {
      if (sql.includes('FROM department_reviewer_backups')) {
        assert.match(sql, /b.is_active = true/);
        assert.match(sql, /u.is_active = true/);
        assert.match(sql, /b.effective_from <= \$2::date/);
        assert.match(sql, /b.effective_to >= \$2::date/);
        return {rows:activeBackup?[{department_id:departmentId,department_name:'HR'}]:[]};
      }
      return {rows:[]};
    };
    const restore = withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
    clearModule('../src/routes/locatorSlips');
    try {
      const router=require('../src/routes/locatorSlips');
      const route=router.stack.find(r=>r.route?.path==='/department-head/check' && r.route.methods.get);
      const res={code:200,status(n){this.code=n;return this;},json(v){this.body=v;}};
      await route.route.stack.at(-1).handle({user:{id:employeeId,role:'admin'}},res);
      assert.equal(res.code,200);
      assert.equal(res.body.canReviewPending,activeBackup);
      assert.equal(res.body.isDeptHead,activeBackup);
      assert.equal(res.body.hasReviewHistory,false);
      assert.equal(res.body.departmentId,activeBackup?departmentId:null);
    } finally {clearModule('../src/routes/locatorSlips');restore();}
  });
}

test('department reviewer assignment does not prevent revoking management permissions', async () => {
  const {activeReviewerFeatures}=require('../src/services/dtrFeatureReviewerAccess');
  const db={query:async sql=>({rows:sql.includes('AS assigned')?[{assigned:true}]:[]})};
  assert.deepEqual(await activeReviewerFeatures(db,employeeId),{leave_allowed:false,locator_allowed:false});
});

test('final HR assignment still requires management permissions', async () => {
  const {activeReviewerFeatures}=require('../src/services/dtrFeatureReviewerAccess');
  const db={query:async sql=>({rows:sql.includes('primary_reviewer_designations')?[{id:employeeId}]:[]})};
  assert.deepEqual(await activeReviewerFeatures(db,employeeId),{leave_allowed:true,locator_allowed:true});
});

test('department backup assignment accepts an admin without Leave or Locator management access', async () => {
  const calls=[];
  const query=async sql => {
    calls.push(sql);
    if (sql.includes('FROM departments')) return {rowCount:1,rows:[{id:departmentId}]};
    if (sql.includes('FROM assignments')) return {rows:[{id:employeeId}]};
    if (sql.includes('dtr_admin_access')) return {rows:[{id:employeeId}]};
    return {rows:[]};
  };
  const restore=withMockedModule('../src/config/db',{pool:{query,connect:async()=>({query,release(){}})}});
  clearModule('../src/routes/departments');
  try {
    const router=require('../src/routes/departments');
    const route=router.stack.find(r=>r.route?.path==='/:id/reviewer-backups' && r.route.methods.put);
    const res={code:200,status(n){this.code=n;return this;},json(v){this.body=v;}};
    await route.route.stack.at(-1).handle({params:{id:departmentId},user:{id:employeeId},body:{effective_from:'2026-10-09',employee_ids:[employeeId]}},res);
    assert.equal(res.code,200);
    assert.ok(calls.some(s=>s.includes('INSERT INTO department_reviewer_backups')));
    assert.equal(calls.some(s=>s.includes('dtr_admin_access')),false);
    assert.ok(calls.includes('COMMIT'));
  } finally {clearModule('../src/routes/departments');restore();}
});

test('department primary assignment does not require admin management access', async () => {
  const {savePrimaryReviewer}=require('../src/services/primaryReviewerDesignation');
  const calls=[];
  const client={release(){},async query(sql){
    calls.push(sql);
    if (sql.includes('FROM departments')) return {rows:[{id:departmentId}]};
    if (sql.includes('FROM users u')) return {rows:[{id:employeeId,role:'admin',department_id:departmentId}]};
    if (sql.includes('dtr_admin_access')) throw Error('Department authority must not require management access');
    if (sql.includes('INSERT INTO primary_reviewer_designations')) return {rows:[{id:employeeId}]};
    return {rows:[]};
  }};
  await savePrimaryReviewer({connect:async()=>client},{departmentId,employeeId,actorId:employeeId,effectiveFrom:'2026-10-09'});
  assert.ok(calls.includes('COMMIT'));
});
