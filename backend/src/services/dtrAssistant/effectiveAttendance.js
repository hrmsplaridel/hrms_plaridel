const {
  evaluateLocatorCoverage, normalizeLocatorCoverage, locatorSlotKey,
} = require('../locatorCoverage');

const PUNCH_FIELDS = { am_in: 'time_in', am_out: 'break_out', pm_in: 'break_in', pm_out: 'time_out' };

function localClock(context = {}) {
  const now = context.as_of_time ? new Date(context.as_of_time) : new Date();
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone: process.env.HRMS_TIMEZONE || 'Asia/Manila',
    year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(now);
  const get = key => parts.find(p => p.type === key)?.value;
  return {date: context.as_of_date || `${get('year')}-${get('month')}-${get('day')}`, minutes: Number(get('hour')) * 60 + Number(get('minute'))};
}
function timeMinutes(time) { const m = String(time || '').match(/^(\d{1,2}):(\d{2})/); return m ? Number(m[1])*60+Number(m[2]) : null; }
function dueSlots(context, day, slots) {
  if (!day) return slots;
  const clock = localClock(context), date = String(day.attendance_date).slice(0,10);
  if (date > clock.date) return [];
  const start = timeMinutes(day.start_time), end = timeMinutes(day.end_time);
  if (start == null || end == null) return date < clock.date ? slots : []; // Unknown due time is not proof of an overdue punch today.
  // An overnight assignment belongs to its start date; its final punches are due the next date.
  const overnight = end <= start;
  const daysElapsed = Math.round((Date.parse(clock.date) - Date.parse(date)) / 86400000);
  const elapsed = clock.minutes + daysElapsed * 1440;
  const breakDeadline = value => { const minutes=timeMinutes(value); return minutes == null ? null : minutes + (overnight && minutes < start ? 1440 : 0); };
  const deadlines = {am_in:start + Number(day.grace_period_minutes || 0),
    am_out:breakDeadline(day.break_start), pm_in:breakDeadline(day.break_end), pm_out:overnight ? end+1440 : end};
  return slots.filter(slot => {const key=locatorSlotKey(slot); const deadline=deadlines[key] ?? (overnight ? end+1440 : end); return elapsed > deadline;});
}
function dayIsNotDue(context, day) {
  const slots = coverageForDate(context, day.attendance_date).expectedSlots;
  return slots.length > 0 && dueSlots(context, day, slots).length === 0;
}

function hrmsToday() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: process.env.HRMS_TIMEZONE || 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(new Date());
  return ['year', 'month', 'day'].map((key) => parts.find((part) => part.type === key).value).join('-');
}

function coverageForDate(context, date) {
  const day = (context.dtr_calendar_days || []).find((item) => item.attendance_date === date);
  const slips = (context.recent_locator_slips || []).filter((slip) =>
    String(slip.slip_date).slice(0, 10) === date && String(slip.status).toLowerCase() === 'approved' && !slip.revoked_at);
  const evaluation = evaluateLocatorCoverage({ locators: slips, shiftInfo: day,
    holidayInfo: day?.holiday_coverage && day.holiday_coverage !== 'none' ? { coverage: day.holiday_coverage } : null,
    date });
  const relevant = slips.filter((slip) => evaluation.expectedSlots.some((slot) => normalizeLocatorCoverage(slip)[slot]));
  const label = [...new Set(relevant.map((slip) => slip.dtr_slot_label || slip.dtr_print_label || 'On field'))].join(' / ');
  return { ...evaluation, day, slips: relevant, label };
}

// Preserve real punches and measured hours. Coverage labels are never invented timestamps.
function effectiveDtrRecords(context) {
  const records = new Map((context.dtr_records || []).map((row) => [String(row.attendance_date).slice(0, 10), { ...row }]));
  const today = context.as_of_date || hrmsToday();
  const dates = new Set([...records.keys(), ...(context.recent_locator_slips || []).map((row) => String(row.slip_date).slice(0, 10))]);
  for (const date of dates) {
    if (context.date_range?.startDate && date < context.date_range.startDate ||
        context.date_range?.endDate && date > context.date_range.endDate) continue;
    if (date > today) continue;
    const coverage = coverageForDate(context, date);
    if (!coverage.slips.length || !coverage.expectedSlots.length) continue;
    const row = records.get(date);
    if (row && (row.leave_type || ['on_leave', 'holiday', 'rest_day'].includes(row.status))) continue;
    const base = row || { attendance_date: date, total_hours: null, source: 'approved_locator' };
    const full = coverage.expectedSlots.every((slot) => base[PUNCH_FIELDS[slot]] || coverage.coverage[slot]);
    const noPunches = !Object.values(PUNCH_FIELDS).some((field) => base[field]);
    records.set(date, { ...base, status: full ? 'present' : 'incomplete',
      attendance_label: coverage.label, locator_coverage: coverage.coverage,
      locator_only: noPunches, locator_fully_covered: full,
      ...(noPunches ? { late_minutes: 0, undertime_minutes: 0, overtime_minutes: 0 } : {}),
      remarks: [base.remarks, `Approved locator: ${coverage.label}`].filter(Boolean).join('; '),
    });
  }
  for (const [date, row] of records) {
    const coverage=coverageForDate(context,date), day=coverage.day;
    if (!day || row.leave_type || ['on_leave','holiday','rest_day'].includes(row.status) || row.locator_fully_covered) continue;
    if (coverage.expectedSlots.length && coverage.expectedSlots.every(slot=>row[PUNCH_FIELDS[slot]]||coverage.coverage[slot])) continue;
    const due=dueSlots(context,day,coverage.expectedSlots);
    if (!coverage.expectedSlots.length || due.length===coverage.expectedSlots.length) continue;
    const overdueMissing=due.some(slot=>!row[PUNCH_FIELDS[slot]]&&!coverage.coverage[slot]);
    records.set(date,{...row,status:overdueMissing?'incomplete':due.length?'in_progress':'not_due',
      undertime_minutes:0, overtime_minutes:0});
  }
  return [...records.values()].sort((a, b) => String(a.attendance_date).localeCompare(String(b.attendance_date)));
}

function effectiveExportStatus(context, day, record) {
  if (record?.attendance_label) return `${record.attendance_label}${record.locator_fully_covered ? '' : ' (partial coverage)'}`;
  if (record?.leave_type || record?.status === 'on_leave') return record.status || 'on_leave';
  if (day.holiday_coverage === 'whole_day') return 'holiday';
  if (day.shift_id) {
    if (!coverageForDate(context, day.attendance_date).expectedSlots.length) return 'rest_day';
    if (!Object.values(PUNCH_FIELDS).some(field => record?.[field]) && dayIsNotDue(context, day)) return 'not_due';
  }
  if (record?.status) return record.status;
  if (!day.shift_id) return 'no_schedule';
  return 'no_record';
}

function coveredMissingSlot(context, date, slot) {
  const key = locatorSlotKey(slot);
  return Boolean(key && coverageForDate(context, String(date).slice(0, 10)).coverage[key]);
}

module.exports = { coverageForDate, effectiveDtrRecords, effectiveExportStatus, coveredMissingSlot, hrmsToday, PUNCH_FIELDS, localClock, dueSlots, dayIsNotDue };
