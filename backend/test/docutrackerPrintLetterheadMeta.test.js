const test = require('node:test');
const assert = require('node:assert/strict');

const {
  officialLetterheadFields,
} = require('../src/routes/docutrackerPrintTemplates');

test('official letterhead is named without becoming a custom print layout', () => {
  const fields = officialLetterheadFields({
    source_name: 'HR_A4.pdf',
    has_pdf: true,
  });
  assert.deepEqual(fields, {
    official_letterhead_name: 'HR_A4.pdf',
    has_official_letterhead: true,
  });
  assert.equal(Object.hasOwn(fields, 'print_layout'), false);
});

test('a missing letterhead stays disconnected', () => {
  assert.deepEqual(officialLetterheadFields(null), {
    official_letterhead_name: null,
    has_official_letterhead: false,
  });
  assert.deepEqual(
    officialLetterheadFields({ source_name: 'HR_A4.pdf', has_pdf: false }),
    {
      official_letterhead_name: null,
      has_official_letterhead: false,
    },
  );
});
