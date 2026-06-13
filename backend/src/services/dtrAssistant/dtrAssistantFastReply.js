const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';

function lower(value) {
  return String(value || '').toLowerCase();
}

function fmtDate(value) {
  if (!value) return '';
  const s = String(value);
  return s.length >= 10 ? s.slice(0, 10) : s;
}

function fmtTime(value) {
  if (!value) return 'none';
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return 'none';
  return new Intl.DateTimeFormat('en-US', {
    timeZone: HRMS_TIMEZONE,
    hour: 'numeric',
    minute: '2-digit',
  }).format(dt);
}

function fmtDays(value) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? n.toFixed(2) : '0.00';
}

function statusLabel(value) {
  return String(value || 'unknown').replace(/_/g, ' ');
}

function isTagalogOrBisaya(message) {
  const text = lower(message);
  return /\b(ano|ba|ko|akong|ngano|unsa|karon|ngayon|kumusta|pila|naa|wala|na-approve)\b/.test(
    text
  );
}

function todayDtrReply(context, localized) {
  const record = context.dtr_records?.[0];
  const range = context.date_range;
  if (!record) {
    return localized
      ? `Wala akong nakitang DTR record para sa ${range?.label || 'today'} (${range?.startDate}).`
      : `I found no DTR record for ${range?.label || 'today'} (${range?.startDate}).`;
  }

  const parts = [
    `Status: ${statusLabel(record.status)}`,
    `AM in: ${fmtTime(record.time_in)}`,
    `AM out: ${fmtTime(record.break_out)}`,
    `PM in: ${fmtTime(record.break_in)}`,
    `PM out: ${fmtTime(record.time_out)}`,
    `Late: ${record.late_minutes || 0} min`,
    `Undertime: ${record.undertime_minutes || 0} min`,
  ];
  if (record.pm_status) parts.push(`PM status: ${statusLabel(record.pm_status)}`);
  if (record.holiday_name) parts.push(`Holiday: ${record.holiday_name}`);
  if (record.leave_type) parts.push(`Leave: ${record.leave_type}`);
  if (record.remarks) parts.push(`Remarks: ${record.remarks}`);

  return localized
    ? `Ito ang DTR record mo for ${fmtDate(record.attendance_date)}. ${parts.join(
        '. '
      )}.`
    : `Here is your DTR record for ${fmtDate(record.attendance_date)}. ${parts.join(
        '. '
      )}.`;
}

function missingLogsReply(context, localized) {
  const records = context.dtr_records || [];
  if (records.length === 0) {
    return localized
      ? `Wala akong nakitang DTR records sa ${context.date_range?.label || 'selected period'}, kaya hindi ko ma-confirm kung may missing logs.`
      : `I found no DTR records for ${context.date_range?.label || 'the selected period'}, so I cannot confirm missing logs.`;
  }

  const incomplete = records.filter((r) => {
    return (
      r.status === 'incomplete' ||
      (!r.time_in && !r.leave_type && !r.holiday_name) ||
      (!r.time_out && r.status !== 'on_leave' && r.status !== 'holiday')
    );
  });

  if (incomplete.length === 0) {
    return localized
      ? `Wala akong nakitang missing or incomplete DTR logs sa ${context.date_range?.label || 'selected period'}.`
      : `I found no missing or incomplete DTR logs for ${context.date_range?.label || 'the selected period'}.`;
  }

  const dates = incomplete.map((r) => fmtDate(r.attendance_date)).join(', ');
  return localized
    ? `May ${incomplete.length} DTR record(s) na mukhang incomplete: ${dates}.`
    : `I found ${incomplete.length} DTR record(s) that look incomplete: ${dates}.`;
}

function leaveBalanceReply(context, localized) {
  const balances = context.leave_balances || [];
  if (balances.length === 0) {
    return localized
      ? 'Wala akong nakitang leave balance records para sa account mo.'
      : 'I found no leave balance records for your account.';
  }

  const lines = balances.map((b) => {
    return `${b.leave_type}: available ${fmtDays(b.available_days)}, remaining ${fmtDays(
      b.remaining_days
    )}, pending ${fmtDays(b.pending_days)}`;
  });

  return localized
    ? `Ito ang leave balance mo: ${lines.join('; ')}.`
    : `Here are your leave balances: ${lines.join('; ')}.`;
}

function latestLeaveReply(context, localized) {
  const request = context.recent_leave_requests?.[0];
  if (!request) {
    return localized
      ? 'Wala akong nakitang leave request records para sa account mo.'
      : 'I found no leave request records for your account.';
  }

  const details = `${request.leave_type || 'Leave'} from ${fmtDate(
    request.start_date
  )} to ${fmtDate(request.end_date)} is ${statusLabel(request.status)}`;
  const remarks = request.reviewer_remarks
    ? ` Reviewer remarks: ${request.reviewer_remarks}.`
    : '';

  return localized
    ? `${details}.${remarks}`
    : `Your latest leave request: ${details}.${remarks}`;
}

function locatorReply(context, localized) {
  const slip = context.recent_locator_slips?.[0];
  if (!slip) {
    return localized
      ? 'Wala akong nakitang locator slip records para sa account mo.'
      : 'I found no locator slip records for your account.';
  }

  const details = `${slip.request_type_label || slip.request_type || 'Locator'} for ${fmtDate(
    slip.slip_date
  )} is ${statusLabel(slip.status)}`;
  const remarks = slip.hr_remarks || slip.dept_head_remarks;

  return localized
    ? `${details}.${remarks ? ` Remarks: ${remarks}.` : ''}`
    : `Your latest locator request: ${details}.${remarks ? ` Remarks: ${remarks}.` : ''}`;
}

function buildFastEmployeeAssistantReply(message, context, intent) {
  const text = lower(message);
  const localized = isTagalogOrBisaya(message);

  if (intent === 'today_dtr') {
    return todayDtrReply(context, localized);
  }
  if (intent === 'missing_logs') {
    return missingLogsReply(context, localized);
  }
  if (intent === 'leave_balance') {
    return leaveBalanceReply(context, localized);
  }
  if (intent === 'latest_leave_request') {
    return latestLeaveReply(context, localized);
  }
  if (intent === 'latest_locator_request') {
    return locatorReply(context, localized);
  }

  if (/\b(dtr|attendance|late|time[\s-]?in|time[\s-]?out)\b/.test(text)) {
    if (/\b(today|karon|ngayon|status|late)\b/.test(text)) {
      return todayDtrReply(context, localized);
    }
  }

  return null;
}

module.exports = { buildFastEmployeeAssistantReply };
