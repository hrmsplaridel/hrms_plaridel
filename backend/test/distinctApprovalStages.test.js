'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { assertFinalLeaveReviewer, resolveEligibleFinalReviewers } = require('../src/services/leaveFinalReviewerService');

function database(departmentApprover = 'earl') {
  return { async query(sql) {
    if (sql.includes('primary_reviewer_designations')) return { rows: [{ id: 'earl' }] };
    if (sql.includes('leave_final_reviewer_backups')) return { rows: [{ id: 'other' }, { id: 'applicant' }] };
    if (sql.includes('department_approver_id')) return { rows: [{ department_approver_id: departmentApprover }] };
    throw new Error(`Unexpected SQL: ${sql}`);
  } };
}

for (const kind of ['leave', 'locator']) {
  test(`${kind}: actual department approver cannot act at final HR, another backup can`, async () => {
    await assert.rejects(assertFinalLeaveReviewer(database(), 'applicant', 'earl', kind, 'request'),
      error => error.statusCode === 403 && /department/i.test(error.message));
    await assertFinalLeaveReviewer(database(), 'applicant', 'other', kind, 'request');
  });
  test(`${kind}: final review recipients exclude applicant and actual department approver`, async () => {
    const reviewers = await resolveEligibleFinalReviewers(database(), 'applicant', kind, 'request');
    assert.deepEqual(reviewers.map(r => r.id), ['other']);
    const nextCycle = await resolveEligibleFinalReviewers(database(null), 'applicant', kind, 'request');
    assert.deepEqual(nextCycle.map(r => r.id), ['earl', 'other']);
  });
}

for (const kind of ['leave','locator']) {
  test(`${kind}: final signature is hidden and signing rejects the department approver`, async () => {
    const requestId='11111111-1111-4111-8111-111111111111';
    const earl='33333333-3333-4333-8333-333333333333';
    const base=database(earl);
    const db={async query(sql) {
      if (sql.includes('FROM leave_requests lr')) return {rows:[{id:requestId,status:'pending_hr',employee_user_id:'applicant',is_snapshotted_reviewer:true}]};
      if (sql.includes('FROM locator_slips ls')) return {rows:[{id:requestId,status:'pending_hr',employee_id:'applicant',dept_head_reviewer_id:earl,is_reviewer:true,print_signatories:{}}]};
      if (sql.includes('primary_reviewer_designations')) return {rows:[{id:earl}]};
      if (sql.includes('signatures s')) return {rows:[]};
      if (['BEGIN','ROLLBACK'].includes(sql)) return {rows:[]};
      return base.query(sql);
    },release(){}};
    db.connect=async()=>db;
    const user={id:earl,role:'admin'};
    if (kind==='leave') {
      const service=require('../src/services/docutrackerLeaveSignatureService');
      const form=await service.getLeaveSourceSignatures(db,user,'dtr','leave_requests',requestId);
      assert.equal(form.signatures.find(s=>s.slot_key==='hr_approver').can_sign,false);
      await assert.rejects(service.signLeaveSourceHrApprover(db,user,'dtr','leave_requests',requestId,{}),error=>error.statusCode===403);
    } else {
      const service=require('../src/services/locatorSignatureService');
      const form=await service.getLocatorSourceSignatures(db,user,'dtr','locator_slips',requestId);
      assert.equal(form.signatures.find(s=>s.slot_key==='hr_approver').can_sign,false);
      await assert.rejects(service.persistLocatorSignature(db,user,requestId,'hr_approver',{}),{code:'FORBIDDEN'});
    }
  });
}

test('old final review alerts exclude the department approver in list and unread count', async () => {
  const service = require('../src/services/notificationService');
  const db = { query: async sql => {
    assert.match(sql, /dept_head_reviewer_id/);
    assert.match(sql, /department_head_approved/);
    assert.match(sql, /submitted/);
    return { rows: [] };
  } };
  await service.listNotifications(db, 'earl');
  await service.countUnread(db, 'earl');
});

test('an active department backup can open approvals before a request is filed', async () => {
  const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
  const query = async sql => {
    if (sql.includes('department_reviewer_backups')) return { rows: [{ department_id: 'dept', department_name: 'HR' }] };
    if (sql.includes('SELECT EXISTS')) return { rows: [{ exists: false }] };
    return { rows: [] };
  };
  const restore = withMockedModule('../src/config/db', { pool: {query, connect: async () => ({query, release() {}})} });
  clearModule('../src/routes/leaveRoutes');
  try {
    const router = require('../src/routes/leaveRoutes');
    const res = { status(n) {this.code=n; return this;}, json(v) {this.body=v;} };
    await router.stack.find(r => r.route?.path === '/department-head/check').route.stack.at(-1).handle({user:{id:'backup'}}, res);
    assert.equal(res.body.canReviewPending, true);
    assert.equal(res.body.departmentId, 'dept');
  } finally { clearModule('../src/routes/leaveRoutes'); restore(); }
});

for (const kind of ['leave', 'locator']) {
  for (const action of ['approve', 'reject', 'return']) {
    test(`${kind} ${action} API rejects the department approver without writing a decision`, async () => {
      const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
      const statements = [];
      const query = async sql => {
        statements.push(sql);
        if (sql.includes('FOR UPDATE')) return { rows: [{ status: 'pending_hr', user_id:'applicant', employee_id:'applicant' }] };
        if (sql.includes('department_approver_id')) return { rows: [{ department_approver_id: 'earl' }] };
        return { rows: [] };
      };
      const restore = withMockedModule('../src/config/db', {pool:{query, connect:async()=>({query,release(){}})}});
      const path = kind === 'leave' ? '../src/routes/leaveRoutes' : '../src/routes/locatorSlips';
      clearModule(path);
      const originalError = console.error;
      try {
        console.error = () => {};
        const router = require(path);
        const routePath = kind === 'locator' && action === 'return' ? '/:id/return-for-correction' : `/:id/${action}`;
        const route = router.stack.find(r => r.route?.path === routePath && r.route.methods.patch);
        const res = {code:200,status(n){this.code=n;return this;},json(v){this.body=v;}};
        await route.route.stack.at(-1).handle({user:{id:'earl',role:'admin'},params:{id:'request'},body:{reason:'Please correct',reviewer_remarks:'Please correct'}},res);
        assert.equal(res.code,403);
        assert.match(res.body.error,/department approval/i);
        assert.equal(statements.some(s => /UPDATE (leave_requests|locator_slips)\s+SET status\s*=\s*'(approved|rejected|returned)/.test(s)),false);
      } finally {console.error=originalError;clearModule(path);restore();}
    });
  }
}
