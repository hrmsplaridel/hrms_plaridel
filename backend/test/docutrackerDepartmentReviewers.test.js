const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseSteps,
  resolveStepAssignees,
} = require('../src/services/docutrackerWorkflowService');

const DEPARTMENT_ID = '00000000-0000-0000-0000-000000000201';
const HEAD_ID = '00000000-0000-0000-0000-000000000301';
const BACKUP_ID = '00000000-0000-0000-0000-000000000302';

test('DocuTracker preserves the department reviewer source in routing JSON', () => {
  const steps = parseSteps([{
    step_order: 1,
    assignee_type: 'user',
    assignee_source: 'department_reviewers',
    department_id: DEPARTMENT_ID,
    user_ids: [],
  }]);
  assert.equal(steps[0].assignee_source, 'department_reviewers');
});

test('DocuTracker resolves the effective Head and backups for an automatic step', async () => {
  let primaryQuery = '';
  const client = {
    async query(sql) {
      const text = String(sql);
      if (text.includes('JOIN position_department_head_periods head_period')) {
        primaryQuery = text;
        return {
          rows: [{ reviewer_id: HEAD_ID, reviewer_name: 'Department Head' }],
        };
      }
      if (text.includes('FROM department_reviewer_backups b')) {
        return {
          rows: [{
            reviewer_id: BACKUP_ID,
            reviewer_name: 'Backup Reviewer',
            backup_rank: 1,
          }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const reviewers = await resolveStepAssignees(client, {
    explicitAssigneeId: null,
    stepConfig: {
      step_order: 2,
      assignee_type: 'user',
      assignee_source: 'department_reviewers',
      department_id: DEPARTMENT_ID,
    },
    currentHolderId: null,
    documentType: 'memo',
    workflowVersion: 1,
  });

  assert.deepEqual(reviewers, [HEAD_ID, BACKUP_ID]);
  assert.match(primaryQuery, /head_period\.effective_from <= \$2::date/);
  assert.match(primaryQuery, /a\.is_active = true/);
  assert.match(primaryQuery, /p\.is_active = true/);
});
