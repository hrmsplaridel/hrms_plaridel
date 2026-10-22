const test = require('node:test');
const assert = require('node:assert/strict');

const {
  listHrWorkflowMirrors,
  normalizeEffectiveDate,
} = require('../src/services/docutrackerHrWorkflowMirrorService');

test('HR workflow mirrors preserve department and final reviewer roles', async () => {
  const db = {
    query: async (sql) => {
      if(!String(sql).includes('FROM departments'))return {rows:[
        {module:'leave',type_id:'standard',type_name:'Annual Leave',workflow_id:'standard-workflow',name:'Standard',current_version:1,steps:['department','hr']},
        {module:'locator',type_id:'standard',type_name:'Locator',workflow_id:'standard-workflow',name:'Standard',current_version:1,steps:['department','hr']},
      ]};
      assert.match(sql, /FROM departments/);
      return {
        rows: [
          { id: 'dept-1', name: 'Finance' },
          { id: 'dept-2', name: 'Human Resources' },
        ],
      };
    },
  };
  const departmentReviewerResolver = async (_db, { departmentId }) => ({
    primary: {
      reviewerId: `head-${departmentId}`,
      reviewerName: `Head ${departmentId}`,
      reviewerRole: 'primary',
      backupRank: null,
    },
    backups: departmentId === 'dept-1'
      ? [{
          reviewerId: 'backup-1',
          reviewerName: 'Finance Backup',
          reviewerRole: 'backup',
          backupRank: 1,
        }]
      : [],
  });
  const finalReviewerResolver = async () => ({
    primary: { id: 'final-1', name: 'Primary HR' },
    backups: [{ id: 'final-2', name: 'Backup HR' }],
  });

  const result = await listHrWorkflowMirrors(db, {
    effectiveDate: '2026-09-29',
    departmentReviewerResolver,
    finalReviewerResolver,
  });

  assert.equal(result.effective_date, '2026-09-29');
  assert.deepEqual(
    result.workflows.map((workflow) => workflow.key),
    ['workflow:standard-workflow:v1']
  );
  assert.equal(result.workflows[0].title,'Standard v1');
  assert.deepEqual(result.workflows[0].used_by,[
    {module:'leave',type_id:'standard',type_name:'Annual Leave'},
    {module:'locator',type_id:'standard',type_name:'Locator'},
  ]);
  for (const workflow of result.workflows) {
    assert.equal(workflow.system_managed, true);
    assert.equal(workflow.steps[0].groups.length, 2);
    assert.match(workflow.steps[0].assignee_summary, /2 heads · 1 backup/);
    assert.equal(workflow.steps[1].groups[0].primary.name, 'Primary HR');
    assert.equal(workflow.steps[1].groups[0].backups[0].name, 'Backup HR');
  }
});

test('mirror grouping keeps different workflow identities and published versions separate',async()=>{
  const rows=[
    {module:'leave',type_id:'sick',type_name:'Sick Leave',workflow_id:'a',name:'Review',current_version:1,steps:['department','hr']},
    {module:'leave',type_id:'vacation',type_name:'Vacation Leave',workflow_id:'a',name:'Review',current_version:1,steps:['department','hr']},
    {module:'locator',type_id:'business',type_name:'Official Business',workflow_id:'a',name:'Review',current_version:1,steps:['department','hr']},
    {module:'leave',type_id:'other',type_name:'Other Leave',workflow_id:'b',name:'Review',current_version:1,steps:['hr']},
    {module:'locator',type_id:'travel',type_name:'Travel Order',workflow_id:'a',name:'Review',current_version:2,steps:['hr']},
  ];
  const result=await listHrWorkflowMirrors({query:async sql=>({rows:sql.includes('FROM departments')?[]:rows})},{
    effectiveDate:'2026-10-16',finalReviewerResolver:async()=>({primary:null,backups:[]}),
  });
  assert.equal(result.workflows.length,3);
  assert.equal(result.workflows.find(w=>w.key==='workflow:a:v1').used_by.length,3);
  assert.equal(result.workflows.find(w=>w.key==='workflow:b:v1').steps.length,1);
  assert.equal(result.workflows.find(w=>w.key==='workflow:a:v2').used_by[0].type_name,'Travel Order');
});

test('HR workflow mirror does not promote a backup into the primary slot', async () => {
  const result = await listHrWorkflowMirrors(
    { query: async () => ({ rows: [] }) },
    {
      effectiveDate: '2026-09-29',
      departmentReviewerResolver: async () => ({ primary: null, backups: [] }),
      finalReviewerResolver: async () => ({
        primary: null,
        backups: [{ id: 'backup-only', name: 'Backup Only' }],
      }),
    }
  );

  const finalGroup = result.reviewer_assignments.final_group;
  assert.equal(finalGroup.primary, null);
  assert.equal(finalGroup.backups[0].name, 'Backup Only');
  assert.deepEqual(result.workflows,[],'No configured types must not fabricate two-stage workflows');
});

test('HR workflow mirror rejects invalid effective dates', () => {
  assert.throws(
    () => normalizeEffectiveDate('2026-02-31'),
    /effective_date must be a valid YYYY-MM-DD date/
  );
});
