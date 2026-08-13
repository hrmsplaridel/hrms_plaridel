const test = require('node:test');
const assert = require('node:assert/strict');

const {
  canModifyLocatorAttachment,
  validateLocatorAttachmentForReview,
} = require('../src/services/locatorFilingRules');

test('submitted locator attachments stay locked until formally returned', () => {
  assert.equal(canModifyLocatorAttachment('pending_department_head'), false);
  assert.equal(canModifyLocatorAttachment('pending_hr'), false);
  assert.equal(canModifyLocatorAttachment('approved'), false);
  assert.equal(canModifyLocatorAttachment('returned_for_correction'), true);
});

test('required locator attachment must have a database reference and physical file', () => {
  const locatorType = { requires_attachment: true };

  assert.match(
    validateLocatorAttachmentForReview({
      locatorType,
      attachmentPath: null,
      attachmentFileExists: false,
    }),
    /requires an attachment/i
  );
  assert.match(
    validateLocatorAttachmentForReview({
      locatorType,
      attachmentPath: 'locator-attachments/evidence.pdf',
      attachmentFileExists: false,
    }),
    /file is missing/i
  );
  assert.equal(
    validateLocatorAttachmentForReview({
      locatorType,
      attachmentPath: 'locator-attachments/evidence.pdf',
      attachmentFileExists: true,
    }),
    null
  );
});

test('optional locator types can be reviewed without an attachment', () => {
  assert.equal(
    validateLocatorAttachmentForReview({
      locatorType: { requires_attachment: false },
      attachmentPath: null,
      attachmentFileExists: false,
    }),
    null
  );
});
