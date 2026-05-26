const NOON_MINUTES = 12 * 60;
const ONE_PM_MINUTES = 13 * 60;
const VALID_PUNCH_MODES = new Set([
  'auto',
  'full_day',
  'am_only',
  'pm_only',
  'single_session',
]);
const ensuredPunchModePools = new WeakMap();

function normalizePunchMode(value) {
  const raw = value == null ? 'auto' : String(value).trim().toLowerCase();
  return VALID_PUNCH_MODES.has(raw) ? raw : 'auto';
}

async function ensureShiftPunchModeColumn(pool) {
  let promise = ensuredPunchModePools.get(pool);
  if (!promise) {
    promise = pool.query(
      `ALTER TABLE shifts
       ADD COLUMN IF NOT EXISTS punch_mode TEXT NOT NULL DEFAULT 'auto'`
    );
    ensuredPunchModePools.set(pool, promise);
  }
  try {
    await promise;
  } catch (err) {
    ensuredPunchModePools.delete(pool);
    throw err;
  }
}

function getShiftType(shiftInfo) {
  if (!shiftInfo) return null;
  const explicit = normalizePunchMode(shiftInfo.punchMode ?? shiftInfo.punch_mode);
  if (explicit !== 'auto') return explicit;

  const { startMinutes, endMinutes, breakEndMinutes } = shiftInfo;
  if (startMinutes == null) return null;
  if (startMinutes >= NOON_MINUTES) return 'pm_only';
  if (breakEndMinutes == null && endMinutes != null && endMinutes <= ONE_PM_MINUTES) {
    return 'am_only';
  }
  return 'full_day';
}

function getExpectedWorkMinutes(shiftInfo) {
  if (!shiftInfo || shiftInfo.startMinutes == null || shiftInfo.endMinutes == null) {
    return 0;
  }
  const spanMinutes = Math.max(0, shiftInfo.endMinutes - shiftInfo.startMinutes);
  const type = getShiftType(shiftInfo);
  if (type !== 'full_day') return spanMinutes;
  const lunchMinutes =
    shiftInfo.breakEndMinutes != null
      ? Math.max(0, shiftInfo.breakEndMinutes - NOON_MINUTES)
      : 60;
  return Math.max(0, spanMinutes - lunchMinutes);
}

function getShiftExpectedLogs(shiftInfo) {
  const type = getShiftType(shiftInfo);
  if (!type) return { needsAm: true, needsPm: true, needsInOut: false };
  if (type === 'pm_only') return { needsAm: false, needsPm: true, needsInOut: false };
  if (type === 'am_only') return { needsAm: true, needsPm: false, needsInOut: false };
  if (type === 'single_session') return { needsAm: false, needsPm: false, needsInOut: true };
  return { needsAm: true, needsPm: true, needsInOut: false };
}

function getExpectedLogsForDay(shiftInfo, holidayInfo) {
  if (!holidayInfo || !holidayInfo.coverage) return getShiftExpectedLogs(shiftInfo);
  const cov = holidayInfo.coverage;
  if (cov === 'whole_day') return { needsAm: false, needsPm: false, needsInOut: false };
  if (cov === 'am_only') return { needsAm: false, needsPm: true, needsInOut: false };
  if (cov === 'pm_only') return { needsAm: true, needsPm: false, needsInOut: false };
  return getShiftExpectedLogs(shiftInfo);
}

function minutesFromMidnightInTimeZone(val, timeZone) {
  if (!val) return null;
  const d = val instanceof Date ? val : new Date(val);
  if (isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(d);
  const hh = parseInt(parts.find((p) => p.type === 'hour')?.value ?? '0', 10);
  const mm = parseInt(parts.find((p) => p.type === 'minute')?.value ?? '0', 10);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  return hh * 60 + mm;
}

function computeTotalHours(timeIn, timeOut, breakOut, breakIn, shiftType) {
  let workMs;
  if (shiftType === 'single_session') {
    if (!timeIn || !timeOut) return 0;
    workMs = new Date(timeOut) - new Date(timeIn);
  } else if (shiftType === 'am_only') {
    if (!timeIn || !breakOut) return 0;
    workMs = new Date(breakOut) - new Date(timeIn);
  } else if (!timeOut) {
    return 0;
  } else if (shiftType === 'pm_only' && !timeIn && breakIn) {
    workMs = new Date(timeOut) - new Date(breakIn);
  } else if (!timeIn) {
    return 0;
  } else {
    workMs = new Date(timeOut) - new Date(timeIn);
    if (breakOut && breakIn) {
      const breakMs = new Date(breakIn) - new Date(breakOut);
      if (breakMs > 0) workMs -= breakMs;
    }
  }
  const hours = workMs / (1000 * 60 * 60);
  return Math.max(0, Math.round(hours * 100) / 100);
}

function computeTotalHoursFromRecord(record, shiftInfo = null) {
  const timeIn = record.time_in ?? record.timeIn ?? null;
  const breakOut = record.break_out ?? record.breakOut ?? null;
  const breakIn = record.break_in ?? record.breakIn ?? null;
  const timeOut = record.time_out ?? record.timeOut ?? null;
  const shiftType = getShiftType(shiftInfo);
  if (shiftType) return computeTotalHours(timeIn, timeOut, breakOut, breakIn, shiftType);

  if (timeIn && breakOut && breakIn && timeOut) {
    return computeTotalHours(timeIn, timeOut, breakOut, breakIn, 'full_day');
  }
  if (timeIn && timeOut && !breakOut && !breakIn) {
    return computeTotalHours(timeIn, timeOut, breakOut, breakIn, 'single_session');
  }
  if (timeIn && breakOut && !breakIn && !timeOut) {
    return computeTotalHours(timeIn, timeOut, breakOut, breakIn, 'am_only');
  }
  if (!timeIn && breakIn && timeOut) {
    return computeTotalHours(timeIn, timeOut, breakOut, breakIn, 'pm_only');
  }
  if (timeIn && timeOut) {
    return computeTotalHours(timeIn, timeOut, breakOut, breakIn, 'full_day');
  }
  return 0;
}

function interpretPunchesForShift(punches, shiftInfo = null, timeZone) {
  const shiftType = getShiftType(shiftInfo) ?? 'full_day';
  const n = punches.length;
  if (n === 0) return null;

  let timeIn = null;
  let breakOut = null;
  let breakIn = null;
  let timeOut = null;
  let status;

  if (shiftType === 'single_session') {
    timeIn = punches[0];
    if (n >= 2) timeOut = punches[n - 1];
    status = n >= 2 ? 'present' : 'incomplete';
  } else if (shiftType === 'pm_only') {
    if (n >= 1) breakIn = punches[0];
    if (n >= 2) timeOut = punches[1];
    status = n >= 2 ? 'present' : 'incomplete';
  } else if (shiftType === 'am_only') {
    if (n >= 1) timeIn = punches[0];
    if (n >= 2) breakOut = punches[1];
    status = n >= 2 ? 'present' : 'incomplete';
  } else {
    const firstPunchMins = minutesFromMidnightInTimeZone(punches[0], timeZone);
    const pmStartThreshold =
      shiftInfo && Number.isFinite(shiftInfo.breakEndMinutes)
        ? shiftInfo.breakEndMinutes
        : NOON_MINUTES;
    const isAfternoonFirstPunch =
      firstPunchMins != null && firstPunchMins >= pmStartThreshold;

    if (isAfternoonFirstPunch) {
      breakIn = punches[0];
      if (n >= 2) timeOut = punches[n - 1];
      status = n >= 2 ? 'present' : 'incomplete';
      return {
        timeIn,
        breakOut,
        breakIn,
        timeOut,
        status,
        totalHours: computeTotalHours(timeIn, timeOut, breakOut, breakIn, 'pm_only'),
        punchCount: n,
        shiftType: 'pm_only',
      };
    }

    if (n === 1) {
      timeIn = punches[0];
      status = 'incomplete';
    } else if (n === 2) {
      timeIn = punches[0];
      breakOut = punches[1];
      status = 'incomplete';
    } else if (n === 3) {
      timeIn = punches[0];
      breakOut = punches[1];
      breakIn = punches[2];
      status = 'incomplete';
    } else {
      timeIn = punches[0];
      breakOut = punches[1];
      breakIn = punches[2];
      timeOut = punches[n - 1];
      status = 'present';
    }
  }

  return {
    timeIn,
    breakOut,
    breakIn,
    timeOut,
    status,
    totalHours: computeTotalHours(timeIn, timeOut, breakOut, breakIn, shiftType),
    punchCount: n,
    shiftType,
  };
}

module.exports = {
  NOON_MINUTES,
  ONE_PM_MINUTES,
  VALID_PUNCH_MODES,
  normalizePunchMode,
  ensureShiftPunchModeColumn,
  getShiftType,
  getExpectedWorkMinutes,
  getShiftExpectedLogs,
  getExpectedLogsForDay,
  minutesFromMidnightInTimeZone,
  computeTotalHours,
  computeTotalHoursFromRecord,
  interpretPunchesForShift,
};
