const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  vacancyListedHeadlineKey,
  vacancyPositionKey,
  findListedVacancyForPosition,
  parseVacancyAgeRequirements,
  vacancyMinimumAge,
  vacancyMaximumAge,
  ageOnCalendarDate,
  assertApplicantAgeForVacancy,
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

test('vacancy age rules reject invalid values and keep a blank maximum', () => {
  assert.equal(parseVacancyAgeRequirements('', null).ok, false);
  assert.equal(parseVacancyAgeRequirements(-1, null).ok, false);
  assert.equal(parseVacancyAgeRequirements('15.5', null).ok, false);
  assert.equal(parseVacancyAgeRequirements(15, '18.2').ok, false);

  const openEnded = parseVacancyAgeRequirements(15, '');
  assert.deepEqual(openEnded, { ok: true, minimumAge: 15, maximumAge: null });

  const range = parseVacancyAgeRequirements(18, 30);
  assert.equal(range.ok, true);
  assert.equal(range.maximumAge, 30);

  const inverted = parseVacancyAgeRequirements(18, 17);
  assert.equal(inverted.ok, false);
  assert.match(
    inverted.error,
    /Maximum age must be greater than or equal to minimum age/,
  );
});

test('missing vacancy age defaults to 18 with no maximum', () => {
  assert.equal(vacancyMinimumAge({}), 18);
  assert.equal(vacancyMaximumAge({}), null);
  assert.equal(vacancyMinimumAge({ minimum_age: 15 }), 15);
  assert.equal(vacancyMaximumAge({ maximum_age: 25 }), 25);
});

test('age uses the calendar date and the vacancy limits', () => {
  const today = '2026-10-10';
  assert.equal(ageOnCalendarDate('2010-10-10', today), 16);
  assert.equal(ageOnCalendarDate('2010-10-11', today), 15);
  assert.equal(ageOnCalendarDate('2008-10-10', today), 18);

  const immersion = assertApplicantAgeForVacancy(
    { minimum_age: 15 },
    '2010-10-10',
    today,
  );
  assert.equal(immersion.ok, true);
  assert.equal(immersion.age, 16);

  const belowRegular = assertApplicantAgeForVacancy(
    { minimum_age: 18 },
    '2010-10-10',
    today,
  );
  assert.equal(belowRegular.ok, false);
  assert.equal(belowRegular.code, 'AGE_BELOW_MINIMUM');
  assert.equal(
    belowRegular.error,
    'This vacancy requires applicants to be at least 18 years old.',
  );

  const exactMinimum = assertApplicantAgeForVacancy(
    { minimum_age: 18 },
    '2008-10-10',
    today,
  );
  assert.equal(exactMinimum.ok, true);
  assert.equal(exactMinimum.age, 18);

  const exactMaximum = assertApplicantAgeForVacancy(
    { minimum_age: 18, maximum_age: 30 },
    '1996-10-10',
    today,
  );
  assert.equal(exactMaximum.ok, true);
  assert.equal(exactMaximum.age, 30);

  const aboveMaximum = assertApplicantAgeForVacancy(
    { minimum_age: 18, maximum_age: 30 },
    '1995-10-09',
    today,
  );
  assert.equal(aboveMaximum.ok, false);
  assert.equal(aboveMaximum.code, 'AGE_ABOVE_MAXIMUM');
  assert.equal(
    aboveMaximum.error,
    'This vacancy accepts applicants up to 30 years old.',
  );

  const legacy = assertApplicantAgeForVacancy({}, '2010-01-01', today);
  assert.equal(legacy.ok, false);
  assert.match(legacy.error, /at least 18/);
});
