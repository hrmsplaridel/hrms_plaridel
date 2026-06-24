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

const NUMBER_WORDS = {
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
  ten: 10,
};

function parsedCount(value) {
  return NUMBER_WORDS[value] || Number(value);
}

function pad2(value) {
  return String(value).padStart(2, '0');
}

function dateFromParts(year, month, day) {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

function daysInMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function startOfMonth(isoDate) {
  return `${String(isoDate).slice(0, 7)}-01`;
}

function semiMonthlyPeriodForDate(isoDate) {
  const [year, month, day] = String(isoDate).split('-').map(Number);
  if (day <= 15) {
    return {
      startDate: dateFromParts(year, month, 1),
      endDate: dateFromParts(year, month, 15),
    };
  }
  return {
    startDate: dateFromParts(year, month, 16),
    endDate: dateFromParts(year, month, daysInMonth(year, month)),
  };
}

function nextSemiMonthlyPeriod(period) {
  const [, , startDay] = String(period.startDate).split('-').map(Number);
  if (startDay === 1) {
    return {
      startDate: `${period.startDate.slice(0, 7)}-16`,
      endDate: endOfMonth(period.startDate),
    };
  }
  const nextMonth = addMonths(period.startDate, 1);
  return {
    startDate: startOfMonth(nextMonth),
    endDate: `${nextMonth.slice(0, 7)}-15`,
  };
}

function previousSemiMonthlyPeriod(period) {
  const [, , startDay] = String(period.startDate).split('-').map(Number);
  if (startDay === 16) {
    return {
      startDate: `${period.startDate.slice(0, 7)}-01`,
      endDate: `${period.startDate.slice(0, 7)}-15`,
    };
  }
  const previousMonth = addMonths(period.startDate, -1);
  return {
    startDate: `${previousMonth.slice(0, 7)}-16`,
    endDate: endOfMonth(previousMonth),
  };
}

function semiMonthlyPeriodByOffset(today, offset) {
  let period = semiMonthlyPeriodForDate(today);
  let remaining = Number(offset || 0);
  while (remaining > 0) {
    period = nextSemiMonthlyPeriod(period);
    remaining -= 1;
  }
  while (remaining < 0) {
    period = previousSemiMonthlyPeriod(period);
    remaining += 1;
  }
  return period;
}

function ordinalWeekdayOfMonth(year, month, weekday, ordinal) {
  if (ordinal === 'last') {
    let date = dateFromParts(year, month, daysInMonth(year, month));
    while (dayOfWeekMondayIndex(date) !== weekday) {
      date = addDays(date, -1);
    }
    return date;
  }
  const ordinalNumber = {
    first: 1,
    '1st': 1,
    second: 2,
    '2nd': 2,
    third: 3,
    '3rd': 3,
    fourth: 4,
    '4th': 4,
  }[ordinal];
  if (!ordinalNumber) return null;
  let date = dateFromParts(year, month, 1);
  const offset = (weekday - dayOfWeekMondayIndex(date) + 7) % 7;
  date = addDays(date, offset + (ordinalNumber - 1) * 7);
  return Number(date.slice(5, 7)) === month ? date : null;
}

function ordinalWeekOfMonth(year, month, ordinal) {
  const lastDay = daysInMonth(year, month);
  if (ordinal === 'last') {
    const startDay = Math.max(1, lastDay - 6);
    return {
      startDate: dateFromParts(year, month, startDay),
      endDate: dateFromParts(year, month, lastDay),
    };
  }
  const ordinalNumber = {
    first: 1,
    '1st': 1,
    second: 2,
    '2nd': 2,
    third: 3,
    '3rd': 3,
    fourth: 4,
    '4th': 4,
  }[ordinal];
  if (!ordinalNumber) return null;
  const startDay = (ordinalNumber - 1) * 7 + 1;
  if (startDay > lastDay) return null;
  return {
    startDate: dateFromParts(year, month, startDay),
    endDate: dateFromParts(year, month, Math.min(startDay + 6, lastDay)),
  };
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
  const monthNames = Object.keys(MONTHS).join('|');
  const weekdayNames = Object.keys(WEEKDAYS).join('|');
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

  const markedMonthDay = text.match(
    new RegExp(
      `\\b(?:on|sa|pag|noong|nung|adtong|adtung|atong|niadtong|niadtung)\\s+(${monthNames})\\s+(\\d{1,2})(?:,?\\s*(20\\d{2}))?\\b`
    )
  );
  if (markedMonthDay) {
    const currentYear = Number(today.slice(0, 4));
    const year = Number(markedMonthDay[3] || currentYear);
    const date = dateFromParts(year, MONTHS[markedMonthDay[1]], Number(markedMonthDay[2]));
    return { label: date, startDate: date, endDate: date };
  }

  const markedDayOnly = text.match(
    /\b(?:sa|pag|noong|nung|adtong|adtung|atong|niadtong|niadtung)\s+(\d{1,2})(?:st|nd|rd|th)?\b(?!\s*(?:day|days|adlaw|ka adlaw))/i
  );
  if (markedDayOnly) {
    const currentYear = Number(today.slice(0, 4));
    const currentMonth = Number(today.slice(5, 7));
    const date = dateFromParts(currentYear, currentMonth, Number(markedDayOnly[1]));
    return { label: date, startDate: date, endDate: date };
  }

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

  const ordinalWeekday = text.match(
    new RegExp(
      `\\b(first|1st|second|2nd|third|3rd|fourth|4th|last)\\s+(${weekdayNames})\\s+(?:of|in|sa)\\s+(${monthNames})(?:,?\\s*(20\\d{2}))?\\b`
    )
  );
  if (ordinalWeekday) {
    const currentYear = Number(today.slice(0, 4));
    const year = Number(ordinalWeekday[4] || currentYear);
    const date = ordinalWeekdayOfMonth(
      year,
      MONTHS[ordinalWeekday[3]],
      WEEKDAYS[ordinalWeekday[2]],
      ordinalWeekday[1]
    );
    if (date) {
      return {
        label: `${ordinalWeekday[1]} ${ordinalWeekday[2]} of ${ordinalWeekday[3]}`,
        startDate: date,
        endDate: date,
      };
    }
  }

  const ordinalWeek = text.match(
    new RegExp(
      `\\b(first|1st|second|2nd|third|3rd|fourth|4th|last)\\s+(?:week|semana|semanaha|linggo)\\s+(?:of|in|sa|ng|nga|for)\\s+(${monthNames})(?:,?\\s*(20\\d{2}))?\\b`
    )
  );
  if (ordinalWeek) {
    const currentYear = Number(today.slice(0, 4));
    const year = Number(ordinalWeek[3] || currentYear);
    const period = ordinalWeekOfMonth(year, MONTHS[ordinalWeek[2]], ordinalWeek[1]);
    if (period) {
      return {
        label: `${ordinalWeek[1]} week of ${ordinalWeek[2]}`,
        startDate: period.startDate,
        endDate: period.endDate,
      };
    }
  }

  const firstSecondCutoff = text.match(
    new RegExp(
      `\\b(first|1st|second|2nd)\\s+(?:pay\\s*period|payroll\\s*period|cut[-\\s]?off|cutoff)(?:\\s+(?:of|in|sa|for)\\s+(${monthNames})(?:,?\\s*(20\\d{2}))?)?\\b`
    )
  );
  if (firstSecondCutoff) {
    const currentYear = Number(today.slice(0, 4));
    const currentMonth = Number(today.slice(5, 7));
    const year = Number(firstSecondCutoff[3] || currentYear);
    const month = firstSecondCutoff[2] ? MONTHS[firstSecondCutoff[2]] : currentMonth;
    const startDate =
      firstSecondCutoff[1] === 'first' || firstSecondCutoff[1] === '1st'
        ? dateFromParts(year, month, 1)
        : dateFromParts(year, month, 16);
    const endDate =
      firstSecondCutoff[1] === 'first' || firstSecondCutoff[1] === '1st'
        ? dateFromParts(year, month, 15)
        : dateFromParts(year, month, daysInMonth(year, month));
    return {
      label: `${firstSecondCutoff[1]} cutoff`,
      startDate,
      endDate,
    };
  }

  const payPeriod = text.match(
    /\b(?:(last|previous|next|this|current|upcoming)\s+)?(pay\s*period|payroll\s*period|cut[-\s]?off|cutoff)\b/
  );
  if (payPeriod) {
    const qualifier = payPeriod[1] || 'current';
    const phrase = payPeriod[2] || 'cutoff';
    let offset = 0;
    if (qualifier === 'last' || qualifier === 'previous') offset = -1;
    if (qualifier === 'next' && /pay/.test(phrase)) offset = 1;
    const period = semiMonthlyPeriodByOffset(today, offset);
    return {
      label: `${qualifier} ${phrase.replace(/\s+/g, ' ')}`,
      startDate: period.startDate,
      endDate: period.endDate,
    };
  }

  const monthOnly = text.match(
    new RegExp(
      `\\b(?:in|sa|pag|noong|nung|adtong|adtung|atong|niadtong|niadtung|last\\s+)?(${monthNames})(?:\\s+(?:nga\\s+)?(?:month|bulan|bulana|buwan|buwana))?(?:,?\\s*(20\\d{2}))?\\b`
    )
  );
  if (monthOnly && !(monthOnly[1] === 'may' && /\bmay\s+(pasok|duty|trabaho|work)\b/.test(text))) {
    const currentYear = Number(today.slice(0, 4));
    const year = Number(monthOnly[2] || currentYear);
    const month = MONTHS[monthOnly[1]];
    const startDate = dateFromParts(year, month, 1);
    return { label: `${monthOnly[1]} ${year}`, startDate, endDate: endOfMonth(startDate) };
  }

  if (/\b(tomorrow|ugma|bukas|next day|following day|sunod adlaw|sunod nga adlaw|kinabukasan)\b/.test(text)) {
    const date = addDays(today, 1);
    return { label: 'tomorrow', startDate: date, endDate: date };
  }

  if (/\b(yesterday|kagahapon|gahapon|kahapon|previous day|day before|miaging adlaw|niaging adlaw|nakaraang araw)\b/.test(text)) {
    const date = addDays(today, -1);
    return { label: 'yesterday', startDate: date, endDate: date };
  }

  const countToken = '(\\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)';
  const daysAgo = text.match(new RegExp(`\\b${countToken}\\s+days?\\s+ago\\b`));
  if (daysAgo) {
    const count = parsedCount(daysAgo[1]);
    const date = addDays(today, -count);
    return {
      label: `${count} ${count === 1 ? 'day' : 'days'} ago`,
      startDate: date,
      endDate: date,
    };
  }

  const weeksAgo = text.match(new RegExp(`\\b${countToken}\\s+weeks?\\s+ago\\b`));
  if (weeksAgo) {
    const count = parsedCount(weeksAgo[1]);
    const startDate = startOfWeekMonday(addDays(today, -count * 7));
    return {
      label: `${count} ${count === 1 ? 'week' : 'weeks'} ago`,
      startDate,
      endDate: addDays(startDate, 6),
    };
  }

  const monthsAgo = text.match(new RegExp(`\\b${countToken}\\s+months?\\s+ago\\b`));
  if (monthsAgo) {
    const count = parsedCount(monthsAgo[1]);
    const month = addMonths(today, -count);
    const startDate = startOfMonth(month);
    return {
      label: `${count} ${count === 1 ? 'month' : 'months'} ago`,
      startDate,
      endDate: endOfMonth(month),
    };
  }

  const weekdayRange = text.match(
    new RegExp(
      `\\b(?:from\\s+)?(?:(last|previous|next|this|current)\\s+)?(${weekdayNames})\\s*(?:to|until|through|-|–)\\s*(?:(last|previous|next|this|current)\\s+)?(${weekdayNames})\\b`
    )
  );
  if (weekdayRange) {
    const startQualifier = weekdayRange[1] || 'this';
    const endQualifier = weekdayRange[3] || startQualifier;
    const qualifierOffset = (qualifier) => {
      if (qualifier === 'last' || qualifier === 'previous') return -7;
      if (qualifier === 'next') return 7;
      return 0;
    };
    const thisWeekStart = startOfWeekMonday(today);
    const startWeek = addDays(thisWeekStart, qualifierOffset(startQualifier));
    const endWeek = addDays(thisWeekStart, qualifierOffset(endQualifier));
    const startDate = addDays(startWeek, WEEKDAYS[weekdayRange[2]]);
    let endDate = addDays(endWeek, WEEKDAYS[weekdayRange[4]]);
    if (endDate < startDate) endDate = addDays(endDate, 7);
    return {
      label: `${weekdayRange[2]} to ${weekdayRange[4]}`,
      startDate,
      endDate,
    };
  }

  const nextWeekday = text.match(
    new RegExp(`\\b(?:next|sunod|sunod nga|sunod na)\\s+(${weekdayNames})\\b`)
  );
  if (nextWeekday) {
    const date = weekdayDate(today, WEEKDAYS[nextWeekday[1]], 'next');
    return { label: `next ${nextWeekday[1]}`, startDate: date, endDate: date };
  }

  const previousWeekday = text.match(
    new RegExp(
      `\\b(?:last|previous|niaging|miaging|adtong|adtung|atong|niadtong|niadtung|noong|nung|nakaraang)\\s+(?:niaging\\s+|miaging\\s+)?(${weekdayNames})\\b`
    )
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

  if (/\b(last month|previous month|niaging buwan|miaging buwan|niaging bulan|miaging bulan|niaging bulana|miaging bulana)\b/.test(text)) {
    const lastMonth = addMonths(today, -1);
    const startDate = `${lastMonth.slice(0, 7)}-01`;
    return { label: 'last month', startDate, endDate: endOfMonth(lastMonth) };
  }

  if (/\b(next month|sunod buwan|sunod nga buwan|sunod bulan|sunod nga bulan|sunod bulana|sunod nga bulana)\b/.test(text)) {
    const nextMonth = addMonths(today, 1);
    const startDate = `${nextMonth.slice(0, 7)}-01`;
    return { label: 'next month', startDate, endDate: endOfMonth(nextMonth) };
  }

  if (/\b(this week|current week|karong semanaha|karon nga semana|karong semana|this semana|week|semana|semanaha)\b/.test(text)) {
    const startDate = startOfWeekMonday(today);
    return { label: 'this week', startDate, endDate: addDays(startDate, 6) };
  }

  if (/\b(this month|current month|aning bulana|ani nga bulan|niining bulana|niini nga bulan|karong bulana|karon nga bulan|karong buwan|karon nga buwan|month|bulan|bulana|buwan|buwana)\b/.test(text)) {
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
