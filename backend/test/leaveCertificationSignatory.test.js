const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

for (const ownRole of ['hr', 'department']) {
  test(`leave applicant who is primary ${ownRole} reviewer prints Mayor in their own official block`, async () => {
    const restores = [
      withMockedModule('../src/config/db', {pool:{query:async sql=>({rows:sql.includes('FROM leave_requests lr')?
        [{employee_id:'employee',submitted_on:'2026-10-09',status:'pending_hr',review_department_id:'department'}]:[]})}}),
      withMockedModule('../src/services/leaveFinalReviewerService', {
        resolveFinalLeaveReviewerConfiguration:async()=>({primary:{id:ownRole==='hr'?'employee':'hr',name:'HR',position_title:'HR Officer'}}),
      }),
      withMockedModule('../src/services/departmentReviewerService', {
        resolveDepartmentReviewers:async()=>({primary:{reviewerId:ownRole==='department'?'employee':'head'}}),
      }),
      withMockedModule('../src/services/officialSignatoryService', {
        ROLE_KEYS:{},resolveActiveMayor:async()=>({employee_id:'mayor',name:'Test Mayor',position_title:'Municipal Mayor'}),
      }),
    ];
    const route='../src/routes/leaveRoutes';clearModule(route);
    try {
      const router=require(route);
      const res={code:200,status(n){this.code=n;return this;},json(v){this.body=v;}};
      await router.stack.find(r=>r.route?.path==='/signatories').route.stack.at(-1).handle(
        {user:{id:'employee',role:'employee'},query:{employee_id:'employee',leave_request_id:'request'}},res);
      assert.equal(res.code,200);
      const slot=ownRole==='hr'?'hr_certification_officer':'recommendation_officer';
      assert.equal(res.body[slot]?.name,'Test Mayor');
      assert.equal(res.body[slot]?.user_id,'mayor');
      assert.equal(res.body[slot]?.position_title,'Municipal Mayor');
    }finally{clearModule(route);restores.reverse().forEach(r=>r());}
  });
}

for (const primary of [{ id: 'primary', name: 'Primary HR', position_title: 'HR Officer' }, null]) {
  test(`7.A uses the primary final HR reviewer (${primary ? 'configured' : 'missing'})`, async () => {
    const dates = [];
    const restores = [
      withMockedModule('../src/config/db', { pool: { query: async (sql) => ({ rows: sql.includes('FROM leave_requests lr') ? [{ employee_id: 'employee', submitted_on: '2026-09-01', approved_on: '2026-09-30', status: 'approved', approving_authority_snapshot: { employee_id: 'mayor', name: 'Mayor' } }] : [] }) } }),
      withMockedModule('../src/services/leaveFinalReviewerService', {
        resolveFinalLeaveReviewerConfiguration: async (_, date) => { dates.push(date); return { primary, backups: [{ id: 'backup', name: 'Backup' }] }; },
      }),
      withMockedModule('../src/services/officialSignatoryService', {
        ROLE_KEYS: { LEAVE_CREDIT_CERTIFIER: 'leave_credit_certifier' },
        resolveOfficialSignatory: async () => ({ employee_id: 'old-certifier', name: 'Old Certifier' }),
      }),
    ];
    const route = '../src/routes/leaveRoutes';
    clearModule(route);
    try {
      const router = require(route);
      const res = { code: 200, status(n) { this.code = n; return this; }, json(body) { this.body = body; } };
      await router.stack.find(l => l.route?.path === '/signatories').route.stack.at(-1).handle({ user: { id: 'employee', role: 'employee' }, query: { employee_id: 'employee', leave_request_id: 'request' } }, res);
      assert.equal(res.code, 200);
      assert.deepEqual(res.body.hr_certification_officer, primary ? { user_id: 'primary', name: 'Primary HR', position_title: 'HR Officer', department_name: null } : null);
      assert.deepEqual(dates, ['2026-09-30']);
      assert.equal(res.body.approving_authority.name, 'Mayor');
    } finally { clearModule(route); restores.reverse().forEach(restore => restore()); }
  });
}
