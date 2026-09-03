const PUNCH_LABELS = {
  time_in: 'Time In',
  break_out: 'AM Out',
  break_in: 'PM In',
  time_out: 'Time Out',
};

function isValidIsoDate(value) {
  const date = String(value || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
  const parsed = Date.parse(`${date}T00:00:00Z`);
  return Number.isFinite(parsed) && new Date(parsed).toISOString().slice(0, 10) === date;
}

function addIsoDays(date, days) {
  const parsed = Date.parse(`${date}T00:00:00Z`);
  return new Date(parsed + days * 86400000).toISOString().slice(0, 10);
}

function localTimestampParts(value, timeZone) {
  if (value == null || value === '') return null;
  const parsed = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(parsed);
  const read = (type) => parts.find((part) => part.type === type)?.value || '';
  const hour = Number(read('hour'));
  const minute = Number(read('minute'));
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return null;
  return {
    date: `${read('year')}-${read('month')}-${read('day')}`,
    minutes: hour * 60 + minute,
  };
}

function validateDtrPunchDates({
  attendanceDate,
  punches,
  shiftInfo,
  todayDate,
  timeZone = 'Asia/Manila',
}) {
  if (!isValidIsoDate(attendanceDate)) {
    return { valid: false, error: 'attendance_date must be a valid YYYY-MM-DD date.' };
  }
  if (isValidIsoDate(todayDate) && attendanceDate > todayDate) {
    return {
      valid: false,
      error: `Future attendance is not allowed. The latest permitted date is ${todayDate}.`,
    };
  }

  const startMinutes = shiftInfo?.startMinutes == null ? NaN : Number(shiftInfo.startMinutes);
  const endMinutes = shiftInfo?.endMinutes == null ? NaN : Number(shiftInfo.endMinutes);
  const isOvernight =
    Number.isFinite(startMinutes) &&
    Number.isFinite(endMinutes) &&
    endMinutes <= startMinutes;
  const followingDate = isOvernight ? addIsoDays(attendanceDate, 1) : null;

  for (const [key, value] of Object.entries(punches || {})) {
    if (value == null || value === '') continue;
    const local = localTimestampParts(value, timeZone);
    const label = PUNCH_LABELS[key] || key;
    if (!local) {
      return { valid: false, error: `${label} must be a valid timestamp.` };
    }
    if (local.date === attendanceDate) continue;
    if (
      isOvernight &&
      local.date === followingDate &&
      local.minutes <= endMinutes
    ) {
      continue;
    }
    const overnightSuffix = isOvernight
      ? ` or within the overnight shift ending ${followingDate}`
      : '';
    return {
      valid: false,
      error: `${label} must belong to ${attendanceDate} in ${timeZone}${overnightSuffix}.`,
    };
  }

  return { valid: true, isOvernight, followingDate };
}

module.exports = {
  addIsoDays,
  isValidIsoDate,
  localTimestampParts,
  validateDtrPunchDates,
};
