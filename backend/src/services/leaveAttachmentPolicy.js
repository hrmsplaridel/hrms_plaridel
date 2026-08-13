const { mustBlockMissingAttachment } = require('../routes/leaveTypeRules');

const ATTACHMENT_MUTABLE_STATUSES = new Set(['draft', 'returned']);

function canModifyLeaveAttachment(status) {
  return ATTACHMENT_MUTABLE_STATUSES.has(String(status || '').trim());
}

function attachmentReplacementCleanupPath({
  committed,
  oldAttachmentPath,
  newAttachmentPath,
}) {
  const oldPath = String(oldAttachmentPath || '').trim() || null;
  const newPath = String(newAttachmentPath || '').trim() || null;
  if (!committed) return newPath;
  return oldPath && oldPath !== newPath ? oldPath : null;
}

function assertRequiredLeaveAttachment({
  rule,
  leaveType,
  days,
  hasAttachment,
}) {
  if (!mustBlockMissingAttachment(rule, leaveType, days, hasAttachment === true)) {
    return;
  }
  const error = new Error(
    `${leaveType || 'This leave type'} requires a supporting document, but the attachment is missing. Return the request to the employee for correction before approval.`
  );
  error.statusCode = 400;
  throw error;
}

module.exports = {
  ATTACHMENT_MUTABLE_STATUSES,
  attachmentReplacementCleanupPath,
  assertRequiredLeaveAttachment,
  canModifyLeaveAttachment,
};
