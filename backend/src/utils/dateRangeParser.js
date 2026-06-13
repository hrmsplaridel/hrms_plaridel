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

function dayOfWeekMondayIndex(isoDate) {
  const [year, month, day] = String(isoDate).split('-').map(Number);
  const dt = new Date(Date.UTC(year, month - 1, day));
  const utcDay = dt.getUTCDay();
  return utcDay === 0 ? 6 : utcDay - 1;
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

const WEEKDAYS = {
  monday: 0,
  mon: 0,
  lunes: 0,
  tuesday: 1,
  tue: 1,
  tues: 1,
  martes: 1,
  wednesday: 2,
  wed: 2,
  miyerkules: 2,
  mierkules: 2,
  merkules: 2,
  thursday: 3,
  thu: 3,
  thurs: 3,
  huwebes: 3,
  jueves: 3,
  webes: 3,
  friday: 4,
  fri: 4,
  biyernes: 4,
  byernes: 4,
  bernes: 4,
  saturday: 5,
  sat: 5,
  sabado: 5,
  sunday: 6,
  sun: 6,
  domingo: 6,
};

function pad2(value) {
  return String(value).padStart(2, '0');
}

function dateFromParts(year, month, day) {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

function weekdayDate(today, targetWeekday, mode = 'next') {
  const current = dayOfWeekMondayIndex(today);
  let offset = targetWeekday - current;
  if (mode === 'next' && offset <= 0) offset += 7;
  if (mode === 'previous' && offset >= 0) offset -= 7;
  return addDays(today, offset);
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

  if (/\b(tomorrow|ugma|bukas)\b/.test(text)) {
    const date = addDays(today, 1);
    return { label: 'tomorrow', startDate: date, endDate: date };
  }

  if (/\b(yesterday|kagahapon|gahapon|kahapon)\b/.test(text)) {
    const date = addDays(today, -1);
    return { label: 'yesterday', startDate: date, endDate: date };
  }

  const weekdayNames = Object.keys(WEEKDAYS).join('|');
  const nextWeekday = text.match(
    new RegExp(`\\b(?:next|sunod|sunod nga|sunod na)\\s+(${weekdayNames})\\b`)
  );
  if (nextWeekday) {
    const date = weekdayDate(today, WEEKDAYS[nextWeekday[1]], 'next');
    return { label: `next ${nextWeekday[1]}`, startDate: date, endDate: date };
  }

  const previousWeekday = text.match(
    new RegExp(`\\b(?:last|previous|niaging|miaging)\\s+(${weekdayNames})\\b`)
  );
  if (previousWeekday) {
    const date = weekdayDate(today, WEEKDAYS[previousWeekday[1]], 'previous');
    return { label: `previous ${previousWeekday[1]}`, startDate: date, endDate: date };
  }

  if (/\b(last week|previous week|niaging semana|miaging semana|niaging semanaha|miaging semanaha)\b/.test(text)) {
    const thisWeekStart = startOfWeekMonday(today);
    const startDate = addDays(thisWeekStart, -7);
    const endDate = addDays(startDate, 6);
    return { label: 'last week', startDate, endDate };
  }

  if (/\b(next week|sunod semana|sunod nga semana|sunod semanaha|sunod nga semanaha)\b/.test(text)) {
    const thisWeekStart = startOfWeekMonday(today);
    const startDate = addDays(thisWeekStart, 7);
    return { label: 'next week', startDate, endDate: addDays(startDate, 6) };
  }

  if (/\b(last month|previous month|niaging buwan|miaging buwan|niaging bulan|miaging bulan)\b/.test(text)) {
    const lastMonth = addMonths(today, -1);
    const startDate = `${lastMonth.slice(0, 7)}-01`;
    return { label: 'last month', startDate, endDate: endOfMonth(lastMonth) };
  }

  if (/\b(next month|sunod buwan|sunod nga buwan|sunod bulan|sunod nga bulan)\b/.test(text)) {
    const nextMonth = addMonths(today, 1);
    const startDate = `${nextMonth.slice(0, 7)}-01`;
    return { label: 'next month', startDate, endDate: endOfMonth(nextMonth) };
  }

  if (/\b(this week|current week|karong semanaha|karon nga semana|karong semana|this semana|week|semana|semanaha)\b/.test(text)) {
    const startDate = startOfWeekMonday(today);
    return { label: 'this week', startDate, endDate: addDays(startDate, 6) };
  }

  if (/\b(this month|current month|karong bulana|karon nga bulan|karong buwan|karon nga buwan|month|bulan|buwan)\b/.test(text)) {
    const startDate = `${today.slice(0, 7)}-01`;
    return { label: 'this month', startDate, endDate: endOfMonth(today) };
  }

  if (/\b(today|karong adlawa|karon nga adlaw|karon|ngayon)\b/.test(text)) {
    return { label: 'today', startDate: today, endDate: today };
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
