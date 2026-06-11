const PH_HOLIDAY_DEFAULTS = {
  2026: {
    country: 'PH',
    label: 'Philippines 2026 national holidays',
    source: 'Proclamation No. 1006, s. 2025 and dated Eid proclamations',
    note:
      "Special working days are not imported because they do not suspend work for DTR. Add Eid'l Adha separately when the dated proclamation is confirmed.",
    holidays: [
      regular('2026-01-01', "New Year's Day"),
      regular('2026-03-20', "Eid'l Fitr"),
      regular('2026-04-02', 'Maundy Thursday'),
      regular('2026-04-03', 'Good Friday'),
      special('2026-04-04', 'Black Saturday'),
      regular('2026-04-09', 'Araw ng Kagitingan'),
      regular('2026-05-01', 'Labor Day'),
      regular('2026-06-12', 'Independence Day'),
      special('2026-02-17', 'Chinese New Year'),
      special('2026-08-21', 'Ninoy Aquino Day'),
      regular('2026-08-31', 'National Heroes Day'),
      special('2026-11-01', "All Saints' Day"),
      special('2026-11-02', "All Souls' Day"),
      regular('2026-11-30', 'Bonifacio Day'),
      special('2026-12-08', 'Feast of the Immaculate Conception'),
      special('2026-12-24', 'Christmas Eve'),
      regular('2026-12-25', 'Christmas Day'),
      regular('2026-12-30', 'Rizal Day'),
      special('2026-12-31', 'Last Day of the Year'),
    ],
  },
};

function regular(date, name) {
  return holiday(date, name, 'regular');
}

function special(date, name) {
  return holiday(date, name, 'special');
}

function holiday(date, name, holidayType) {
  return {
    date_from: date,
    date_to: date,
    name,
    holiday_type: holidayType,
    description: 'PH national default holiday.',
    is_active: true,
    recurring: false,
    coverage: 'whole_day',
  };
}

function supportedYears() {
  return Object.keys(PH_HOLIDAY_DEFAULTS)
    .map((year) => Number(year))
    .sort((a, b) => a - b);
}

function getPhilippineHolidayDefaults(year) {
  const numericYear = Number(year);
  if (!Number.isInteger(numericYear)) return null;
  const template = PH_HOLIDAY_DEFAULTS[numericYear];
  if (!template) return null;
  return {
    ...template,
    year: numericYear,
    supported_years: supportedYears(),
    holidays: template.holidays.map((item) => ({ ...item })),
  };
}

module.exports = {
  getPhilippineHolidayDefaults,
  supportedYears,
};
