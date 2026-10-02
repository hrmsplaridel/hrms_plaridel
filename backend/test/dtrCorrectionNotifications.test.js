const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule } = require('./helpers/moduleMocks');

test('DTR submission and decisions use the shared in-app/push notification service', async () => {
  const sent = [];
  const restore = withMockedModule('../src/services/notificationService', {
    insertNotification: async (_, payload) => sent.push(payload),
    insertNotificationForUsers: async (_, ids, payload) => sent.push({ ids, ...payload }),
  });
  const path = require.resolve('../src/services/dtrCorrectionNotifications');
  delete require.cache[path];
  try {
    const service = require(path);
    const row = { id: 'request', employee_id: 'employee', attendance_date: '2026-09-30' };
    const db = { query: async (sql, args) => {
      assert.match(sql, /role IN \('admin','hr'\)/);
      assert.match(sql, /is_active = true/);
      assert.match(sql, /id <> \$1/);
      assert.deepEqual(args, ['employee']);
      return { rows: [{ id: 'reviewer' }] };
    } };
    await service.submitted(db, row);
    await service.reviewed(db, row, 'approved');
    await service.reviewed(db, row, 'rejected');
    assert.deepEqual(sent.map(n => n.type), ['dtr_correction_pending_review', 'dtr_correction_approved', 'dtr_correction_rejected']);
    assert.deepEqual(sent[0].ids, ['reviewer']);
    for (const n of sent) {
      assert.equal(n.category, 'dtr');
      assert.equal(n.referenceId, 'request');
      assert.equal(n.referenceType, 'dtr_correction');
    }
    assert.equal(sent[1].userId, 'employee');
    assert.equal(sent[2].userId, 'employee');
  } finally { delete require.cache[path]; restore(); }
});
