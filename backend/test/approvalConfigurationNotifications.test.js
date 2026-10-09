const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

for (const fail of [false, true]) {
  test(`configuration alerts are deduplicated and published only after commit (fail=${fail})`, async () => {
    const events = [];
    let alreadySent = false;
    const client = {async query(sql) {
      events.push(sql);
      if (sql.includes('SELECT u.id')) {
        assert.match(sql, /approvals_allowed = true/);
        assert.match(sql, /NOT EXISTS/);
        return { rows: alreadySent ? [] : [{id:'config-admin'}] };
      }
      if (sql === 'COMMIT') alreadySent = true;
      return {rows:[]};
    },release(){events.push('release');}};
    const pool = {connect:async()=>client};
    const restore = withMockedModule('../src/services/notificationService', {
      insertNotification: async (_, payload) => {
        assert.equal(payload.deferDelivery,true);
        assert.equal(payload.type,'approval_configuration_required');
        if (fail) throw new Error('write failed');
        return {user_id:payload.userId};
      },
      publishNotification: () => {assert.ok(events.includes('COMMIT'));events.push('push');},
    });
    const path='../src/services/approvalConfigurationNotifications';
    clearModule(path);
    try {
      const {notifyMissingFinalReviewer}=require(path);
      if (fail) {
        await assert.rejects(notifyMissingFinalReviewer(pool,'leave','request'),/write failed/);
        assert.ok(events.includes('ROLLBACK'));
        assert.equal(events.includes('push'),false);
      } else {
        await notifyMissingFinalReviewer(pool,'leave','request');
        await notifyMissingFinalReviewer(pool,'leave','request');
        assert.equal(events.filter(e=>e==='push').length,1);
        assert.ok(events.some(e=>e.includes('pg_advisory_xact_lock')));
      }
    } finally {clearModule(path);restore();}
  });
}
