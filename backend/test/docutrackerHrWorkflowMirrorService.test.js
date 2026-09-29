const test = require('node:test');
const assert = require('node:assert/strict');

const {
  listHrWorkflowMirrors,
  normalizeEffectiveDate,
} = require('../src/services/docutrackerHrWorkflowMirrorService');

test('HR workflow mirrors preserve department and final reviewer roles', async () => {
  const db = {
    query: async (sql) => {
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
    ['leave', 'locator']
  );
  for (const workflow of result.workflows) {
    assert.equal(workflow.system_managed, true);
    assert.equal(workflow.steps[0].groups.length, 2);
    assert.match(workflow.steps[0].assignee_summary, /2 heads · 1 backup/);
    assert.equal(workflow.steps[1].groups[0].primary.name, 'Primary HR');
    assert.equal(workflow.steps[1].groups[0].backups[0].name, 'Backup HR');
  }
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

  const finalGroup = result.workflows[0].steps[1].groups[0];
  assert.equal(finalGroup.primary, null);
  assert.equal(finalGroup.backups[0].name, 'Backup Only');
  assert.match(result.workflows[0].steps[1].assignee_summary, /No primary reviewer/);
});

test('HR workflow mirror rejects invalid effective dates', () => {
  assert.throws(
    () => normalizeEffectiveDate('2026-02-31'),
    /effective_date must be a valid YYYY-MM-DD date/
  );
});
