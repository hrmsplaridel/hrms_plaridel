const test = require('node:test');
const assert = require('node:assert/strict');

const {
  attachmentReplacementCleanupPath,
  assertRequiredLeaveAttachment,
  canModifyLeaveAttachment,
} = require('../src/services/leaveAttachmentPolicy');

test('attachment replacement cleans the new file on failure and old file after commit', () => {
  const oldPath = 'leave_requests/old.pdf';
  const newPath = 'leave_requests/new.pdf';

  assert.equal(
    attachmentReplacementCleanupPath({
      committed: false,
      oldAttachmentPath: oldPath,
      newAttachmentPath: newPath,
    }),
    newPath
  );
  assert.equal(
    attachmentReplacementCleanupPath({
      committed: true,
      oldAttachmentPath: oldPath,
      newAttachmentPath: newPath,
    }),
    oldPath
  );
  assert.equal(
    attachmentReplacementCleanupPath({
      committed: true,
      oldAttachmentPath: newPath,
      newAttachmentPath: newPath,
    }),
    null
  );
});

test('attachments can be changed only while a leave request is draft or returned', () => {
  assert.equal(canModifyLeaveAttachment('draft'), true);
  assert.equal(canModifyLeaveAttachment('returned'), true);

  for (const status of [
    'pending',
    'pending_department_head',
    'pending_hr',
    'approved',
    'rejected',
    'rejected_by_department_head',
    'rejected_by_hr',
    'cancelled',
  ]) {
    assert.equal(canModifyLeaveAttachment(status), false, status);
  }
});

test('final approval blocks a generally required attachment when it is missing', () => {
  assert.throws(
    () => assertRequiredLeaveAttachment({
      rule: { requires_attachment: true },
      leaveType: 'maternityLeave',
      days: 10,
      hasAttachment: false,
    }),
    /requires a supporting document.*missing/i
  );

  assert.doesNotThrow(() => assertRequiredLeaveAttachment({
    rule: { requires_attachment: true },
    leaveType: 'maternityLeave',
    days: 10,
    hasAttachment: true,
  }));
});

test('final approval applies the sick-leave attachment threshold', () => {
  const rule = {
    requires_attachment: false,
    requires_attachment_when_over_days: 5,
  };

  assert.doesNotThrow(() => assertRequiredLeaveAttachment({
    rule,
    leaveType: 'sickLeave',
    days: 4,
    hasAttachment: false,
  }));
  assert.throws(
    () => assertRequiredLeaveAttachment({
      rule,
      leaveType: 'sickLeave',
      days: 5,
      hasAttachment: false,
    }),
    /requires a supporting document/i
  );
});
