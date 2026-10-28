const {
  evaluateLocatorCoverage, normalizeLocatorCoverage, locatorSlotKey,
} = require('../locatorCoverage');

const PUNCH_FIELDS = { am_in: 'time_in', am_out: 'break_out', pm_in: 'break_in', pm_out: 'time_out' };

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
  return [...records.values()].sort((a, b) => String(a.attendance_date).localeCompare(String(b.attendance_date)));
}

function effectiveExportStatus(context, day, record) {
  if (record?.attendance_label) return `${record.attendance_label}${record.locator_fully_covered ? '' : ' (partial coverage)'}`;
  if (day.attendance_date > (context.as_of_date || hrmsToday()) &&
      !Object.values(PUNCH_FIELDS).some(field => record?.[field]) && !record?.leave_type) return 'not_due';
  if (record?.status) return record.status;
  if (day.holiday_coverage === 'whole_day') return 'holiday';
  if (!day.shift_id) return 'no_schedule';
  const coverage = coverageForDate(context, day.attendance_date);
  if (!coverage.expectedSlots.length) return 'rest_day';
  if (day.attendance_date > (context.as_of_date || hrmsToday())) return 'not_due';
  return 'no_record';
}

function coveredMissingSlot(context, date, slot) {
  const key = locatorSlotKey(slot);
  return Boolean(key && coverageForDate(context, String(date).slice(0, 10)).coverage[key]);
}

module.exports = { coverageForDate, effectiveDtrRecords, effectiveExportStatus, coveredMissingSlot, hrmsToday, PUNCH_FIELDS };
