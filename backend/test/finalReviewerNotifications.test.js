const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule } = require('./helpers/moduleMocks');

for (const kind of ['leave', 'locator']) {
  for (const configured of [true, false]) {
    test(`${kind} final-review notifications use assigned reviewers only (configured=${configured})`, async () => {
      const sent = [];
      const restore = withMockedModule('../src/services/notificationService', {
        getHrAdminUserIds: async () => ['applicant', 'unassigned-admin'],
        insertNotification: async (_, payload) => sent.push({ ids: [payload.userId], ...payload }),
        insertNotificationForUsers: async (_, ids, payload) => sent.push({ ids, ...payload }),
      });
      const alerts = [];
      const restoreAlerts = withMockedModule('../src/services/approvalConfigurationNotifications', { notifyMissingFinalReviewer: async (_, kind, id) => alerts.push({kind, id}) });
      const path = require.resolve(`../src/services/${kind}Notifications`);
      delete require.cache[path];
      const db = { query: async (sql) => {
        if (sql.includes('primary_reviewer_designations')) {
          assert.match(sql, /u.is_active = true/);
          assert.match(sql, /designation.effective_from <=/);
          return { rows: configured ? [{ id: 'primary' }] : [] };
        }
        if (sql.includes('FROM leave_final_reviewer_backups')) {
          assert.match(sql, /b.is_active = true/);
          assert.match(sql, /b.effective_to/);
          return { rows: configured ? [{ id: 'backup' }, { id: 'applicant' }, { id: 'backup' }] : [] };
        }
        if (sql.startsWith('SELECT final_review_route')) return {rows:[{final_review_route:'hr'}]};
        if (sql.includes('department_approver_id')) return { rows: [{ department_approver_id: 'primary' }] };
        throw new Error(`Unexpected query: ${sql}`);
      } };
      try {
        const service = require(path);
        const input = { employeeUserId: 'applicant', leaveRequestId: 'request', slipId: 'request', status: 'pending_hr' };
        await service.notifyAfterSubmit(db, input);
        await service.notifyAfterSubmit(db, { ...input, status: 'pending' });
        await service.notifyDepartmentHeadApprovedForHr(db, input);
        if (kind === 'leave') await service.notifyStakeholdersLeaveCancelled(db, input);
        for (const n of sent) assert.deepEqual(n.ids, configured ? ['backup'] : []);
        assert.equal(alerts.length, configured ? 0 : 3);
        sent.length = 0;
        await service.notifyAfterSubmit(db, { ...input, status: 'pending_department_head', departmentHeadUserId: 'head', departmentReviewerUserIds: ['head', 'dept-backup', 'applicant'] });
        assert.deepEqual(sent[0].ids, ['head', 'dept-backup']);
        await service.notifyEmployee(db, { ...input, type: 'approved' });
        assert.deepEqual(sent[1].ids, ['applicant']);
      } finally { delete require.cache[path]; restoreAlerts(); restore(); }
    });
  }
}
