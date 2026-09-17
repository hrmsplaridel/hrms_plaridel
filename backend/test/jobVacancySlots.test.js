const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  vacancyListedHeadlineKey,
  vacancyPositionKey,
  findListedVacancyForPosition,
} = require('../src/utils/jobVacancySlots');

test('listed vacancy key uses the job title only', () => {
  assert.equal(
    vacancyListedHeadlineKey({
      headline: 'Administrative Aide',
      education: 'BSIT',
    }),
    'administrative aide',
  );
  assert.equal(
    vacancyListedHeadlineKey({
      education: 'BSIT',
      experience: '1 year',
    }),
    '',
  );
});

test('legacy position key still falls back to requirements', () => {
  assert.equal(vacancyPositionKey({ education: 'BSIT' }), 'bsit');
});

test('find listed vacancy ignores requirement-only rows', () => {
  const vacancies = [
    { education: 'BSIT', experience: '1 year' },
    { headline: 'Administrative Aide' },
  ];
  assert.equal(findListedVacancyForPosition(vacancies, 'BSIT'), null);
  assert.equal(
    findListedVacancyForPosition(vacancies, 'Administrative Aide')?.headline,
    'Administrative Aide',
  );
});
