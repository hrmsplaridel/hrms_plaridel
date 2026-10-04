const test = require('node:test');
const assert = require('node:assert/strict');
const { validateAttachment, MAX_SIZE } = require('../src/services/dtrCorrectionAttachment');
test('attachment is optional and verifies extension against content signature', () => {
  assert.equal(validateAttachment(null), null);
  for (const [name, bytes, mime] of [
    ['evidence.pdf', Buffer.from('%PDF-1.4\n'), 'application/pdf'],
    ['evidence.jpg', Buffer.from([255,216,255,224]), 'image/jpeg'],
    ['evidence.png', Buffer.from([137,80,78,71,13,10,26,10]), 'image/png'],
  ]) assert.equal(validateAttachment({ originalname: name, buffer: bytes }).mime, mime);
  assert.throws(() => validateAttachment({ originalname: 'fake.pdf', buffer: Buffer.from('not a pdf') }));
  assert.throws(() => validateAttachment({ originalname: 'file.svg', buffer: Buffer.from('<svg/>') }));
  assert.throws(() => validateAttachment({ originalname: 'file.pdf', buffer: Buffer.alloc(MAX_SIZE + 1) }));
  assert.throws(() => validateAttachment({ originalname: 'file.pdf', buffer: Buffer.alloc(0) }));
  assert.equal(validateAttachment({ originalname: '../test.pdf', buffer: Buffer.from('%PDF-1.4') }).name, 'test.pdf');
});
