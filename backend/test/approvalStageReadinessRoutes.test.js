const test = require('node:test');
const assert = require('node:assert/strict');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');
const applicant = '11111111-1111-4111-8111-111111111111';
const actor = '22222222-2222-4222-8222-222222222222';
const backup = '33333333-3333-4333-8333-333333333333';
const request = '44444444-4444-4444-8444-444444444444';

for (const kind of ['leave', 'locator']) {
  for (const finalAvailable of [false, true]) {
    test(`${kind} department endorsement requires a different final reviewer; available=${finalAvailable}`, async () => {
      const row = {id:request, user_id:applicant, employee_id:applicant, status:'pending_department_head',
        final_review_route:'hr', start_date:'2026-10-20', end_date:'2026-10-20',
        slip_date:'2026-10-20', request_type:'locator', am_in:true, days:1,
        leave_type_name:'customLeave', signature_revision:1};
      const sqls = [];
      let signatureWrites = 0;
      const query = async (sql, params=[]) => {
        sqls.push(sql);
        if (sql.includes('FOR UPDATE OF')) return {rows:[{...row}]};
        if (sql.includes('primary_reviewer_designations')) return {rows:[{id:actor}]};
        if (sql.includes('leave_final_reviewer_backups')) return {rows:finalAvailable ? [{id:backup}] : []};
        if (sql.startsWith('SELECT final_review_route')) return {rows:[{final_review_route:'hr'}]};
        if (/UPDATE (leave_requests|locator_slips)/.test(sql)) row.status='pending_hr';
        if (sql.startsWith('SELECT lr.*') || sql.includes('FROM locator_slips ls') && sql.includes('ls.*')) return {rows:[{...row}]};
        return {rows:[]};
      };
      const readPool = async sql => ({rows: sql.startsWith('SELECT lr.*') ||
        sql.includes('FROM locator_slips ls') && sql.includes('ls.*') ? [{...row}] : []});
      const restores = [withMockedModule('../src/config/db', {pool:{query:readPool,connect:async()=>({query,release(){}})}})];
      if (kind==='leave') {
        const signatures=require('../src/services/docutrackerLeaveSignatureService');
        restores.push(withMockedModule('../src/services/docutrackerLeaveSignatureService', {...signatures,
          requireDepartmentHeadApprovalSignature:async()=>{signatureWrites++;}}));
        const notifications=require('../src/services/leaveNotifications');
        restores.push(withMockedModule('../src/services/leaveNotifications',{...notifications,
          notifyDepartmentHeadApprovedForHr:async()=>{},notifyEmployee:async()=>{}}));
      } else {
        const signatures=require('../src/services/locatorSignatureService');
        restores.push(withMockedModule('../src/services/locatorSignatureService', {...signatures,
          persistLocatorSignature:async()=>{signatureWrites++;}}));
        const departments=require('../src/services/departmentHeadService');
        restores.push(withMockedModule('../src/services/departmentHeadService', {...departments,
          isDepartmentHead:async()=>({departmentId:request,isDeptHead:true})}));
        const conflicts=require('../src/services/locatorConflictPolicy');
        restores.push(withMockedModule('../src/services/locatorConflictPolicy', {...conflicts,
          findLocatorRequestConflicts:async()=>({ok:true})}));
        const notifications=require('../src/services/locatorNotifications');
        restores.push(withMockedModule('../src/services/locatorNotifications', {...notifications,
          notifyDepartmentHeadApprovedForEmployee:async()=>{},notifyDepartmentHeadApprovedForHr:async()=>{}}));
      }
      const path=`../src/routes/${kind==='leave' ? 'leaveRoutes' : 'locatorSlips'}`;
      clearModule(path);
      const originalError=console.error;
      try {
        console.error=()=>{};
        const handle=require(path).stack.find(s=>s.route?.path==='/:id/department-head-approve').route.stack.at(-1).handle;
        const res={code:200,status(n){this.code=n;return this;},json(v){this.body=v;return this;}};
        await handle({user:{id:actor,role:'admin'},params:{id:request},body:{}},res);
        assert.equal(res.code,finalAvailable ? 200 : 409,JSON.stringify(res.body));
        if (!finalAvailable) {
          assert.match(res.body.error,/another|different|distinct/i);
          assert.equal(row.status,'pending_department_head');
          assert.equal(signatureWrites,0);
          assert.equal(sqls.some(sql=>/UPDATE (leave_requests|locator_slips)|INSERT INTO (leave_request_history|locator_slip_history)/.test(sql)),false);
          assert.ok(sqls.includes('ROLLBACK'));
          assert.equal(sqls.includes('COMMIT'),false);
        } else {
          assert.equal(row.status,'pending_hr');
          assert.ok(sqls.includes('COMMIT'));
        }
      } finally {console.error=originalError;clearModule(path);restores.reverse().forEach(restore=>restore());}
    });
  }
}

test('returned Locator resubmission rejects overlapping stages before changing the request', async () => {
  const row={id:request,employee_id:applicant,status:'returned_for_correction',slip_date_text:'2026-10-20',
    slip_date:'2026-10-20',request_type:'locator',am_in:true,office:'Office',reason:'Visit'};
  const sqls=[];
  const query=async sql=>{
    sqls.push(sql);
    if(sql.includes('FOR UPDATE OF ls'))return {rows:[{...row}]};
    if(sql.includes('FROM locator_request_types'))return {rows:[{code:'locator',is_active:true,approval_route:'hr'}]};
    if(sql.includes('primary_reviewer_designations'))return {rows:[{id:actor,role:'hr'}]};
    return {rows:[]};
  };
  const departments=require('../src/services/departmentHeadService');
  const filing=require('../src/services/locatorFilingRules');
  const conflicts=require('../src/services/locatorConflictPolicy');
  const dates=require('../src/services/locatorDatePolicy');
  const restores=[
    withMockedModule('../src/config/db',{pool:{query:async()=>({rows:[]}),connect:async()=>({query,release(){}})}}),
    withMockedModule('../src/services/departmentHeadService',{...departments,
      getDepartmentReviewSnapshotForDate:async()=>({departmentHeadUserId:actor,reviewerUserIds:[actor]})}),
    withMockedModule('../src/services/locatorFilingRules',{...filing,validateLocatorWorkingDayForEmployee:async()=>({ok:true})}),
    withMockedModule('../src/services/locatorConflictPolicy',{...conflicts,findLocatorRequestConflicts:async()=>({ok:true})}),
    withMockedModule('../src/services/locatorDatePolicy',{...dates,
      evaluateEmployeeLocatorDateWindow:()=>({ok:true}),evaluateLocatorEmployeeCorrectionWindow:()=>({ok:true})}),
  ];
  clearModule('../src/routes/locatorSlips');
  const originalError=console.error;
  try {
    console.error=()=>{};
    const handle=require('../src/routes/locatorSlips').stack.find(s=>s.route?.path==='/:id/resubmit').route.stack.at(-1).handle;
    const res={code:200,status(n){this.code=n;return this;},json(v){this.body=v;return this;}};
    await handle({params:{id:request},user:{id:applicant,role:'employee'},body:{}},res);
    assert.equal(res.code,409,JSON.stringify(res.body));
    assert.match(res.body.error,/different final HR reviewer/i);
    assert.equal(sqls.some(sql=>/UPDATE locator_slips|INSERT INTO docutracker_locator_signatures/.test(sql)),false);
    assert.ok(sqls.includes('ROLLBACK'));
  } finally {console.error=originalError;clearModule('../src/routes/locatorSlips');restores.reverse().forEach(restore=>restore());}
});
