const test = require('node:test');
const assert = require('node:assert/strict');
const {
  sanitizeExamImagePath,
  sanitizeExamImageCaption,
  normalizeOptionImages,
  imagePathsFromRow,
  EXAM_IMAGE_FILE_RE,
} = require('../src/utils/examQuestionImages');

const good = 'exam-images/3f2b1c4e-1111-4222-8333-444455556666.png';
const good2 = 'exam-images/aaaaaaaa-1111-4222-8333-444455556666.webp';

test('sanitizeExamImagePath accepts only exam-images uploads', () => {
  assert.equal(sanitizeExamImagePath(good), good);
  assert.equal(sanitizeExamImagePath(`  ${good} `), good);
  assert.equal(sanitizeExamImagePath('exam-images/../../etc/passwd'), null);
  assert.equal(sanitizeExamImagePath('avatars/3f2b1c4e-1111-4222-8333-444455556666.png'), null);
  assert.equal(sanitizeExamImagePath('exam-images/a.gif'), null);
  assert.equal(sanitizeExamImagePath('https://evil.test/x.png'), null);
  assert.equal(sanitizeExamImagePath(null), null);
  assert.equal(sanitizeExamImagePath(5), null);
});

test('sanitizeExamImageCaption trims, caps length and drops blanks', () => {
  assert.equal(sanitizeExamImageCaption('  Figure 1  '), 'Figure 1');
  assert.equal(sanitizeExamImageCaption('   '), null);
  assert.equal(sanitizeExamImageCaption(undefined), null);
  assert.equal(sanitizeExamImageCaption('x'.repeat(500)).length, 300);
});

test('normalizeOptionImages keeps choice indexes aligned and returns null for text-only', () => {
  assert.equal(normalizeOptionImages(undefined, 4), null);
  assert.equal(normalizeOptionImages([null, null, null, null], 4), null);
  assert.deepEqual(normalizeOptionImages([null, good, 'bad', good2, good], 4), [
    null,
    good,
    null,
    good2,
  ]);
  assert.deepEqual(normalizeOptionImages([good], 3), [good, null, null]);
});

test('imagePathsFromRow lists question and choice images, ignores legacy rows', () => {
  assert.deepEqual(imagePathsFromRow({}), []);
  assert.deepEqual(
    imagePathsFromRow({
      question_image_path: good,
      option_images_json: [null, good2],
    }),
    [good, good2],
  );
});

test('EXAM_IMAGE_FILE_RE validates served file names', () => {
  assert.ok(EXAM_IMAGE_FILE_RE.test('3f2b1c4e-1111-4222-8333-444455556666.jpg'));
  assert.ok(!EXAM_IMAGE_FILE_RE.test('../secret.png'));
  assert.ok(!EXAM_IMAGE_FILE_RE.test('abc.png'));
});
