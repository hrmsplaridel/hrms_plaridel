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

function parseAssistantDateRange(message, options = {}) {
  const text = String(message || '').toLowerCase();
  const today = options.today || todayInHrmsTimezone(options.now);
  const explicit = text.match(/\b(\d{4}-\d{2}-\d{2})\b/);

  if (explicit) {
    return {
      label: explicit[1],
      startDate: explicit[1],
      endDate: explicit[1],
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
  parseAssistantDateRange,
  todayInHrmsTimezone,
};
