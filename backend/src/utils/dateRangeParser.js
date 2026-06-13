const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';

function todayInHrmsTimezone(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: HRMS_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const y = parts.find((p) => p.type === 'year')?.value || '';
  const m = parts.find((p) => p.type === 'month')?.value || '';
  const d = parts.find((p) => p.type === 'day')?.value || '';
  return `${y}-${m}-${d}`;
}

function addDays(isoDate, days) {
  const [year, month, day] = String(isoDate).split('-').map(Number);
  const dt = new Date(Date.UTC(year, month - 1, day + days));
  return dt.toISOString().slice(0, 10);
}

function startOfWeekMonday(isoDate) {
  const [year, month, day] = String(isoDate).split('-').map(Number);
  const dt = new Date(Date.UTC(year, month - 1, day));
  const utcDay = dt.getUTCDay();
  const offset = utcDay === 0 ? -6 : 1 - utcDay;
  return addDays(isoDate, offset);
}

function endOfMonth(isoDate) {
  const [year, month] = String(isoDate).split('-').map(Number);
  const dt = new Date(Date.UTC(year, month, 0));
  return dt.toISOString().slice(0, 10);
}

function addMonths(isoDate, months) {
  const [year, month] = String(isoDate).split('-').map(Number);
  const dt = new Date(Date.UTC(year, month - 1 + months, 1));
  return dt.toISOString().slice(0, 10);
}

const MONTHS = {
  january: 1,
  jan: 1,
  february: 2,
  feb: 2,
  march: 3,
  mar: 3,
  april: 4,
  apr: 4,
  may: 5,
  june: 6,
  jun: 6,
  july: 7,
  jul: 7,
  august: 8,
  aug: 8,
  september: 9,
  sep: 9,
  sept: 9,
  october: 10,
  oct: 10,
  november: 11,
  nov: 11,
  december: 12,
  dec: 12,
};

function pad2(value) {
  return String(value).padStart(2, '0');
}

function dateFromParts(year, month, day) {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

function parseAssistantDateRange(message, options = {}) {
  const text = String(message || '').toLowerCase();
  const today = options.today || todayInHrmsTimezone(options.now);
  const explicitRange = text.match(
    /\b(\d{4}-\d{2}-\d{2})\s*(?:to|until|through|-|–)\s*(\d{4}-\d{2}-\d{2})\b/
  );
  if (explicitRange) {
    return {
      label: `${explicitRange[1]} to ${explicitRange[2]}`,
      startDate: explicitRange[1],
      endDate: explicitRange[2],
    };
  }

  const explicit = text.match(/\b(\d{4}-\d{2}-\d{2})\b/);

  if (explicit) {
    return {
      label: explicit[1],
      startDate: explicit[1],
      endDate: explicit[1],
    };
  }

  const monthNames = Object.keys(MONTHS).join('|');
  const monthRange = text.match(
    new RegExp(
      `\\b(${monthNames})\\s+(\\d{1,2})(?:\\s*(?:to|until|through|-|–)\\s*(?:(${monthNames})\\s+)?(\\d{1,2}))?(?:,?\\s*(20\\d{2}))?\\b`
    )
  );
  if (monthRange) {
    const currentYear = Number(today.slice(0, 4));
    const year = Number(monthRange[5] || currentYear);
    const startMonth = MONTHS[monthRange[1]];
    const startDay = Number(monthRange[2]);
    const endMonth = monthRange[3] ? MONTHS[monthRange[3]] : startMonth;
    const endDay = monthRange[4] ? Number(monthRange[4]) : startDay;
    const startDate = dateFromParts(year, startMonth, startDay);
    const endDate = dateFromParts(year, endMonth, endDay);
    return {
      label: startDate === endDate ? startDate : `${startDate} to ${endDate}`,
      startDate,
      endDate,
    };
  }

  if (/\byesterday\b/.test(text)) {
    const date = addDays(today, -1);
    return { label: 'yesterday', startDate: date, endDate: date };
  }

  if (/\blast week\b/.test(text)) {
    const thisWeekStart = startOfWeekMonday(today);
    const startDate = addDays(thisWeekStart, -7);
    const endDate = addDays(startDate, 6);
    return { label: 'last week', startDate, endDate };
  }

  if (/\blast month\b/.test(text)) {
    const lastMonth = addMonths(today, -1);
    const startDate = `${lastMonth.slice(0, 7)}-01`;
    return { label: 'last month', startDate, endDate: endOfMonth(lastMonth) };
  }

  if (/\bthis week\b|\bweek\b/.test(text)) {
    const startDate = startOfWeekMonday(today);
    return { label: 'this week', startDate, endDate: addDays(startDate, 6) };
  }

  if (/\bthis month\b|\bmonth\b/.test(text)) {
    const startDate = `${today.slice(0, 7)}-01`;
    return { label: 'this month', startDate, endDate: endOfMonth(today) };
  }

  return {
    label: 'today',
    startDate: today,
    endDate: today,
  };
}

module.exports = {
  addDays,
  addMonths,
  parseAssistantDateRange,
  todayInHrmsTimezone,
};
