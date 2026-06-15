const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';
const {
  GUIDELINE_SECTIONS,
  getFormGuidanceForType,
  getLeaveGuidanceForType,
  getGuidelineSectionsForMessage,
  summarizeLeaveGuidance,
} = require('./leaveFilingGuidelines');

function lower(value) {
  return String(value || '').toLowerCase();
}

function fmtDate(value) {
  if (!value) return '';
  const s = String(value);
  return s.length >= 10 ? s.slice(0, 10) : s;
}

function fmtFriendlyDate(value) {
  const iso = fmtDate(value);
  const match = iso.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return iso;
  const dt = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  return new Intl.DateTimeFormat('en-US', {
    timeZone: 'UTC',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  }).format(dt);
}

function fmtFriendlyDateRange(start, end) {
  const startIso = fmtDate(start);
  const endIso = fmtDate(end);
  if (!startIso && !endIso) return '';
  if (!endIso || startIso === endIso) return `on ${fmtFriendlyDate(startIso)}`;
  return `from ${fmtFriendlyDate(startIso)} to ${fmtFriendlyDate(endIso)}`;
}

function fmtLocalizedDateRange(start, end, language) {
  const phrase = fmtFriendlyDateRange(start, end);
  if (!phrase) return '';
  if (language === 'bisaya') {
    return phrase.replace(/^on /, 'sa ').replace(/^from /, 'gikan ').replace(/ to /, ' hangtod ');
  }
  if (language === 'tagalog') {
    return phrase.replace(/^on /, 'noong ').replace(/^from /, 'mula ').replace(/ to /, ' hanggang ');
  }
  return phrase;
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
  if (!Number.isFinite(n)) return '0';
  if (Number.isInteger(n)) return String(n);
  return String(Number(n.toFixed(2)));
}

function fmtDayCount(value) {
  const text = fmtDays(value);
  return `${text} ${Number(value) === 1 ? 'day' : 'days'}`;
}

function plural(count, singular, pluralValue = `${singular}s`) {
  return Number(count) === 1 ? singular : pluralValue;
}

function localizedPeriodLabel(label, language) {
  const value = String(label || 'selected period').toLowerCase();
  if (language === 'bisaya') {
    if (value === 'today') return 'karon';
    if (value === 'this week') return 'karong semanaha';
    if (value === 'this month') return 'aning bulana';
    if (value === 'last month') return 'miaging bulan';
    if (value === 'next month') return 'sunod bulan';
  }
  if (language === 'tagalog') {
    if (value === 'today') return 'ngayon';
    if (value === 'this week') return 'ngayong linggo';
    if (value === 'this month') return 'ngayong buwan';
    if (value === 'last month') return 'nakaraang buwan';
    if (value === 'next month') return 'susunod na buwan';
  }
  return label || 'selected period';
}

function asNumber(value) {
  if (value == null || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function statusLabel(value) {
  return String(value || 'unknown').replace(/_/g, ' ');
}

function trimTrailingSentencePunctuation(value) {
  return String(value || '').replace(/[.\s]+$/g, '').trim();
}

function isTagalogOrBisaya(message) {
  const text = lower(message);
  return /\b(ano|ba|ko|akong|ngano|unsa|unsay|karon|ngayon|kumusta|pila|kabuok|naa|wala|pasok|na-approve|adtong|adtung|atong|niadtong|niadtung|ana|adto|ato)\b/.test(
    text
  );
}

function languageOf(message) {
  const text = lower(message);
  if (/\b(ngano|unsa|unsay|unsa'y|karon|pila|kabuok|naa|akong|nako|nabilin|gamay|kuwang|imong|nimo|gikan|mahimong|adlaw|kinahanglan|ug|kay|aning|bulana|adtong|adtung|atong|niadtong|niadtung|ana|adto|ato|duty)\b/.test(text)) {
    return 'bisaya';
  }
  if (/\b(ano|ngayon|ako|ko|ba|may|wala|ilan|bakit|maliit|natira|kailangan|pasok|noong|nung)\b/.test(text)) {
    return 'tagalog';
  }
  return 'english';
}

function responseLabels(language) {
  if (language === 'bisaya') {
    return {
      details: 'Detalye',
      nextStep: 'Sunod buhaton',
      more: 'Naa pa',
    };
  }
  if (language === 'tagalog') {
    return {
      details: 'Detalye',
      nextStep: 'Susunod',
      more: 'May',
    };
  }
  return {
    details: 'Details',
    nextStep: 'Next step',
    more: 'Plus',
  };
}

function bulletLines(items, limit = 7) {
  const clean = (items || []).filter(Boolean);
  const visible = clean.slice(0, limit);
  const rest = clean.length - visible.length;
  const lines = visible.map((item) => `- ${item}`);
  if (rest > 0) lines.push(`- Plus ${rest} more.`);
  return lines;
}

function structuredReply(language, { title, summary, details = [], nextStep, limit = 7 }) {
  const labels = responseLabels(language);
  const parts = [title, '', summary].filter((part) => part != null && part !== '');
  const lines = bulletLines(details, limit);
  if (lines.length > 0) {
    parts.push('', `${labels.details}:`, ...lines);
  }
  if (nextStep) {
    parts.push('', `${labels.nextStep}: ${nextStep}`);
  }
  return parts.join('\n');
}

function requestedLeaveType(message) {
  const text = lower(message).replace(/[\s_-]+/g, '');
  if (/\b(sick|sl|sickleave)\b/.test(lower(message)) || text.includes('sickleave')) {
    return 'sick';
  }
  if (
    /\b(vacation|vl|vacationleave)\b/.test(lower(message)) ||
    text.includes('vacationleave')
  ) {
    return 'vacation';
  }
  return null;
}

function normalizedText(value) {
  return lower(value).replace(/[^a-z0-9]+/g, '');
}

function leaveTypeSearchText(typeRecord) {
  return `${typeRecord.display_name || ''} ${typeRecord.name || ''} ${typeRecord.description || ''}`;
}

function inferLeaveTypeFromRecords(message, typeRecords = []) {
  const normalizedMessage = normalizedText(message);
  if (!normalizedMessage || typeRecords.length === 0) return null;

  let best = null;
  let bestScore = 0;
  for (const type of typeRecords) {
    const label = leaveTypeSearchText(type);
    const normalizedLabel = normalizedText(label);
    if (!normalizedLabel) continue;

    const words = lower(label)
      .split(/[^a-z0-9]+/)
      .filter((word) => word.length >= 3 && word !== 'leave');
    const uniqueWords = [...new Set(words)];
    const score = uniqueWords.reduce((total, word) => {
      return total + (normalizedMessage.includes(word) ? 1 : 0);
    }, normalizedMessage.includes(normalizedLabel) ? 3 : 0);

    if (score > bestScore) {
      best = type;
      bestScore = score;
    }
  }

  return bestScore > 0 ? best : null;
}

function mentionedLeaveTypeRecords(context, message) {
  const normalizedMessage = normalizedText(message);
  const scored = (context.leave_types || [])
    .map((type) => {
      const label = leaveTypeSearchText(type);
      const normalizedLabel = normalizedText(label);
      const words = lower(label)
        .split(/[^a-z0-9]+/)
        .filter((word) => word.length >= 3 && word !== 'leave');
      const uniqueWords = [...new Set(words)];
      const score = uniqueWords.reduce((total, word) => {
        return total + (normalizedMessage.includes(word) ? 1 : 0);
      }, normalizedLabel && normalizedMessage.includes(normalizedLabel) ? 3 : 0);
      return { type, score };
    })
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score);
  return scored.map((item) => item.type);
}

function requestedLeaveTypeRecord(message, context) {
  const type = requestedLeaveType(message);
  if (type) {
    return (context.leave_types || []).find((record) => leaveTypeRecordMatches(record, type)) || null;
  }
  return inferLeaveTypeFromRecords(message, context.leave_types || []);
}

function normalizeSex(value) {
  const text = lower(value);
  if (text === 'm' || text === 'male') return 'male';
  if (text === 'f' || text === 'female') return 'female';
  return text || null;
}

function isWhyBalanceQuestion(message) {
  const text = lower(message);
  return /\b(why|ngano|bakit|gamay|small|low|maliit|nabilin|natira|remaining)\b/.test(
    text
  );
}

function hasDateRangeHint(message) {
  const text = lower(message);
  return /\b(today|tomorrow|yesterday|ugma|kagahapon|gahapon|karon|karong adlawa|week|semana|semanaha|month|bulan|bulana|buwan|buwana|aning bulana|last month|this month|next month|last week|this week|next week|next day|following day|previous day|day before|same day|same date|sunod adlaw|sunod|miaging|niaging|adtong|adtung|atong|niadtong|niadtung|noong|nung|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b|\b(?:sa|pag|noong|nung|adtong|adtung|atong|niadtong|niadtung)\s+\d{1,2}\b/.test(
    text
  );
}

function requestOverlapsRange(request, range) {
  if (!range?.startDate || !range?.endDate) return true;
  if (!request?.start_date || !request?.end_date) return true;
  return request.start_date <= range.endDate && request.end_date >= range.startDate;
}

function daysBetweenIso(startDate, endDate) {
  if (!startDate || !endDate) return null;
  const start = new Date(`${startDate}T00:00:00Z`);
  const end = new Date(`${endDate}T00:00:00Z`);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return null;
  return Math.round((end.getTime() - start.getTime()) / 86400000);
}

function rangeDayCount(range) {
  const diff = daysBetweenIso(range?.startDate, range?.endDate);
  return diff == null ? null : diff + 1;
}

function pendingStatus(value) {
  return /^(pending|pending_department_head|pending_hr)$/i.test(String(value || ''));
}

function approvedStatus(value) {
  return /^approved/i.test(String(value || ''));
}

function rejectedStatus(value) {
  return /^(rejected|rejected_department_head|rejected_by_department_head|rejected_hr|rejected_by_hr|declined|denied)$/i.test(
    String(value || '')
  );
}

function returnedStatus(value) {
  return /^returned$/i.test(String(value || ''));
}

function activeLeaveStatus(value) {
  const status = String(value || '').toLowerCase();
  return (
    pendingStatus(status) ||
    approvedStatus(status) ||
    status === 'returned' ||
    status === 'draft'
  );
}

function parseRequestedDays(message) {
  const text = lower(message);
  const match = text.match(/\b(\d+(?:\.\d+)?)\s*(?:day|days|adlaw|ka\s*adlaw)?\b/);
  return match ? asNumber(match[1]) : null;
}

function requestedDaysOrRangeDays(message, context) {
  return parseRequestedDays(message) || rangeDayCount(context.date_range);
}

function leaveTypeMatches(balance, type) {
  if (!type) return true;
  const name = lower(balance.leave_type).replace(/[\s_-]+/g, '');
  if (type === 'sick') return name.includes('sick') || name === 'sl';
  if (type === 'vacation') return name.includes('vacation') || name === 'vl';
  return true;
}

function leaveBalanceMatchesRecord(balance, typeRecord) {
  if (!typeRecord) return true;
  const balanceName = normalizedText(balance.leave_type);
  const typeName = normalizedText(`${typeRecord.display_name || ''} ${typeRecord.name || ''}`);
  if (!balanceName || !typeName) return false;
  return typeName.includes(balanceName) || balanceName.includes(typeName);
}

function leaveTypeRecordMatches(typeRecord, type) {
  if (!type) return true;
  const name = lower(`${typeRecord.display_name || ''} ${typeRecord.name || ''}`).replace(
    /[\s_-]+/g,
    ''
  );
  if (type === 'sick') return name.includes('sick') || name === 'sl';
  if (type === 'vacation') return name.includes('vacation') || name === 'vl';
  return true;
}

function labelLeaveType(value) {
  const text = String(value || 'Leave').replace(/([a-z])([A-Z])/g, '$1 $2');
  return text.replace(/\bleave\b/i, 'leave');
}

function fmtLeaveRequest(request) {
  const days = request.days != null ? ` (${fmtDayCount(request.days)})` : '';
  return `${labelLeaveType(request.leave_type)} ${fmtFriendlyDateRange(
    request.start_date,
    request.end_date
  )} - ${workflowStatusText(request.status)}${days}`;
}

function leaveRequestMatchesRecord(request, typeRecord) {
  if (!typeRecord) return true;
  const requestName = normalizedText(request.leave_type);
  const typeName = normalizedText(`${typeRecord.display_name || ''} ${typeRecord.name || ''}`);
  if (!requestName || !typeName) return false;
  return typeName.includes(requestName) || requestName.includes(typeName);
}

function requestedStatusMatcher(message) {
  const text = lower(message);
  if (/\b(pending|waiting|awaiting|hold|holding)\b/.test(text)) return pendingStatus;
  if (/\b(approved|approve|na-approve)\b/.test(text)) return approvedStatus;
  if (/\b(rejected|declined|denied|gi reject)\b/.test(text)) return rejectedStatus;
  if (/\b(returned|gibalik|binalik|correction)\b/.test(text)) return returnedStatus;
  return null;
}

function requestMatchesMessageFilters(request, message, context) {
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const matcher = requestedStatusMatcher(message);
  const useRange = hasDateRangeHint(message);
  if (requestedRecord && !leaveRequestMatchesRecord(request, requestedRecord)) return false;
  if (matcher && !matcher(request.status)) return false;
  if (useRange && !requestOverlapsRange(request, context.date_range)) return false;
  return true;
}

function limitedRequests(requests, limit = 5) {
  return requests.slice(0, limit);
}

function balanceFormulaLine(b) {
  return `earned ${fmtDays(b.earned_days)}, used ${fmtDays(b.used_days)}, adjusted ${fmtDays(
    b.adjusted_days
  )}, pending ${fmtDays(b.pending_days)}, remaining ${fmtDays(
    b.remaining_days
  )}, available ${fmtDays(b.available_days)}`;
}

function attachmentRequiredForType(type, days) {
  if (!type) return false;
  const threshold = asNumber(type.requires_attachment_when_over_days);
  if (threshold != null && days != null) return days >= threshold;
  return type.requires_attachment === true;
}

function attachmentRuleText(type, days) {
  const threshold = asNumber(type.requires_attachment_when_over_days);
  if (threshold != null) {
    const requiredNow = days != null && days >= threshold;
    return requiredNow
      ? `attachment required because the request reaches ${fmtDayCount(threshold)}`
      : `attachment required when filing ${fmtDayCount(threshold)} or more`;
  }
  return type.requires_attachment ? 'attachment required' : 'no attachment required';
}

function workflowStatusText(status) {
  const value = String(status || '').toLowerCase();
  if (value === 'pending_department_head') return 'waiting for department head review';
  if (value === 'pending_hr' || value === 'pending') return 'waiting for HR final review';
  if (value === 'approved') return 'approved by HR';
  if (value === 'returned') return 'returned for correction';
  if (value === 'rejected_by_department_head' || value === 'rejected_department_head') {
    return 'rejected by department head';
  }
  if (value === 'rejected_by_hr' || value === 'rejected_hr' || value === 'rejected') {
    return 'rejected by HR';
  }
  if (value === 'draft') return 'still in draft';
  if (value === 'cancelled') return 'cancelled';
  return statusLabel(status);
}

function firstReviewReason(request) {
  const details = request?.details || {};
  return (
    request?.reviewer_remarks ||
    request?.hr_remarks ||
    request?.dept_head_remarks ||
    request?.latest_history?.remarks ||
    details.disapproval_reason ||
    details.disapprovalReason ||
    details.recommendation_remarks ||
    details.recommendationRemarks ||
    null
  );
}

function todayDtrReply(context, localized) {
  const record = context.dtr_records?.[0];
  const range = context.date_range;
  if (!record) {
    const displayDate = range?.startDate ? ` (${fmtFriendlyDate(range.startDate)})` : '';
    return localized
      ? `Wala akong nakitang DTR record para sa ${range?.label || 'today'}${displayDate}.`
      : `I found no DTR record for ${range?.label || 'today'}${displayDate}.`;
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
    ? `Ito ang DTR record mo for ${fmtFriendlyDate(record.attendance_date)}. ${parts.join(
        '. '
      )}.`
    : `Here is your DTR record for ${fmtFriendlyDate(record.attendance_date)}. ${parts.join(
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

  const dates = incomplete.map((r) => fmtFriendlyDate(r.attendance_date)).join(', ');
  return localized
    ? `May ${incomplete.length} DTR ${plural(incomplete.length, 'record')} na mukhang incomplete: ${dates}.`
    : `I found ${incomplete.length} DTR ${plural(incomplete.length, 'record')} that look incomplete: ${dates}.`;
}

function dtrRecords(context) {
  return context.dtr_records || [];
}

function isNonWorkingDtrRecord(record) {
  const status = lower(record?.status);
  return (
    status === 'on_leave' ||
    status === 'holiday' ||
    status === 'rest_day' ||
    !!record?.leave_type ||
    !!record?.holiday_name
  );
}

function missingDtrSlots(record) {
  if (!record) return ['no DTR record'];
  if (isNonWorkingDtrRecord(record)) return [];
  const missing = [];
  if (!record.time_in) missing.push('AM in');
  if (!record.break_out) missing.push('AM out');
  if (!record.break_in) missing.push('PM in');
  if (!record.time_out) missing.push('PM out');
  return missing;
}

function requestedDtrSlot(message) {
  const text = lower(message);
  if (/\b(am\s*in|time[\s-]?in|clock[\s-]?in)\b/.test(text)) return 'AM in';
  if (/\b(am\s*out|break[\s-]?out|morning out)\b/.test(text)) return 'AM out';
  if (/\b(pm\s*in|break[\s-]?in|afternoon in)\b/.test(text)) return 'PM in';
  if (/\b(pm\s*out|time[\s-]?out|clock[\s-]?out)\b/.test(text)) return 'PM out';
  return null;
}

function isIncompleteDtrRecord(record) {
  if (!record) return true;
  if (isNonWorkingDtrRecord(record)) return false;
  const status = lower(record.status);
  return status === 'incomplete' || missingDtrSlots(record).length > 0;
}

function isIncompleteDtrRecordForContext(context, record) {
  if (!record) return true;
  if (isNonWorkingDtrRecord(record)) return false;
  const status = lower(record.status);
  return status === 'incomplete' || missingDtrSlotsForContext(context, record).length > 0;
}

function isAbsentDtrRecord(record) {
  const status = lower(record?.status);
  return status === 'absent' || status === 'no_record' || status === 'missing';
}

function dtrIssueRecords(records, predicate) {
  return records.filter(predicate).sort((a, b) => String(a.attendance_date).localeCompare(String(b.attendance_date)));
}

function todayIsoInHrmsTimezone() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: HRMS_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const year = parts.find((part) => part.type === 'year')?.value;
  const month = parts.find((part) => part.type === 'month')?.value;
  const day = parts.find((part) => part.type === 'day')?.value;
  return `${year}-${month}-${day}`;
}

function noRecordWorkingDays(context) {
  const today = todayIsoInHrmsTimezone();
  return dtrCalendarDays(context).filter((day) => {
    if (day.attendance_date > today) return false;
    if (!isCalendarWorkingDay(day)) return false;
    if (dtrRecordForDate(context, day.attendance_date)) return false;
    if (firstMatchingLeave(context, day.attendance_date)) return false;
    return true;
  });
}

function fmtMinutes(value) {
  const n = Number(value || 0);
  if (!Number.isFinite(n) || n <= 0) return '0 min';
  if (n < 60) return `${n} min`;
  const hours = Math.floor(n / 60);
  const minutes = n % 60;
  return minutes > 0 ? `${hours} hr ${minutes} min` : `${hours} hr`;
}

function fmtHours(value) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? n.toFixed(2) : '0.00';
}

function timeTextToMinutes(value) {
  if (!value) return null;
  const match = String(value).match(/^(\d{1,2}):(\d{2})/);
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

function minutesFromIsoInHrmsTimezone(value) {
  if (!value) return null;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: HRMS_TIMEZONE,
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(dt);
  const hour = Number(parts.find((part) => part.type === 'hour')?.value || 0);
  const minute = Number(parts.find((part) => part.type === 'minute')?.value || 0);
  return hour * 60 + minute;
}

function fmtClockMinutes(value) {
  if (value == null) return 'none';
  const h = Math.floor(value / 60);
  const m = value % 60;
  const hour12 = h % 12 || 12;
  const suffix = h >= 12 ? 'PM' : 'AM';
  return `${hour12}:${String(m).padStart(2, '0')} ${suffix}`;
}

function fmtScheduleTime(value) {
  const minutes = timeTextToMinutes(value);
  return minutes == null ? String(value || '').trim() : fmtClockMinutes(minutes);
}

function fmtScheduleRange(day) {
  const start = fmtScheduleTime(day?.start_time);
  const end = fmtScheduleTime(day?.end_time);
  if (!start && !end) return '';
  if (!end) return start;
  if (!start) return end;
  return `${start}-${end}`;
}

function isoDayOfWeek(dateString) {
  const dt = new Date(`${dateString}T00:00:00Z`);
  const day = dt.getUTCDay();
  return day === 0 ? 7 : day;
}

function dtrCalendarDays(context) {
  return context.dtr_calendar_days || [];
}

function calendarDayForDate(context, date) {
  const key = fmtDate(date);
  return dtrCalendarDays(context).find((day) => day.attendance_date === key) || null;
}

function dtrRecordForDate(context, date) {
  const key = fmtDate(date);
  return dtrRecords(context).find((record) => fmtDate(record.attendance_date) === key) || null;
}

function shiftTypeFromCalendar(day) {
  if (!day?.start_time) return null;
  const explicit = lower(day.punch_mode || 'auto');
  if (explicit && explicit !== 'auto') return explicit;
  const start = timeTextToMinutes(day.start_time);
  const end = timeTextToMinutes(day.end_time);
  const breakEnd = timeTextToMinutes(day.break_end);
  if (start == null) return null;
  if (start >= 12 * 60) return 'pm_only';
  if (breakEnd == null && end != null && end <= 13 * 60) return 'am_only';
  return 'full_day';
}

function isCalendarWorkingDay(day) {
  if (!day?.shift_id || !day.start_time) return false;
  const workingDays = Array.isArray(day.working_days) ? day.working_days : [];
  if (workingDays.length > 0 && !workingDays.includes(isoDayOfWeek(day.attendance_date))) {
    return false;
  }
  return day.holiday_coverage !== 'whole_day';
}

function expectedSlotsForCalendarDay(day) {
  if (!isCalendarWorkingDay(day)) return [];
  const type = shiftTypeFromCalendar(day);
  let slots;
  if (type === 'single_session') slots = ['AM in', 'PM out'];
  else if (type === 'am_only') slots = ['AM in', 'AM out'];
  else if (type === 'pm_only') slots = ['PM in', 'PM out'];
  else slots = ['AM in', 'AM out', 'PM in', 'PM out'];

  if (day.holiday_coverage === 'am_only') {
    slots = slots.filter((slot) => slot === 'PM in' || slot === 'PM out');
  }
  if (day.holiday_coverage === 'pm_only') {
    slots = slots.filter((slot) => slot === 'AM in' || slot === 'AM out');
  }
  return slots;
}

function slotValue(record, slot) {
  if (slot === 'AM in') return record?.time_in;
  if (slot === 'AM out') return record?.break_out;
  if (slot === 'PM in') return record?.break_in;
  if (slot === 'PM out') return record?.time_out;
  return null;
}

function missingDtrSlotsForContext(context, recordOrDate) {
  const date = fmtDate(recordOrDate?.attendance_date || recordOrDate);
  const record =
    typeof recordOrDate === 'object' && recordOrDate?.attendance_date
      ? recordOrDate
      : dtrRecordForDate(context, date);
  const day = calendarDayForDate(context, date);
  if (!record) {
    if (day && isCalendarWorkingDay(day)) return ['no DTR record'];
    return [];
  }
  if (isNonWorkingDtrRecord(record)) return [];
  const expected = day ? expectedSlotsForCalendarDay(day) : ['AM in', 'AM out', 'PM in', 'PM out'];
  return expected.filter((slot) => !slotValue(record, slot));
}

function dtrRecordLine(record, context = null) {
  const missing = context ? missingDtrSlotsForContext(context, record) : missingDtrSlots(record);
  const day = context ? calendarDayForDate(context, record.attendance_date) : null;
  const missingText = missing.length > 0 ? `, missing ${missing.join(', ')}` : '';
  const leave = record.leave_type ? `, leave ${labelLeaveType(record.leave_type)}` : '';
  const holiday = record.holiday_name ? `, holiday ${record.holiday_name}` : '';
  const schedule = day?.shift_name
    ? `, shift ${day.shift_name} ${day.start_time || ''}-${day.end_time || ''}, grace ${day.grace_period_minutes || 0} min`
    : '';
  return `${fmtFriendlyDate(record.attendance_date)}: ${statusLabel(record.status)}, AM in ${fmtTime(
    record.time_in
  )}, AM out ${fmtTime(record.break_out)}, PM in ${fmtTime(record.break_in)}, PM out ${fmtTime(
    record.time_out
  )}, hours ${fmtHours(record.total_hours)}, late ${record.late_minutes || 0} min, undertime ${
    record.undertime_minutes || 0
  } min, overtime ${record.overtime_minutes || 0} min${missingText}${leave}${holiday}${schedule}`;
}

function dtrDailyRecordReply(context, message) {
  const language = languageOf(message);
  const record = dtrRecords(context)[0];
  const label = context.date_range?.label || 'selected date';
  if (!record) {
    const day = calendarDayForDate(context, context.date_range?.startDate);
    if (day?.holiday_name) {
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Wala koy DTR punch record sa ${fmtFriendlyDate(day.attendance_date)}, pero holiday ni: ${day.holiday_name}.`
            : language === 'tagalog'
              ? `Wala akong DTR punch record noong ${fmtFriendlyDate(day.attendance_date)}, pero holiday ito: ${day.holiday_name}.`
              : `${fmtFriendlyDate(day.attendance_date)} has no DTR record, but it is marked as ${day.holiday_name}.`,
        details: [
          `Holiday coverage: ${day.holiday_coverage || 'whole_day'}`,
          day.shift_name ? `Schedule: ${day.shift_name}` : null,
        ],
        nextStep:
          language === 'bisaya'
            ? 'No action needed kung sakto ang holiday setup.'
            : language === 'tagalog'
              ? 'No action needed kung tama ang holiday setup.'
              : 'No action is needed unless HR expected you to report for work that day.',
      });
    }
    if (day && !isCalendarWorkingDay(day)) {
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Wala koy DTR record sa ${fmtFriendlyDate(day.attendance_date)} kay dili siya required-log day base sa schedule context.`
            : language === 'tagalog'
              ? `Wala akong DTR record noong ${fmtFriendlyDate(day.attendance_date)} dahil hindi siya required-log day base sa schedule context.`
              : `${fmtFriendlyDate(day.attendance_date)} has no DTR record because it is not a required-log day in the schedule context.`,
        details: [
          `Schedule: ${day.shift_name || 'rest day/no required logs'}`,
          'Expected logs: none',
        ],
        nextStep:
          language === 'bisaya'
            ? 'No action needed kung sakto ang imong schedule ani nga date.'
            : language === 'tagalog'
              ? 'No action needed kung tama ang schedule mo sa date na ito.'
              : 'No action is needed unless your schedule for that date is wrong.',
      });
    }
    if (day && isCalendarWorkingDay(day)) {
      const expected = expectedSlotsForCalendarDay(day);
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Status: Absent/no DTR record. Scheduled workday ni pero wala koy nakitang DTR punches.`
            : language === 'tagalog'
              ? `Status: Absent/no DTR record. Scheduled workday ito pero wala akong nakitang DTR punches.`
              : `No DTR record was found for ${fmtFriendlyDate(day.attendance_date)}, but it is a scheduled workday.`,
        details: [
          `Shift: ${day.shift_name || 'shift'} ${fmtScheduleRange(day)}`.trim(),
          `Grace period: ${fmtMinutes(day.grace_period_minutes || 0)}`,
          `Expected logs: ${expected.join(', ')}`,
        ],
        nextStep:
          language === 'bisaya'
            ? 'Kung ni-duty ka ani nga adlaw, i-check kung kinahanglan ba ug DTR correction, locator slip, or leave coverage.'
            : language === 'tagalog'
              ? 'Kung pumasok ka sa araw na ito, i-check kung kailangan ng DTR correction, locator slip, o leave coverage.'
              : 'If you worked that day, check whether you need a DTR correction, locator slip, or leave coverage.',
      });
    }
    return structuredReply(language, {
      title: 'DTR check',
      summary: `I found no DTR record for ${label}${
        context.date_range?.startDate ? ` (${fmtFriendlyDate(context.date_range.startDate)})` : ''
      }.`,
      nextStep: 'Ask HR/Admin to confirm if a schedule or DTR record should exist for that date.',
    });
  }
  const missing = missingDtrSlotsForContext(context, record);
  const day = calendarDayForDate(context, record.attendance_date);
  const details = [
    `Status: ${statusLabel(record.status)}`,
    `AM in: ${fmtTime(record.time_in)}`,
    `AM out: ${fmtTime(record.break_out)}`,
    `PM in: ${fmtTime(record.break_in)}`,
    `PM out: ${fmtTime(record.time_out)}`,
    `Total hours: ${fmtHours(record.total_hours)}`,
    `Late: ${fmtMinutes(record.late_minutes || 0)}`,
    `Undertime: ${fmtMinutes(record.undertime_minutes || 0)}`,
    missing.length > 0 ? `Missing: ${missing.join(', ')}` : null,
    day?.shift_name ? `Shift: ${day.shift_name} ${day.start_time || ''}-${day.end_time || ''}` : null,
    record.leave_type ? `Linked leave: ${labelLeaveType(record.leave_type)}` : null,
    record.holiday_name ? `Holiday: ${record.holiday_name}` : null,
  ];
  return structuredReply(language, {
    title: `DTR for ${fmtFriendlyDate(record.attendance_date)}`,
    summary: missing.length > 0
      ? `Your DTR is ${statusLabel(record.status)} and has missing logs.`
      : `Your DTR is ${statusLabel(record.status)}.`,
    details,
    nextStep: missing.length > 0
      ? 'Review the missing logs, then check locator, leave, or HR correction coverage.'
      : null,
  });
}

function dtrRangeSummaryReply(context, message) {
  const language = languageOf(message);
  const records = dtrRecords(context);
  const label = context.date_range?.label || 'selected period';
  const noRecords = noRecordWorkingDays(context);
  if (records.length === 0 && noRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang DTR records para sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang DTR records para sa ${label}.`;
    return `I found no DTR records for ${label}.`;
  }

  const totals = records.reduce(
    (acc, record) => {
      const status = lower(record.status);
      acc.hours += asNumber(record.total_hours) || 0;
      acc.late += Number(record.late_minutes || 0);
      acc.undertime += Number(record.undertime_minutes || 0);
      acc.overtime += Number(record.overtime_minutes || 0);
      if (status === 'present' || status === 'complete') acc.present += 1;
      else if (isAbsentDtrRecord(record)) acc.absent += 1;
      else if (isIncompleteDtrRecord(record)) acc.incomplete += 1;
      else if (status === 'on_leave' || record.leave_type) acc.onLeave += 1;
      else if (status === 'holiday' || record.holiday_name) acc.holiday += 1;
      else acc.other += 1;
      return acc;
    },
    { hours: 0, late: 0, undertime: 0, overtime: 0, present: 0, absent: 0, incomplete: 0, onLeave: 0, holiday: 0, other: 0 }
  );
  const issues = totals.incomplete + totals.absent + noRecords.length;
  const possibleAbsentOrNoRecord = totals.absent + noRecords.length;
  const wantsPresent =
    /\b(present|complete|kompleto|kumpleto)\b/.test(lower(message)) &&
    /\b(pila|ilan|how many|count|counts|total)\b/.test(lower(message));
  const summary = (() => {
    if (language === 'bisaya') {
      if (wantsPresent) {
        return `Naa kay ${totals.present} present/complete DTR ${plural(totals.present, 'day')} sa ${label}.`;
      }
      return issues > 0
        ? `Nakita nako ang ${issues} ka DTR ${plural(issues, 'item')} nga angay i-review para ani nga period.`
        : 'Wala koy nakitang klaro nga DTR issue para ani nga period.';
    }
    if (language === 'tagalog') {
      if (wantsPresent) {
        return `May ${totals.present} present/complete DTR ${plural(totals.present, 'day')} ka sa ${label}.`;
      }
      return issues > 0
        ? `May nakita akong ${issues} DTR ${plural(issues, 'item')} na kailangang i-review para sa period na ito.`
        : 'Wala akong nakitang obvious DTR issue para sa period na ito.';
    }
    if (wantsPresent) {
      return `You have ${totals.present} present/complete DTR ${plural(totals.present, 'day')} for ${label}.`;
    }
    return issues > 0
      ? `I found ${issues} DTR ${plural(issues, 'item')} to review for this period.`
      : 'I did not find obvious DTR issues for this period.';
  })();
  const absenceTotalLine =
    noRecords.length > 0 || totals.absent > 0
      ? `Absent/no-record days: ${possibleAbsentOrNoRecord}`
      : null;
  const savedAbsentLine =
    totals.absent > 0 || noRecords.length > 0
      ? `Saved absent rows: ${totals.absent}`
      : null;
  const noRecordLine =
    noRecords.length > 0
      ? `Generated no-record workdays: ${noRecords.length}`
      : null;
  const issueNextStep =
    issues > 0
      ? noRecords.length > 0
        ? language === 'bisaya'
          ? 'Ang saved absent rows kay kanang naa gyud sa DTR table. Ang generated no-record workdays kay scheduled workdays nga walay punches, mao na sila ang possible absent days.'
          : language === 'tagalog'
            ? 'Ang saved absent rows ay yung totoong nasa DTR table. Ang generated no-record workdays ay scheduled workdays na walang punches, kaya sila ang possible absent days.'
            : 'Saved absent rows are actual DTR rows. Generated no-record workdays are scheduled workdays with no punches, so they are possible absent days.'
        : 'Check missing logs, leave coverage, or locator coverage for the issue dates.'
      : null;
  return structuredReply(language, {
    title: `DTR summary for ${label}`,
    summary,
    details: [
      `Saved DTR rows: ${records.length}`,
      `Present/complete: ${totals.present}`,
      absenceTotalLine,
      `Incomplete: ${totals.incomplete}`,
      savedAbsentLine,
      noRecordLine,
      `On leave: ${totals.onLeave}`,
      `Holiday: ${totals.holiday}`,
      `Total hours: ${fmtHours(totals.hours)}`,
      `Late: ${fmtMinutes(totals.late)}`,
      `Undertime: ${fmtMinutes(totals.undertime)}`,
      `Overtime: ${fmtMinutes(totals.overtime)}`,
    ],
    nextStep: issueNextStep,
    limit: 13,
  });
}

function dtrMissingLogsReply(context, message, explain = false) {
  const language = languageOf(message);
  const label = context.date_range?.label || 'selected period';
  const records = dtrRecords(context);
  const noRecords = noRecordWorkingDays(context);
  if (records.length === 0 && noRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy DTR record para sa ${label}; dili nako ma-confirm kung unsang log ang missing.`;
    if (language === 'tagalog') return `Wala akong DTR record para sa ${label}; hindi ko ma-confirm kung anong log ang missing.`;
    return `I found no DTR record for ${label}, so I cannot confirm which log is missing.`;
  }

  const incomplete = dtrIssueRecords(records, (record) => isIncompleteDtrRecordForContext(context, record));
  if (incomplete.length === 0 && noRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang missing or incomplete DTR logs sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang missing or incomplete DTR logs sa ${label}.`;
    return `I found no missing or incomplete DTR logs for ${label}.`;
  }

  const recordLines = limitedRequests(incomplete, 8).map((record) => {
    const missing = missingDtrSlotsForContext(context, record);
    const reason = firstMatchingCoverageText(context, record, missing);
    return `${fmtFriendlyDate(record.attendance_date)}: missing ${missing.join(', ')}${
      explain && reason ? `; possible coverage found: ${reason}` : ''
    }`;
  });
  const noRecordLines = limitedRequests(noRecords, Math.max(0, 8 - recordLines.length)).map((day) => {
    return `${fmtFriendlyDate(day.attendance_date)}: no DTR record; expected logs: ${expectedSlotsForCalendarDay(day).join(', ')}${day.shift_name ? ` (${day.shift_name})` : ''}`;
  });
  const lines = [...recordLines, ...noRecordLines];
  const count = incomplete.length + noRecords.length;
  return structuredReply(language, {
    title: `Missing logs for ${label}`,
    summary: `I found ${count} missing or incomplete DTR ${plural(count, 'item')}.`,
    details: lines,
    nextStep: 'For each date, check if it should be corrected by HR/Admin, covered by a locator slip, or covered by leave.',
    limit: 8,
  });
}

function dtrMinuteSummaryReply(context, message, kind) {
  const language = languageOf(message);
  const records = dtrRecords(context);
  const label = context.date_range?.label || 'selected period';
  const field =
    kind === 'late'
      ? 'late_minutes'
      : kind === 'undertime'
        ? 'undertime_minutes'
        : 'overtime_minutes';
  const issueRecords = dtrIssueRecords(records, (record) => Number(record[field] || 0) > 0);
  const total = issueRecords.reduce((sum, record) => sum + Number(record[field] || 0), 0);
  if (issueRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang ${kind} records sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang ${kind} records sa ${label}.`;
    return `I found no ${kind} records for ${label}.`;
  }
  const lines = issueRecords.map((record) => `${fmtFriendlyDate(record.attendance_date)}: ${fmtMinutes(record[field])}`);
  return structuredReply(language, {
    title: `${kind} summary for ${label}`,
    summary: `I found ${issueRecords.length} ${kind} ${plural(issueRecords.length, 'record')}, total ${fmtMinutes(total)}.`,
    details: lines,
    nextStep: kind === 'late'
      ? 'Ask why you were late if you want the schedule/grace-period breakdown.'
      : null,
    limit: 8,
  });
}

function dtrLateReasonReply(context, message) {
  const language = languageOf(message);
  const records = dtrIssueRecords(dtrRecords(context), (record) => Number(record.late_minutes || 0) > 0);
  if (records.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang late minutes sa selected DTR records.';
    if (language === 'tagalog') return 'Wala akong nakitang late minutes sa selected DTR records.';
    return 'I found no late minutes in the selected DTR records.';
  }
  const lines = records.map((record) => {
    const day = calendarDayForDate(context, record.attendance_date);
    const grace = Number(day?.grace_period_minutes || 0);
    const shiftStart = timeTextToMinutes(day?.start_time);
    const breakEnd = timeTextToMinutes(day?.break_end);
    const timeInMinutes = minutesFromIsoInHrmsTimezone(record.time_in);
    const breakInMinutes = minutesFromIsoInHrmsTimezone(record.break_in);
    const amCutoff = shiftStart != null ? shiftStart + grace : null;
    const pmCutoff = breakEnd != null ? breakEnd + grace : null;
    const computed = [];
    if (amCutoff != null && timeInMinutes != null && timeInMinutes > amCutoff) {
      computed.push(`AM in ${fmtClockMinutes(timeInMinutes)} after cutoff ${fmtClockMinutes(amCutoff)} by ${fmtMinutes(timeInMinutes - amCutoff)}`);
    }
    if (pmCutoff != null && breakInMinutes != null && breakInMinutes > pmCutoff) {
      computed.push(`PM in ${fmtClockMinutes(breakInMinutes)} after cutoff ${fmtClockMinutes(pmCutoff)} by ${fmtMinutes(breakInMinutes - pmCutoff)}`);
    }
    const pieces = [
      `time in ${fmtTime(record.time_in)}`,
      `late ${fmtMinutes(record.late_minutes)}`,
      day?.shift_name
        ? `shift ${day.shift_name} ${day.start_time || ''}-${day.end_time || ''}, grace ${grace} min`
        : 'no shift schedule found',
      computed.length > 0 ? `reason: ${computed.join('. ')}` : null,
      record.source ? `source ${record.source}` : null,
      record.remarks ? `remarks ${record.remarks}` : null,
    ].filter(Boolean);
    return `${fmtFriendlyDate(record.attendance_date)}: ${pieces.join(', ')}`;
  });
  return structuredReply(language, {
    title: 'Late details',
    summary: `I found ${records.length} late ${plural(records.length, 'record')} in the selected DTR records.`,
    details: lines,
    nextStep: 'If the late minutes look wrong, compare the cutoff time with your actual time-in and ask HR/Admin to review.',
    limit: 5,
  });
}

function dtrAbsentSummaryReply(context, message) {
  const language = languageOf(message);
  const label = context.date_range?.label || 'selected period';
  const displayLabel = localizedPeriodLabel(label, language);
  const absent = dtrIssueRecords(dtrRecords(context), isAbsentDtrRecord);
  const noRecords = noRecordWorkingDays(context);
  if (absent.length === 0 && noRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang absent or no-record DTR para sa ${displayLabel}.`;
    if (language === 'tagalog') return `Wala akong nakitang DTR record na marked absent sa ${displayLabel}.`;
    return `I found no DTR records marked absent for ${displayLabel}.`;
  }
  const absentLines = absent.map((record) => `${fmtFriendlyDate(record.attendance_date)}: marked ${statusLabel(record.status)}`);
  const noRecordLines = noRecords.map((day) => `${fmtFriendlyDate(day.attendance_date)}: no DTR record on a scheduled workday${day.shift_name ? ` (${day.shift_name})` : ''}`);
  const all = [...absentLines, ...noRecordLines];
  if (language === 'bisaya') {
    return structuredReply(language, {
      title: `Absence check - ${displayLabel}`,
      summary: `Nakita nako ang ${all.length} ka posible nga absent/no-record ${plural(all.length, 'day')}.`,
      details: all,
      nextStep: 'I-check kung dapat ba ni ma-cover sa leave, locator, holiday, or DTR correction.',
      limit: 8,
    });
  }
  if (language === 'tagalog') {
    return structuredReply(language, {
      title: `Absence check para sa ${displayLabel}`,
      summary: `May nakita akong ${all.length} possible absence/no-record ${plural(all.length, 'day')}.`,
      details: all,
      nextStep: 'I-check kung dapat ba itong ma-cover ng leave, locator, holiday, o DTR correction.',
      limit: 8,
    });
  }
  return structuredReply(language, {
    title: `Absence check for ${displayLabel}`,
    summary: `I found ${all.length} possible absence/no-record ${plural(all.length, 'day')}.`,
    details: all,
    nextStep: 'Check if these dates should be covered by leave, locator, holiday, or a DTR correction.',
    limit: 8,
  });
}

function firstMatchingLeave(context, date) {
  return (context.recent_leave_requests || []).find((request) => {
    if (!approvedStatus(request.status)) return false;
    return request.start_date <= date && request.end_date >= date;
  });
}

function firstMatchingLocator(context, date) {
  return (context.recent_locator_slips || []).find((slip) => {
    return slip.slip_date === date && approvedStatus(slip.status);
  });
}

function locatorCoversSlot(slip, slot) {
  if (slot === 'AM in') return slip?.coverage?.am_in === true;
  if (slot === 'AM out') return slip?.coverage?.am_out === true;
  if (slot === 'PM in') return slip?.coverage?.pm_in === true;
  if (slot === 'PM out') return slip?.coverage?.pm_out === true;
  if (slot === 'no DTR record') {
    return (
      slip?.coverage?.am_in === true ||
      slip?.coverage?.am_out === true ||
      slip?.coverage?.pm_in === true ||
      slip?.coverage?.pm_out === true
    );
  }
  return false;
}

function locatorCoverageForMissingSlots(context, date, missingSlots = []) {
  const slips = (context.recent_locator_slips || []).filter((slip) => {
    return slip.slip_date === date && approvedStatus(slip.status);
  });
  if (slips.length === 0) return null;
  const missing = missingSlots.length > 0 ? missingSlots : ['no DTR record'];
  for (const slip of slips) {
    const covered = missing.filter((slot) => locatorCoversSlot(slip, slot));
    if (covered.length > 0) {
      const uncovered = missing.filter((slot) => !covered.includes(slot));
      return `${locatorCoverageText(slip)}. Covered: ${covered.join(', ')}${
        uncovered.length > 0 ? `. Not covered: ${uncovered.join(', ')}` : ''
      }`;
    }
  }
  return `${locatorCoverageText(slips[0])}. It does not match the missing logs: ${missing.join(', ')}`;
}

function locatorCoverageText(slip) {
  const slots = [];
  if (slip?.coverage?.am_in) slots.push('AM in');
  if (slip?.coverage?.am_out) slots.push('AM out');
  if (slip?.coverage?.pm_in) slots.push('PM in');
  if (slip?.coverage?.pm_out) slots.push('PM out');
  return `${slip.request_type_label || slip.request_type || 'Locator'} ${statusLabel(slip.status)}${
    slots.length > 0 ? ` covering ${slots.join(', ')}` : ''
  }`;
}

function firstMatchingCoverageText(context, record, missingSlots = []) {
  const date = fmtDate(record?.attendance_date);
  const leave = firstMatchingLeave(context, date);
  if (leave) return `${labelLeaveType(leave.leave_type)} (${workflowStatusText(leave.status)})`;
  const locatorText = locatorCoverageForMissingSlots(context, date, missingSlots);
  if (locatorText) return locatorText;
  return null;
}

function dtrStatusExplanationReply(context, message) {
  const language = languageOf(message);
  const record = dtrRecords(context)[0];
  if (!record) {
    const range = context.date_range || {};
    const day = range.startDate ? calendarDayForDate(context, range.startDate) : null;
    const dateText = range.startDate
      ? fmtLocalizedDateRange(range.startDate, range.endDate, language)
      : range.label || 'the selected date';
    if (day?.holiday_name) {
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Wala koy DTR punch record ${dateText}, pero holiday ni: ${day.holiday_name}.`
            : language === 'tagalog'
              ? `Wala akong DTR punch record ${dateText}, pero holiday ito: ${day.holiday_name}.`
              : `I found no DTR punch record ${dateText}, but this date is marked as ${day.holiday_name}.`,
        details: [
          `Status: ${statusLabel('holiday')}`,
          `Holiday coverage: ${day.holiday_coverage || 'whole_day'}`,
          day.shift_name ? `Schedule: ${day.shift_name}` : null,
        ],
        nextStep:
          language === 'bisaya'
            ? 'No action needed kung sakto ang holiday setup.'
            : language === 'tagalog'
              ? 'No action needed kung tama ang holiday setup.'
              : 'No action is needed if the holiday setup is correct.',
      });
    }
    if (day && !isCalendarWorkingDay(day)) {
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Wala koy DTR record ${dateText} kay dili siya required-log day base sa schedule context.`
            : language === 'tagalog'
              ? `Wala akong DTR record ${dateText} dahil hindi siya required-log day base sa schedule context.`
              : `I found no DTR record ${dateText} because it is not a required-log day in the schedule context.`,
        details: [
          `Status: ${statusLabel('rest_day')}`,
          `Schedule: ${day.shift_name || 'rest day/no required logs'}`,
          'Expected logs: none',
        ],
        nextStep:
          language === 'bisaya'
            ? 'No action needed kung sakto ang imong schedule ani nga date.'
            : language === 'tagalog'
              ? 'No action needed kung tama ang schedule mo sa date na ito.'
              : 'No action is needed if your schedule for that date is correct.',
      });
    }
    if (day && isCalendarWorkingDay(day)) {
      const expected = expectedSlotsForCalendarDay(day);
      const coverage = locatorCoverageForMissingSlots(context, day.attendance_date, ['no DTR record']);
      return structuredReply(language, {
        title: `DTR check for ${fmtFriendlyDate(day.attendance_date)}`,
        summary:
          language === 'bisaya'
            ? `Status: Absent/no DTR record. Scheduled workday ni pero wala koy nakitang DTR punches.`
            : language === 'tagalog'
              ? `Status: Absent/no DTR record. Scheduled workday ito pero wala akong nakitang DTR punches.`
              : 'Status: Absent/no DTR record. This is a scheduled workday, but no DTR punches were found.',
        details: [
          `Shift: ${day.shift_name || 'shift'} ${fmtScheduleRange(day)}`.trim(),
          `Grace period: ${fmtMinutes(day.grace_period_minutes || 0)}`,
          `Expected logs: ${expected.join(', ') || 'none'}`,
          coverage ? `Locator coverage: ${coverage}` : null,
        ],
        nextStep:
          language === 'bisaya'
            ? 'Kung ni-duty ka ani nga adlaw, i-check kung kinahanglan ba ug DTR correction, locator slip, or leave coverage.'
            : language === 'tagalog'
              ? 'Kung pumasok ka sa araw na ito, i-check kung kailangan ng DTR correction, locator slip, o leave coverage.'
              : 'If you worked that day, check whether you need a DTR correction, locator slip, or leave coverage.',
      });
    }
    if (language === 'bisaya') {
      return structuredReply(language, {
        title: 'DTR check',
        summary: `Wala koy nakitang DTR record ${dateText}.`,
        nextStep: 'Kung working day ni, i-check kung covered ba siya sa leave, locator, holiday, or HR correction.',
      });
    }
    if (language === 'tagalog') {
      return structuredReply(language, {
        title: 'DTR check',
        summary: `Wala akong nakitang DTR record ${dateText}.`,
        nextStep: 'Kung working day ito, i-check kung covered siya ng leave, locator, holiday, o HR correction.',
      });
    }
    return structuredReply(language, {
      title: 'DTR check',
      summary: `I found no DTR record ${dateText}.`,
      nextStep: 'If this is a working day, check whether leave, locator, holiday, or HR correction should cover it.',
    });
  }
  const missing = missingDtrSlotsForContext(context, record);
  const coverage = firstMatchingCoverageText(context, record, missing);
  const day = calendarDayForDate(context, record.attendance_date);
  const parts = [
    `Status: ${statusLabel(record.status)}`,
    day?.shift_name ? `Shift: ${day.shift_name} ${fmtScheduleRange(day)}` : null,
    missing.length > 0 ? `Missing logs: ${missing.join(', ')}` : null,
    record.leave_type ? `Linked leave: ${labelLeaveType(record.leave_type)}` : null,
    record.holiday_name ? `Holiday: ${record.holiday_name}` : null,
    coverage ? `Coverage: ${coverage}` : null,
    record.remarks ? `Remarks: ${record.remarks}` : null,
  ];
  const summary =
    language === 'bisaya'
      ? `Ang DTR status nimo kay ${statusLabel(record.status)}.`
      : language === 'tagalog'
        ? `Ang DTR status mo ay ${statusLabel(record.status)}.`
        : `Your DTR status is ${statusLabel(record.status)}.`;
  const nextStep =
    missing.length > 0
      ? language === 'bisaya'
        ? 'I-review ang missing logs ug i-check kung dapat covered sa leave, locator, or HR correction.'
        : language === 'tagalog'
          ? 'I-review ang missing logs at i-check kung dapat covered ng leave, locator, o HR correction.'
          : 'Review the missing logs and check if leave, locator, or HR correction should cover them.'
      : null;
  return structuredReply(language, {
    title: `DTR explanation for ${fmtFriendlyDate(record.attendance_date)}`,
    summary,
    details: parts,
    nextStep,
  });
}

function dtrCorrectionGuidanceReply(context, message) {
  const language = languageOf(message);
  const incomplete = dtrIssueRecords(dtrRecords(context), (record) =>
    isIncompleteDtrRecordForContext(context, record)
  );
  const requestedSlot = requestedDtrSlot(message);
  const target =
    (requestedSlot
      ? incomplete.find((record) => missingDtrSlotsForContext(context, record).includes(requestedSlot))
      : null) ||
    incomplete[0] ||
    dtrRecords(context)[0] ||
    null;
  const missing = missingDtrSlotsForContext(context, target);
  const coverage = target ? firstMatchingCoverageText(context, target, missing) : null;
  const issue = target
    ? `${fmtFriendlyDate(target.attendance_date)}${missing.length > 0 ? ` missing ${missing.join(', ')}` : ''}`
    : context.date_range?.label || 'selected date';
  const guidance = coverage
    ? [
        `Possible coverage found: ${coverage}`,
        'Ask HR/Admin if this has already been posted or synced to your DTR.',
      ]
    : [
        'If this was official business or WFH, file/check a locator slip.',
        'If this was a missed punch, contact HR/Admin for manual correction and prepare proof or remarks.',
        'If you were on leave, file/check the leave request.',
      ];
  return structuredReply(language, {
    title: 'How to fix this DTR issue',
    summary: `Target issue: ${issue}.`,
    details: guidance,
    nextStep: 'Start with the option that matches what actually happened on that date.',
  });
}

function dtrLeaveCoverageReply(context, message) {
  const language = languageOf(message);
  const label = context.date_range?.label || 'selected period';
  const leaves = (context.recent_leave_requests || []).filter((request) => {
    return approvedStatus(request.status) && requestOverlapsRange(request, context.date_range);
  });
  if (leaves.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang approved leave nga ni-cover sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang approved leave na nag-cover sa ${label}.`;
    return `I found no approved leave covering ${label}.`;
  }
  const lines = leaves.map(fmtLeaveRequest);
  return structuredReply(language, {
    title: `Leave coverage for ${label}`,
    summary: `I found ${leaves.length} approved leave ${plural(leaves.length, 'request')} covering this period.`,
    details: lines,
    nextStep: 'If the DTR still shows absent/missing logs, ask HR/Admin to verify whether the leave was posted to DTR.',
    limit: 5,
  });
}

function dtrLocatorCoverageReply(context, message) {
  const language = languageOf(message);
  const label = context.date_range?.label || 'selected period';
  const requestedSlot = requestedDtrSlot(message);
  const slips = (context.recent_locator_slips || []).filter((slip) => {
    if (!context.date_range?.startDate || !context.date_range?.endDate) return true;
    return slip.slip_date >= context.date_range.startDate && slip.slip_date <= context.date_range.endDate;
  });
  if (slips.length === 0) {
    return structuredReply(language, {
      title: 'Locator coverage check',
      summary:
        language === 'bisaya'
          ? `Wala koy nakitang locator slip para sa ${localizedPeriodLabel(label, language)}.`
          : language === 'tagalog'
            ? `Wala akong nakitang locator slip para sa ${localizedPeriodLabel(label, language)}.`
            : `I found no locator slip for ${label}.`,
      nextStep:
        language === 'bisaya'
          ? 'Kung missing log ni, i-check kung kinahanglan ba mag-file ug locator or DTR correction.'
          : language === 'tagalog'
            ? 'Kung missing log ito, i-check kung kailangan ng locator o DTR correction.'
            : 'If this is for a missing log, check whether you need a locator slip or DTR correction.',
    });
  }
  const approvedMatching = requestedSlot
    ? slips.filter((slip) => approvedStatus(slip.status) && locatorCoversSlot(slip, requestedSlot))
    : slips.filter((slip) => approvedStatus(slip.status));
  const lines = slips.map((slip) => {
    const slotCheck = requestedSlot
      ? locatorCoversSlot(slip, requestedSlot)
        ? `covers ${requestedSlot}`
        : `does not cover ${requestedSlot}`
      : locatorSlots(slip).length > 0
        ? `covers ${locatorSlots(slip).join(', ')}`
        : 'no covered slot saved';
    const finalCoverage = approvedStatus(slip.status) ? '' : ', not final coverage until approved';
    return `${fmtFriendlyDate(slip.slip_date)}: ${locatorCoverageText(slip)} (${slotCheck}${finalCoverage})${
      slip.hr_remarks ? `, HR remarks ${slip.hr_remarks}` : ''
    }`;
  });
  const summary = requestedSlot
    ? approvedMatching.length > 0
      ? language === 'bisaya'
        ? `Naa koy approved locator nga ni-cover sa ${requestedSlot} para sa ${localizedPeriodLabel(label, language)}.`
        : language === 'tagalog'
          ? `May approved locator na nag-cover sa ${requestedSlot} para sa ${localizedPeriodLabel(label, language)}.`
          : `I found an approved locator covering ${requestedSlot} for ${label}.`
      : language === 'bisaya'
        ? `Naa koy locator slip, pero wala koy approved locator nga klarong ni-cover sa ${requestedSlot}.`
        : language === 'tagalog'
          ? `May locator slip, pero wala akong approved locator na malinaw na nag-cover sa ${requestedSlot}.`
          : `I found locator slips, but no approved locator clearly covers ${requestedSlot}.`
    : language === 'bisaya'
      ? `Nakita nako ang ${slips.length} ka locator slip para sa ${localizedPeriodLabel(label, language)}.`
      : language === 'tagalog'
        ? `May nakita akong ${slips.length} locator slip para sa ${localizedPeriodLabel(label, language)}.`
        : `I found ${slips.length} locator ${plural(slips.length, 'slip')} in this period.`;
  return structuredReply(language, {
    title: `Locator coverage for ${label}`,
    summary,
    details: lines,
    nextStep:
      requestedSlot && approvedMatching.length === 0
        ? language === 'bisaya'
          ? 'Kung mao ni ang missing slot, i-check kung naa bay lain approved locator, leave, holiday, or DTR correction.'
          : language === 'tagalog'
            ? 'Kung ito ang missing slot, i-check kung may ibang approved locator, leave, holiday, o DTR correction.'
            : 'If this is the missing slot, check for another approved locator, leave, holiday, or DTR correction.'
        : 'If a specific log is missing, ask me to check locator coverage for that missing slot.',
    limit: 5,
  });
}

function dtrHolidayReply(context, message) {
  const language = languageOf(message);
  const recordHolidays = dtrRecords(context)
    .filter((record) => record.holiday_name || lower(record.status) === 'holiday')
    .map((record) => ({
      date: fmtDate(record.attendance_date),
      displayDate: fmtFriendlyDate(record.attendance_date),
      name: record.holiday_name || 'holiday',
      type: record.holiday_type || statusLabel(record.status),
      coverage: 'from DTR',
    }));
  const calendarHolidays = dtrCalendarDays(context)
    .filter((day) => day.holiday_name)
    .map((day) => ({
      date: day.attendance_date,
      displayDate: fmtFriendlyDate(day.attendance_date),
      name: day.holiday_name,
      type: day.holiday_type,
      coverage: day.holiday_coverage,
    }));
  const seen = new Set();
  const holidays = [...recordHolidays, ...calendarHolidays].filter((item) => {
    const key = `${item.date}|${item.name}|${item.coverage}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  if (holidays.length === 0) {
    const range = context.date_range || {};
    const period = range.startDate
      ? fmtLocalizedDateRange(range.startDate, range.endDate, language)
      : range.label || 'the selected period';
    if (language === 'bisaya') {
      return structuredReply(language, {
        title: 'Holiday check',
        summary: `Wala koy nakitang holiday record ${period}.`,
        nextStep: 'Kung dapat holiday ni, ipa-check sa HR/Admin ang holiday calendar setup.',
      });
    }
    if (language === 'tagalog') {
      return structuredReply(language, {
        title: 'Holiday check',
        summary: `Wala akong nakitang holiday record ${period}.`,
        nextStep: 'Kung dapat holiday ito, ipa-check sa HR/Admin ang holiday calendar setup.',
      });
    }
    return structuredReply(language, {
      title: 'Holiday check',
      summary: `I found no holiday record ${period}.`,
      nextStep: 'If this should be a holiday, ask HR/Admin to check the holiday calendar setup.',
    });
  }
  const lines = holidays.map((holiday) => `${holiday.displayDate || fmtFriendlyDate(holiday.date)}: ${holiday.name} (${holiday.type || 'holiday'}, ${holiday.coverage || 'whole_day'})`);
  const summary =
    language === 'bisaya'
      ? `Nakita nako ang ${holidays.length} ka holiday record para ani nga period.`
      : language === 'tagalog'
        ? `Nakakita ako ng ${holidays.length} holiday ${plural(holidays.length, 'record')} para sa period na ito.`
        : `I found ${holidays.length} holiday-linked ${plural(holidays.length, 'record')} for this period.`;
  const nextStep =
    language === 'bisaya'
      ? 'Kung holiday date pero na-count gihapon nga absent, ipa-review sa HR/Admin ang holiday coverage ug schedule setup.'
      : language === 'tagalog'
        ? 'Kung holiday date pero na-count pa rin as absent, ipa-review sa HR/Admin ang holiday coverage at schedule setup.'
        : 'If a holiday date is still counted as absent, ask HR/Admin to review the holiday coverage and schedule setup.';
  return structuredReply(language, {
    title: 'Holiday check',
    summary,
    details: lines,
    nextStep,
    limit: 5,
  });
}

function dtrScheduleContextReply(context, message) {
  const language = languageOf(message);
  const days = dtrCalendarDays(context).filter((day) => day.shift_id || day.holiday_id);
  if (days.length === 0) {
    const text = 'I found no assignment/shift schedule for the selected period. HR/Admin should confirm schedule-specific late or undertime rules.';
    if (language === 'bisaya') return `Wala koy nakitang shift schedule sa selected period. ${text}`;
    if (language === 'tagalog') return `Wala akong nakitang shift schedule sa selected period. ${text}`;
    return text;
  }
  const lines = limitedRequests(days, 7).map((day) => {
    const expected = expectedSlotsForCalendarDay(day);
    const working = isCalendarWorkingDay(day) ? 'working day' : 'non-working/no required logs';
    const holiday = day.holiday_name
      ? `, holiday ${day.holiday_name} (${day.holiday_coverage || 'whole_day'})`
      : '';
    return `${fmtFriendlyDate(day.attendance_date)}: ${day.shift_name || 'no shift'} ${day.start_time || ''}-${day.end_time || ''}, grace ${day.grace_period_minutes || 0} min, ${working}, expected ${expected.length > 0 ? expected.join(', ') : 'none'}${holiday}`;
  });
  return structuredReply(language, {
    title: `Schedule context for ${context.date_range?.label || 'selected period'}`,
    summary: `I found ${days.length} schedule/holiday ${plural(days.length, 'day')}.`,
    details: lines,
    nextStep: 'Use this to verify expected logs, late cutoff, undertime, rest day, or holiday handling.',
    limit: 7,
  });
}

function dtrExportGuidanceReply(context, message) {
  const language = languageOf(message);
  return structuredReply(language, {
    title: 'DTR export',
    summary: 'I generated an Excel export for the selected DTR period.',
    details: [
      'The file includes the DTR records currently loaded for this chat.',
      'For signed official DTR forms, still use the DTR/attendance report page or HR/Admin workflow.',
    ],
    nextStep: 'Download the attached Excel file from this message.',
  });
}

function leaveBalanceReply(context, localized, message) {
  const balances = context.leave_balances || [];
  if (balances.length === 0) {
    return localized
      ? 'Wala akong nakitang leave balance records para sa account mo.'
      : 'I found no leave balance records for your account.';
  }

  const language = languageOf(message);
  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const selected = balances.filter((b) => {
    if (requestedRecord) return leaveBalanceMatchesRecord(b, requestedRecord);
    return leaveTypeMatches(b, requestedType);
  });
  const visibleBalances = selected.length > 0 ? selected : balances;
  const why = isWhyBalanceQuestion(message);

  if (why && visibleBalances.length === 1) {
    const b = visibleBalances[0];
    const type = labelLeaveType(b.leave_type);
    if (language === 'bisaya') {
      return `Ang ${type} balance nimo kay ${fmtDays(
        b.available_days
      )} available. Gamay siya kung gamay pa ang na-earn or naa nay nagamit/pending: ${balanceFormulaLine(
        b
      )}.`;
    }
    if (language === 'tagalog') {
      return `Ang ${type} balance mo ay ${fmtDays(
        b.available_days
      )} available. Maliit ito kung kaunti pa ang earned o may used/pending days: ${balanceFormulaLine(
        b
      )}.`;
    }
    return `Your ${type} balance is ${fmtDays(
      b.available_days
    )} available. It may be low because of earned, used, adjusted, and pending days: ${balanceFormulaLine(
      b
    )}.`;
  }

  if (why) {
    const explanations = visibleBalances.map((b) => {
      return `${labelLeaveType(b.leave_type)}: ${balanceFormulaLine(b)}`;
    });
    if (language === 'bisaya') {
      return `Base sa records, mao ni nganong mao ra ang nabilin nga leave balance: ${explanations.join(
        '; '
      )}. Ang available balance maapektuhan sa earned, used, adjusted, ug pending days.`;
    }
    if (language === 'tagalog') {
      return `Base sa records, ito ang breakdown kung bakit ganyan ang natitirang leave balance: ${explanations.join(
        '; '
      )}. Naaapektuhan ang available balance ng earned, used, adjusted, at pending days.`;
    }
    return `Here is why your leave balance is at that amount: ${explanations.join(
      '; '
    )}. Available balance is affected by earned, used, adjusted, and pending days.`;
  }

  const lines = visibleBalances.map((b) => {
    return `${labelLeaveType(b.leave_type)}: ${fmtDays(b.available_days)} available, ${fmtDays(
      b.remaining_days
    )} remaining, ${fmtDays(b.pending_days)} pending`;
  });

  return structuredReply(language, {
    title: 'Leave balance',
    summary: `I found ${visibleBalances.length} leave balance ${plural(visibleBalances.length, 'record')}.`,
    details: lines,
    limit: 8,
  });
}

function latestLeaveReply(context, localized) {
  const request = context.recent_leave_requests?.[0];
  if (!request) {
    return localized
      ? 'Wala akong nakitang leave request records para sa account mo.'
      : 'I found no leave request records for your account.';
  }

  const details = `${labelLeaveType(request.leave_type || 'Leave')} ${fmtFriendlyDateRange(
    request.start_date,
    request.end_date
  )} is ${workflowStatusText(request.status)}`;
  const reviewer =
    request.reviewer_name || request.approver_name || request.latest_history?.actor_name;
  const remarks = firstReviewReason(request)
    ? ` Remarks: ${firstReviewReason(request)}.`
    : '';
  const reviewedBy = reviewer ? ` Last reviewer: ${reviewer}.` : '';

  return localized
    ? `${details}.${remarks}${reviewedBy}`
    : `Your latest leave request: ${details}.${remarks}${reviewedBy}`;
}

function leaveRequestsByStatusReply(context, message, matcher, labels) {
  const language = languageOf(message);
  const useRange = hasDateRangeHint(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (!matcher(request.status)) return false;
    if (!requestMatchesMessageFilters(request, message, context)) return false;
    if (useRange && !requestOverlapsRange(request, context.date_range)) return false;
    return true;
  });

  if (requests.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang ${labels.bisaya} leave request.`;
    if (language === 'tagalog') return `Wala akong nakitang ${labels.tagalog} leave request.`;
    return `I found no ${labels.english} leave requests.`;
  }

  const lines = requests.map((request) => {
    const reason = firstReviewReason(request);
    return `${fmtLeaveRequest(request)}${reason ? `. Remarks: ${trimTrailingSentencePunctuation(reason)}.` : ''}`;
  });
  return structuredReply(language, {
    title: `${labels.english[0].toUpperCase()}${labels.english.slice(1)} leave requests`,
    summary: `I found ${requests.length} ${labels.english} leave request${requests.length === 1 ? '' : 's'}.`,
    details: lines,
    limit: 5,
  });
}

function leaveHistoryReply(context, message) {
  const language = languageOf(message);
  const useRange = hasDateRangeHint(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    return requestMatchesMessageFilters(request, message, context);
  });

  if (requests.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave history para ana nga period.';
    if (language === 'tagalog') return 'Wala akong nakitang leave history para sa period na iyon.';
    return 'I found no leave history for that period.';
  }

  const label = useRange ? context.date_range?.label || 'selected period' : 'recent requests';
  return structuredReply(language, {
    title: `Leave history (${label})`,
    summary: `I found ${requests.length} leave request${requests.length === 1 ? '' : 's'}.`,
    details: requests.map(fmtLeaveRequest),
    limit: 5,
  });
}

function leaveAvailabilityReply(context, message) {
  const language = languageOf(message);
  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const days = requestedDaysOrRangeDays(message, context);
  const balances = context.leave_balances || [];
  const selected = balances.filter((b) => {
    if (requestedRecord) return leaveBalanceMatchesRecord(b, requestedRecord);
    return leaveTypeMatches(b, requestedType);
  });
  const balance = requestedType || requestedRecord || selected.length === 1 ? selected[0] : null;

  if (!days) {
    if (language === 'bisaya') return 'Pila ka adlaw nga leave ang imong plano i-file?';
    if (language === 'tagalog') return 'Ilang araw ng leave ang balak mong i-file?';
    return 'How many leave days are you planning to file?';
  }

  if (!requestedType && !requestedRecord && selected.length > 1) {
    if (language === 'bisaya') return 'Unsang leave type ang imong gamiton: sick leave, vacation leave, or lain?';
    if (language === 'tagalog') return 'Anong leave type ang gagamitin mo: sick leave, vacation leave, o iba pa?';
    return 'Which leave type do you want to use: sick leave, vacation leave, or another type?';
  }

  const available = balance ? asNumber(balance.available_days) || 0 : null;
  const type = labelLeaveType(balance?.leave_type || requestedRecord?.display_name || requestedRecord?.name || 'leave');
  const enough = available == null ? null : available >= days;
  const warnings = [];
  const blockers = [];
  const notes = [];
  if (requestedRecord?.employee_can_file === false) {
    blockers.push('employee filing is disabled for this leave type');
  }
  if (requestedRecord?.admin_only === true) {
    blockers.push('this leave type is admin/HR-only');
  }
  if (requestedRecord?.allows_past_dates === false && context.date_range?.startDate) {
    const daysFromToday = daysBetweenIso(new Date().toISOString().slice(0, 10), context.date_range.startDate);
    if (daysFromToday != null && daysFromToday < 0) {
      blockers.push('past-date filing is not allowed for this leave type');
    }
  }
  const advanceDays = asNumber(requestedRecord?.minimum_advance_days);
  if (advanceDays != null && context.date_range?.startDate) {
    const daysFromToday = daysBetweenIso(new Date().toISOString().slice(0, 10), context.date_range.startDate);
    if (daysFromToday != null && daysFromToday < advanceDays) {
      warnings.push(`needs ${fmtDayCount(advanceDays)} advance notice`);
    }
  }
  const maxDays = asNumber(requestedRecord?.max_days);
  if (maxDays != null && days > maxDays) {
    blockers.push(`max allowed is ${fmtDayCount(maxDays)}`);
  }
  if (requestedRecord) {
    notes.push(attachmentRuleText(requestedRecord, days));
  }
  if (!balance) {
    notes.push('no matching leave balance row was found for this leave type');
  }
  if (hasDateRangeHint(message)) {
    const overlaps = (context.recent_leave_requests || []).filter((request) => {
      if (!activeLeaveStatus(request.status)) return false;
      if (!requestOverlapsRange(request, context.date_range)) return false;
      if (requestedRecord && !leaveRequestMatchesRecord(request, requestedRecord)) return false;
      return true;
    });
    if (overlaps.length > 0) {
      blockers.push(`Overlap found: ${limitedRequests(overlaps, 2).map(fmtLeaveRequest).join(' | ')}`);
    }
  }
  const baseBalanceEnglish =
    available == null
      ? `I could not verify a balance row for ${type}, but I checked the filing rules for ${fmtDayCount(days)}`
      : `you have ${fmtDays(available)} available ${type} for ${fmtDayCount(days)}`;
  const baseBalanceBisaya =
    available == null
      ? `wala koy matching balance row para sa ${type}, pero na-check nako ang filing rules para sa ${fmtDayCount(days)}`
      : `naa kay ${fmtDays(available)} available ${type} para sa ${fmtDayCount(days)}`;
  const baseBalanceTagalog =
    available == null
      ? `wala akong matching balance row para sa ${type}, pero na-check ko ang filing rules para sa ${fmtDayCount(days)}`
      : `may ${fmtDays(available)} available ${type} para sa ${fmtDayCount(days)}`;

  if (language === 'bisaya') {
    const details = [
      blockers.length > 0 ? `Issue: ${blockers.join(' | ')}` : null,
      warnings.length > 0 ? `Warning: ${warnings.join(' | ')}` : null,
      ...notes.map((note) => `Note: ${note}`),
    ].filter(Boolean);
    if (blockers.length > 0 || enough === false) {
      const balanceText =
        enough === false
          ? `dili igo ang balance: naa kay ${fmtDays(available)} available ${type}, pero ${fmtDayCount(days)} imong plano`
          : baseBalanceBisaya;
      return structuredReply(language, {
        title: 'Leave filing check',
        summary: `Dili pa limpyo ang filing check: ${balanceText}.`,
        details,
        nextStep: 'Final approval gihapon ang HR workflow.',
      });
    }
    return structuredReply(language, {
      title: 'Leave filing check',
      summary: `Pwede sa initial filing check: ${baseBalanceBisaya}.`,
      details,
      nextStep: 'Dili pa ni final approval.',
    });
  }
  if (language === 'tagalog') {
    const details = [
      blockers.length > 0 ? `Issue: ${blockers.join(' | ')}` : null,
      warnings.length > 0 ? `Warning: ${warnings.join(' | ')}` : null,
      ...notes.map((note) => `Note: ${note}`),
    ].filter(Boolean);
    if (blockers.length > 0 || enough === false) {
      const balanceText =
        enough === false
          ? `hindi sapat ang balance: may ${fmtDays(available)} available ${type}, pero ${fmtDayCount(days)} ang plano mo`
          : baseBalanceTagalog;
      return structuredReply(language, {
        title: 'Leave filing check',
        summary: `May issue sa filing check: ${balanceText}.`,
        details,
        nextStep: 'Dadaan pa rin ito sa HR approval workflow.',
      });
    }
    return structuredReply(language, {
      title: 'Leave filing check',
      summary: `Puwede sa initial filing check: ${baseBalanceTagalog}.`,
      details,
      nextStep: 'Hindi pa ito final approval.',
    });
  }
  const details = [
    blockers.length > 0 ? `Issue: ${blockers.join(' | ')}` : null,
    warnings.length > 0 ? `Warning: ${warnings.join(' | ')}` : null,
    ...notes.map((note) => `Note: ${note}`),
  ].filter(Boolean);
  if (blockers.length > 0 || enough === false) {
    const balanceText =
      enough === false
        ? `balance is not enough: you have ${fmtDays(available)} available ${type}, but plan to file ${fmtDayCount(days)}`
        : baseBalanceEnglish;
    return structuredReply(language, {
      title: 'Leave filing check',
      summary: `Filing check found an issue: ${balanceText}.`,
      details,
      nextStep: 'This still needs the normal HR approval workflow.',
    });
  }
  return structuredReply(language, {
    title: 'Leave filing check',
    summary: `Initial filing check looks okay: ${baseBalanceEnglish}.`,
    details,
    nextStep: 'This is not final approval yet.',
  });
}

function leaveTypesReply(context, message) {
  const language = languageOf(message);
  const types = context.leave_types || [];
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang active leave types sa system records.';
    if (language === 'tagalog') return 'Wala akong nakitang active leave types sa system records.';
    return 'I found no active leave types in the system records.';
  }

  const lines = types
    .filter((type) => type.employee_can_file !== false)
    .slice(0, 8)
    .map((type) => labelLeaveType(type.display_name || type.name))
    .join(', ');
  if (language === 'bisaya') return `Mao ni ang leave types nga pwede nimo ma-file: ${lines}.`;
  if (language === 'tagalog') return `Ito ang leave types na puwede mong i-file: ${lines}.`;
  return `These are the leave types you can file: ${lines}.`;
}

function leaveRequirementsReply(context, message) {
  const language = languageOf(message);
  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const allTypes = context.leave_types || [];
  const selected = requestedRecord
    ? [requestedRecord]
    : allTypes.filter((type) => leaveTypeRecordMatches(type, requestedType));
  const visibleTypes = selected.length > 0 ? selected : allTypes.filter((type) => type.employee_can_file !== false);

  if (visibleTypes.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave filing requirements sa system records.';
    if (language === 'tagalog') return 'Wala akong nakitang leave filing requirements sa system records.';
    return 'I found no leave filing requirements in the system records.';
  }

  const lines = visibleTypes.slice(0, 4).map((type) => {
    const guidance = getLeaveGuidanceForType(type);
    const guidelineText = guidance
      ? ` Guideline: ${trimTrailingSentencePunctuation(
          [guidance.requirements, guidance.limits, guidance.advanceFiling]
            .filter(Boolean)
            .join(' ')
        )}.`
      : '';
    return `${labelLeaveType(type.display_name || type.name)}: ${leaveRequirementParts(
      type
    ).join(', ')}.${guidelineText}`;
  });

  return structuredReply(language, {
    title: 'Leave requirements',
    summary: 'Here are the filing requirements I found from the HRMS setup and guidelines.',
    details: lines.map(trimTrailingSentencePunctuation),
    nextStep: 'Final approval still follows the HR review workflow.',
    limit: 4,
  });
}

function leaveRequirementParts(type) {
  const parts = [];
  parts.push(
    type.employee_can_file === false || type.admin_only
      ? 'employee filing disabled'
      : 'employee can file'
  );
  parts.push(type.allows_past_dates === false ? 'past dates not allowed' : 'past dates allowed');
  parts.push(attachmentRuleText(type));
  if (type.minimum_advance_days != null) {
    parts.push(`${fmtDayCount(type.minimum_advance_days)} advance notice`);
  }
  if (type.max_days != null) {
    parts.push(`max ${fmtDayCount(type.max_days)}`);
  }
  return parts;
}

function matchingLeaveTypes(context, message) {
  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const allTypes = context.leave_types || [];
  if (requestedRecord) return [requestedRecord];
  const selected = allTypes.filter((type) => leaveTypeRecordMatches(type, requestedType));
  return selected.length > 0 ? selected : allTypes.filter((type) => type.employee_can_file !== false);
}

function leaveAttachmentRequirementReply(context, message) {
  const language = languageOf(message);
  const types = matchingLeaveTypes(context, message);
  const days = requestedDaysOrRangeDays(message, context);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang attachment rule para ana nga leave type.';
    if (language === 'tagalog') return 'Wala akong nakitang attachment rule para sa leave type na iyon.';
    return 'I found no attachment rule for that leave type.';
  }

  const lines = types.slice(0, 4).map((type) => {
    const guidance = getLeaveGuidanceForType(type);
    const guideline = guidance?.requirements
      ? ` Guideline: ${trimTrailingSentencePunctuation(guidance.requirements)}.`
      : '';
    return `${labelLeaveType(type.display_name || type.name)}: ${attachmentRuleText(
      type,
      days
    )}.${guideline}`;
  });

  return structuredReply(language, {
    title: 'Attachment requirement',
    summary: 'Here is what the HRMS setup says about attachments.',
    details: lines.map(trimTrailingSentencePunctuation),
    limit: 4,
  });
}

function leaveFilingPolicyReply(context, message) {
  const language = languageOf(message);
  const types = matchingLeaveTypes(context, message);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang filing policy para ana nga leave type.';
    if (language === 'tagalog') return 'Wala akong nakitang filing policy para sa leave type na iyon.';
    return 'I found no filing policy for that leave type.';
  }

  const lines = types.slice(0, 4).map((type) => {
    const guidance = getLeaveGuidanceForType(type);
    const guidelineSummary = trimTrailingSentencePunctuation(
      summarizeLeaveGuidance(guidance)
    );
    return `${labelLeaveType(type.display_name || type.name)}: ${leaveRequirementParts(
      type
    ).join(', ')}.${guidelineSummary ? ` Guideline: ${guidelineSummary}` : ''}`;
  });

  return structuredReply(language, {
    title: 'Leave filing policy',
    summary: 'Here is the filing policy from the HRMS setup and guidelines.',
    details: lines.map(trimTrailingSentencePunctuation),
    nextStep: 'Approval still follows the HR workflow.',
    limit: 4,
  });
}

function leaveFormGuidanceReply(context, message) {
  const language = languageOf(message);
  const types = matchingLeaveTypes(context, message).slice(0, 3);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave type para sa form guidance.';
    if (language === 'tagalog') return 'Wala akong nakitang leave type para sa form guidance.';
    return 'I found no leave type for form guidance.';
  }

  const lines = types.map((type) => {
    const form = getFormGuidanceForType(type);
    const requirement = attachmentRuleText(type, requestedDaysOrRangeDays(message, context));
    return `${labelLeaveType(type.display_name || type.name)}: ${form.fields.join(' ')} Requirement: ${requirement}.`;
  });

  return structuredReply(language, {
    title: 'Leave form guide',
    summary: 'Use these details when filling out the leave form.',
    details: lines.map(trimTrailingSentencePunctuation),
    limit: 3,
  });
}

function leaveEligibilityReply(context, message) {
  const language = languageOf(message);
  const types = matchingLeaveTypes(context, message).slice(0, 3);
  const employeeSex = normalizeSex(context.employee?.sex);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave type para sa eligibility check.';
    if (language === 'tagalog') return 'Wala akong nakitang leave type para sa eligibility check.';
    return 'I found no leave type for an eligibility check.';
  }

  const lines = types.map((type) => {
    const blockers = [];
    const warnings = [];
    const sexRule = lower(type.sex_eligibility || 'any') || 'any';
    if (type.employee_can_file === false || type.admin_only) {
      blockers.push('employee filing disabled/admin-only');
    }
    if (sexRule !== 'any') {
      if (!employeeSex) {
        warnings.push(`profile sex is missing, HR should confirm ${sexRule} eligibility`);
      } else if (employeeSex !== sexRule) {
        blockers.push(`configured for ${sexRule} employees only`);
      }
    }
    const label = labelLeaveType(type.display_name || type.name);
    if (blockers.length > 0) return `${label}: not eligible by current rule (${blockers.join(', ')})`;
    if (warnings.length > 0) return `${label}: likely eligible, but ${warnings.join(', ')}`;
    return `${label}: eligible by profile/rule check`;
  });

  return structuredReply(language, {
    title: 'Eligibility check',
    summary: 'This is only an initial filing check.',
    details: lines,
    nextStep: 'Final approval still follows the HR workflow.',
    limit: 3,
  });
}

function leaveDtrImpactReply(context, message) {
  const language = languageOf(message);
  const types = matchingLeaveTypes(context, message).slice(0, 3);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave type para sa DTR impact.';
    if (language === 'tagalog') return 'Wala akong nakitang leave type para sa DTR impact.';
    return 'I found no leave type for DTR impact.';
  }

  const lines = types.map((type) => {
    const label = labelLeaveType(type.display_name || type.name);
    const balance = type.balance_ledger_type
      ? `balance ledger: ${type.balance_ledger_type}`
      : 'no specific balance ledger shown';
    if (type.affects_dtr_normally === false) {
      return `${label}: configured not to affect DTR normally; HR may handle attendance manually.`;
    }
    return `${label}: once approved/posting runs, covered dates can be marked on leave in DTR; ${balance}.`;
  });

  return structuredReply(language, {
    title: 'DTR impact',
    summary: 'Here is how the leave can affect DTR after approval/posting.',
    details: lines,
    nextStep: 'Final posting or approval is still the basis.',
    limit: 3,
  });
}

function leaveGuidelineSectionReply(context, message) {
  const language = languageOf(message);
  const sections = getGuidelineSectionsForMessage(message);
  const type = requestedLeaveTypeRecord(message, context);
  const guidance = type ? getLeaveGuidanceForType(type) : null;

  if (guidance && /\b(supporting|document|docs|attachment|requirements?)\b/i.test(message)) {
    const line = `${labelLeaveType(type.display_name || type.name)}: ${trimTrailingSentencePunctuation(
      [guidance.requirements, guidance.limits, guidance.advanceFiling, guidance.notes]
        .filter(Boolean)
        .join(' ')
    )}. Requirement: ${attachmentRuleText(type, requestedDaysOrRangeDays(message, context))}.`;
    return structuredReply(language, {
      title: 'Guideline answer',
      summary: 'Here is the guideline detail I found.',
      details: [line],
    });
  }

  if (sections.length === 0) {
    const titles = GUIDELINE_SECTIONS.map((section) => section.title).join(', ');
    if (language === 'bisaya') return `Pwede nako i-explain ani nga guideline sections: ${titles}.`;
    if (language === 'tagalog') return `Pwede kong i-explain itong guideline sections: ${titles}.`;
    return `I can explain these guideline sections: ${titles}.`;
  }

  const lines = sections.map((section) => `${section.title}: ${section.points.join(' ')}`);
  return structuredReply(language, {
    title: 'Guidelines',
    summary: `I found ${sections.length} guideline ${plural(sections.length, 'section')}.`,
    details: lines,
    limit: 4,
  });
}

function leaveTypeCompareReply(context, message) {
  const language = languageOf(message);
  const types = mentionedLeaveTypeRecords(context, message).slice(0, 2);
  if (types.length < 2) {
    if (language === 'bisaya') return 'Unsang duha ka leave types ang imong gusto i-compare? Example: sick leave vs vacation leave.';
    if (language === 'tagalog') return 'Aling dalawang leave types ang gusto mong i-compare? Example: sick leave vs vacation leave.';
    return 'Which two leave types do you want to compare? Example: sick leave vs vacation leave.';
  }

  const lines = types.map((type) => {
    const guidance = getLeaveGuidanceForType(type);
    const pieces = [
      leaveRequirementParts(type).join(', '),
      guidance?.requirements ? `guideline requirements: ${guidance.requirements}` : null,
      guidance?.limits ? `limit: ${guidance.limits}` : null,
    ].filter(Boolean);
    return `${labelLeaveType(type.display_name || type.name)}: ${pieces.join('. ')}`;
  });

  return structuredReply(language, {
    title: 'Leave type comparison',
    summary: 'Here is the side-by-side comparison.',
    details: lines,
    limit: 2,
  });
}

function leaveGuidedFilingReply(context, message) {
  const language = languageOf(message);
  const type = requestedLeaveTypeRecord(message, context);
  const days = requestedDaysOrRangeDays(message, context);
  const missing = [];
  if (!type) missing.push('leave type');
  if (!hasDateRangeHint(message)) missing.push('date or date range');
  if (!days) missing.push('number of days');

  if (missing.length > 0) {
    if (language === 'bisaya') {
      return `Tabangan tika sa leave filing. Kulang pa: ${missing.join(', ')}. Ihatag ang leave type, date range, number of days, ug reason/attachment kung required.`;
    }
    if (language === 'tagalog') {
      return `Tutulungan kita sa leave filing. Kulang pa: ${missing.join(', ')}. Ibigay ang leave type, date range, number of days, at reason/attachment kung required.`;
    }
    return `I can guide the leave filing. Missing: ${missing.join(', ')}. Provide leave type, date range, number of days, and reason/attachment if required.`;
  }

  const check = leaveAvailabilityReply(context, message);
  const form = getFormGuidanceForType(type);
  if (language === 'bisaya') {
    return `${check} Sunod: sa form, ${form.fields.join(' ')} I-submit ra sa leave module; dili pa ko mo-auto-submit.`;
  }
  if (language === 'tagalog') {
    return `${check} Next: sa form, ${form.fields.join(' ')} I-submit sa leave module; hindi ako mag-auto-submit.`;
  }
  return `${check} Next in the form: ${form.fields.join(' ')} Submit it in the leave module; I will not auto-submit it.`;
}

function leaveOverlapCheckReply(context, message) {
  const language = languageOf(message);
  if (!hasDateRangeHint(message)) {
    if (language === 'bisaya') return 'Unsang date or date range ang imong gusto ipa-check?';
    if (language === 'tagalog') return 'Anong date or date range ang gusto mong ipa-check?';
    return 'Which date or date range do you want me to check?';
  }

  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const overlaps = (context.recent_leave_requests || []).filter((request) => {
    if (!activeLeaveStatus(request.status)) return false;
    if (!requestOverlapsRange(request, context.date_range)) return false;
    if (requestedRecord && !leaveRequestMatchesRecord(request, requestedRecord)) return false;
    return true;
  });

  if (overlaps.length === 0) {
    if (language === 'bisaya') {
      return `Wala koy nakitang active leave request nga ni-overlap sa ${context.date_range?.label || 'selected date'}.`;
    }
    if (language === 'tagalog') {
      return `Wala akong nakitang active leave request na nag-o-overlap sa ${context.date_range?.label || 'selected date'}.`;
    }
    return `I found no active leave request overlapping ${context.date_range?.label || 'the selected date'}.`;
  }

  return structuredReply(language, {
    title: 'Leave overlap check',
    summary: `I found ${overlaps.length} overlapping leave ${plural(overlaps.length, 'request')}.`,
    details: overlaps.map(fmtLeaveRequest),
    nextStep: 'Review the overlapping request before filing another leave for the same date.',
    limit: 5,
  });
}

function leavePendingDaysExplanationReply(context, message) {
  const language = languageOf(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const pendingBalances = (context.leave_balances || []).filter((balance) => {
    if ((asNumber(balance.pending_days) || 0) <= 0) return false;
    if (requestedRecord) return leaveBalanceMatchesRecord(balance, requestedRecord);
    return true;
  });
  const pendingRequests = (context.recent_leave_requests || []).filter((request) => {
    if (!pendingStatus(request.status)) return false;
    if (requestedRecord && !leaveRequestMatchesRecord(request, requestedRecord)) return false;
    return true;
  });

  if (pendingBalances.length === 0 && pendingRequests.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang pending leave days sa imong current records.';
    if (language === 'tagalog') return 'Wala akong nakitang pending leave days sa current records mo.';
    return 'I found no pending leave days in your current records.';
  }

  const balanceLines = pendingBalances.map((b) => {
    return `${labelLeaveType(b.leave_type)} pending ${fmtDayCount(b.pending_days)}`;
  });
  const requestLines = limitedRequests(pendingRequests, 4).map(fmtLeaveRequest);
  const details = [...balanceLines, ...requestLines];

  return structuredReply(language, {
    title: 'Pending leave days',
    summary: 'Here is where the pending leave days are coming from.',
    details,
    limit: 6,
  });
}

function leaveBalanceAfterFilingReply(context, message) {
  const language = languageOf(message);
  const days = parseRequestedDays(message);
  if (!days) {
    if (language === 'bisaya') return 'Pila ka adlaw nga leave ang imong plano i-file?';
    if (language === 'tagalog') return 'Ilang araw ng leave ang balak mong i-file?';
    return 'How many leave days are you planning to file?';
  }

  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const balances = context.leave_balances || [];
  const selected = balances.filter((b) => {
    if (requestedRecord) return leaveBalanceMatchesRecord(b, requestedRecord);
    return leaveTypeMatches(b, requestedType);
  });
  const balance = requestedType || requestedRecord || selected.length === 1 ? selected[0] : null;

  if (!requestedType && !requestedRecord && selected.length > 1) {
    if (language === 'bisaya') return 'Unsang leave type ang imong gamiton para sa balance-after-filing check?';
    if (language === 'tagalog') return 'Anong leave type ang gagamitin mo para sa balance-after-filing check?';
    return 'Which leave type should I use for the balance-after-filing check?';
  }
  if (!balance) {
    if (language === 'bisaya') return 'Wala koy matching leave balance para ana nga leave type.';
    if (language === 'tagalog') return 'Wala akong matching leave balance para sa leave type na iyon.';
    return 'I found no matching leave balance for that leave type.';
  }

  const available = asNumber(balance.available_days) || 0;
  const after = available - days;
  const type = labelLeaveType(balance.leave_type);
  if (language === 'bisaya') {
    return `Kung mag-file ka ug ${fmtDayCount(days)} nga ${type}, gikan sa ${fmtDays(
      available
    )} available mahimong ${fmtDays(after)} ang estimated balance. Balance estimate ra ni, dili pa approval.`;
  }
  if (language === 'tagalog') {
    return `Kung mag-file ka ng ${fmtDayCount(days)} na ${type}, mula ${fmtDays(
      available
    )} available magiging ${fmtDays(after)} ang estimated balance. Estimate lang ito, hindi pa approval.`;
  }
  return `If you file ${fmtDayCount(days)} of ${type}, your estimated balance would go from ${fmtDays(
    available
  )} to ${fmtDays(after)}. This is only an estimate, not approval.`;
}

function leaveRequestSummaryReply(context, message) {
  const language = languageOf(message);
  const useRange = hasDateRangeHint(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (useRange && !requestOverlapsRange(request, context.date_range)) return false;
    return true;
  });

  if (requests.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave requests para ana nga period.';
    if (language === 'tagalog') return 'Wala akong nakitang leave requests para sa period na iyon.';
    return 'I found no leave requests for that period.';
  }

  const counts = requests.reduce(
    (acc, request) => {
      if (pendingStatus(request.status)) acc.pending += 1;
      else if (approvedStatus(request.status)) acc.approved += 1;
      else if (rejectedStatus(request.status)) acc.rejected += 1;
      else acc.other += 1;
      acc.days += asNumber(request.days) || 0;
      return acc;
    },
    { pending: 0, approved: 0, rejected: 0, other: 0, days: 0 }
  );

  const label = useRange ? context.date_range?.label || 'selected period' : 'recent records';
  return structuredReply(language, {
    title: `Leave summary (${label})`,
    summary: `I found ${requests.length} leave ${plural(requests.length, 'request')}, total ${fmtDayCount(counts.days)}.`,
    details: [
      `Pending: ${counts.pending}`,
      `Approved: ${counts.approved}`,
      `Rejected: ${counts.rejected}`,
      `Other: ${counts.other}`,
    ],
  });
}

function leaveRequestLookupReply(context, message) {
  const language = languageOf(message);
  const useRange = hasDateRangeHint(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (useRange && !requestOverlapsRange(request, context.date_range)) return false;
    return requestMatchesMessageFilters(request, message, context);
  });

  if (requests.length === 0) {
    const label = context.date_range?.label || 'that date';
    if (language === 'bisaya') return `Wala koy nakitang leave request nga gi-file para sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang leave request na na-file para sa ${label}.`;
    return `I found no leave request filed for ${label}.`;
  }

  const lines = limitedRequests(requests, 3).map((request) => {
    return `${labelLeaveType(request.leave_type)} (${workflowStatusText(
      request.status
    )}, ${fmtDayCount(request.days)}, ${fmtFriendlyDateRange(request.start_date, request.end_date).replace(
      /^on /,
      ''
    )})`;
  });
  const more = requests.length > 3 ? ` plus ${requests.length - 3} more` : '';
  const label = context.date_range?.label || 'that date';

  return structuredReply(language, {
    title: `Leave request for ${label}`,
    summary: `I found ${requests.length} matching leave ${plural(requests.length, 'request')}.`,
    details: [...lines, ...(more ? [more.trim()] : [])],
    limit: 4,
  });
}

function leaveRejectionReasonReply(context, message) {
  const language = languageOf(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (!requestMatchesMessageFilters(request, message, context)) return false;
    return rejectedStatus(request.status) || returnedStatus(request.status);
  });
  const request = requests[0] || (context.recent_leave_requests || []).find((r) => rejectedStatus(r.status) || returnedStatus(r.status));

  if (!request) {
    if (language === 'bisaya') return 'Wala koy nakitang rejected or returned leave request sa recent records mo.';
    if (language === 'tagalog') return 'Wala akong nakitang rejected or returned leave request sa recent records mo.';
    return 'I found no rejected or returned leave request in your recent records.';
  }

  const reason = firstReviewReason(request);
  const base = `${fmtLeaveRequest(request)}`;
  if (!reason) {
    return structuredReply(language, {
      title: 'Leave rejection reason',
      summary: base,
      details: ['No reviewer remarks or reason were found in the record.'],
    });
  }
  const cleanReason = String(reason).replace(/[.\s]+$/, '');
  return structuredReply(language, {
    title: 'Leave rejection reason',
    summary: base,
    details: [`Remarks: ${cleanReason}`],
  });
}

function leaveApprovalTrackerReply(context, message) {
  const language = languageOf(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (!requestMatchesMessageFilters(request, message, context)) return false;
    return pendingStatus(request.status) || returnedStatus(request.status) || approvedStatus(request.status);
  });
  const request = requests[0] || context.recent_leave_requests?.[0];

  if (!request) {
    if (language === 'bisaya') return 'Wala koy nakitang leave request nga i-track sa recent records mo.';
    if (language === 'tagalog') return 'Wala akong nakitang leave request na puwedeng i-track sa recent records mo.';
    return 'I found no leave request to track in your recent records.';
  }

  const status = String(request.status || '').toLowerCase();
  let owner = workflowStatusText(status);
  if (status === 'pending_department_head') owner = 'currently waiting for department head review';
  if (status === 'pending_hr' || status === 'pending') owner = 'currently waiting for HR final review';
  if (status === 'approved') owner = 'already approved';
  if (status === 'returned') owner = 'returned to you for correction';
  if (rejectedStatus(status)) owner = 'already rejected';

  const actor = request.reviewer_name || request.approver_name || request.latest_history?.actor_name;
  const actorText = actor ? ` Last action/reviewer: ${actor}.` : '';
  const remarks = firstReviewReason(request);
  const remarksText = remarks ? ` Remarks: ${remarks}.` : '';
  const content = `${labelLeaveType(request.leave_type)} ${fmtFriendlyDateRange(
    request.start_date,
    request.end_date
  )} is ${owner}.${actorText}${remarksText}`;

  if (language === 'bisaya') return content;
  if (language === 'tagalog') return content;
  return content;
}

function leaveApprovalHistoryReply(context, message) {
  const language = languageOf(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    return requestMatchesMessageFilters(request, message, context);
  });
  const request = requests[0] || context.recent_leave_requests?.[0];

  if (!request) {
    if (language === 'bisaya') return 'Wala koy nakitang leave request para sa approval timeline.';
    if (language === 'tagalog') return 'Wala akong nakitang leave request para sa approval timeline.';
    return 'I found no leave request for an approval timeline.';
  }

  const history = Array.isArray(request.history) ? request.history : [];
  if (history.length === 0 && !request.latest_history) {
    const base = fmtLeaveRequest(request);
    if (language === 'bisaya') return `${base}. Wala koy detailed approval history sa record.`;
    if (language === 'tagalog') return `${base}. Wala akong detailed approval history sa record.`;
    return `${base}. I found no detailed approval history in the record.`;
  }

  const events = history.length > 0 ? history : [request.latest_history];
  const lines = limitedRequests(events, 6).map((event) => {
    const action = statusLabel(event.action || event.to_status || 'action');
    const actor = event.actor_name ? ` by ${event.actor_name}` : '';
    const when = event.acted_at ? ` on ${fmtFriendlyDate(event.acted_at)}` : '';
    const remarks = event.remarks ? ` (${event.remarks})` : '';
    return `${action}${actor}${when}${remarks}`;
  });
  const more = events.length > 6 ? ` plus ${events.length - 6} more` : '';
  const base = fmtLeaveRequest(request);

  return structuredReply(language, {
    title: 'Approval timeline',
    summary: base,
    details: [...lines, ...(more ? [more.trim()] : [])],
    limit: 7,
  });
}

function locatorSlots(slip) {
  const slots = [];
  if (slip?.coverage?.am_in) slots.push('AM in');
  if (slip?.coverage?.am_out) slots.push('AM out');
  if (slip?.coverage?.pm_in) slots.push('PM in');
  if (slip?.coverage?.pm_out) slots.push('PM out');
  return slots;
}

function locatorStatusText(status) {
  const value = lower(status);
  if (value === 'pending_department_head') return 'waiting for department head review';
  if (value === 'pending_hr' || value === 'pending') return 'waiting for HR review';
  if (value === 'approved') return 'approved by HR';
  if (value === 'rejected_by_department_head') return 'rejected by department head';
  if (value === 'rejected_by_hr' || value === 'rejected') return 'rejected by HR';
  if (value === 'cancelled' || value === 'canceled') return 'cancelled';
  return statusLabel(status);
}

function requestedLocatorType(message) {
  const text = lower(message);
  if (/\b(wfh|work from home|home)\b/.test(text)) return 'work_from_home';
  if (/\b(pass slip|pass-slip|passslip)\b/.test(text)) return 'pass_slip';
  if (/\b(official business|official|business|ob|on field|field|fieldwork|field work|out of office|outside office|travel order|locator)\b/.test(text)) return 'locator';
  return null;
}

function locatorTypeMatches(item, requestedType) {
  if (!requestedType) return true;
  const code = lower(item?.request_type || item?.code);
  const label = lower(item?.request_type_label || item?.label);
  if (requestedType === 'locator') {
    return (
      code === 'locator' ||
      code === 'official_business' ||
      code === 'official business' ||
      label.includes('locator') ||
      label.includes('official business') ||
      label.includes('on field')
    );
  }
  return (
    code === requestedType ||
    label.includes(requestedType.replace(/_/g, ' '))
  );
}

function requestedLocatorStatus(message) {
  const text = lower(message);
  if (/\b(pending|waiting|awaiting|hold|holding|asa|where|kinsa|sino)\b/.test(text)) return 'pending';
  if (/\b(approved|approve|na-approve)\b/.test(text)) return 'approved';
  if (/\b(rejected|reject|declined|denied|gi reject|gireject|not approved|wala.*approve|dili.*approved|hindi.*approved)\b/.test(text)) return 'rejected';
  if (/\b(cancelled|canceled|cancel)\b/.test(text)) return 'cancelled';
  return null;
}

function locatorStatusMatches(status, requested) {
  if (!requested) return true;
  const value = lower(status);
  if (requested === 'pending') return value === 'pending' || value === 'pending_department_head' || value === 'pending_hr';
  if (requested === 'approved') return value === 'approved';
  if (requested === 'rejected') return value === 'rejected' || value === 'rejected_by_department_head' || value === 'rejected_by_hr';
  if (requested === 'cancelled') return value === 'cancelled' || value === 'canceled';
  return true;
}

function locatorSlipsForMessage(context, message) {
  const range = context.date_range || {};
  const useRange = hasDateRangeHint(message);
  const requestedType = requestedLocatorType(message);
  const requestedStatus = requestedLocatorStatus(message);
  return (context.recent_locator_slips || []).filter((slip) => {
    if (useRange && range.startDate && range.endDate) {
      if (slip.slip_date < range.startDate || slip.slip_date > range.endDate) return false;
    }
    if (!locatorTypeMatches(slip, requestedType)) return false;
    if (!locatorStatusMatches(slip.status, requestedStatus)) return false;
    return true;
  });
}

function fmtLocatorSlip(slip) {
  const slots = locatorSlots(slip);
  const type = slip.request_type_label || slip.request_type || 'Locator';
  const place = slip.office ? `, ${slip.office}` : '';
  const attachment = slip.has_attachment ? ', with attachment' : '';
  return `${type} on ${fmtFriendlyDate(slip.slip_date)} - ${locatorStatusText(slip.status)}${
    slots.length > 0 ? `, covering ${slots.join(', ')}` : ''
  }${place}${attachment}`;
}

function locatorRemarks(slip) {
  return slip.hr_remarks || slip.dept_head_remarks || null;
}

function locatorReply(context, localized, message = '') {
  const language = languageOf(message);
  const slips = locatorSlipsForMessage(context, message);
  const slip = slips[0] || context.recent_locator_slips?.[0];
  if (!slip) {
    if (language === 'bisaya') return 'Wala koy nakitang locator slip records sa imong account.';
    if (language === 'tagalog' || localized) return 'Wala akong nakitang locator slip records para sa account mo.';
    return 'I found no locator slip records for your account.';
  }

  const remarks = locatorRemarks(slip);
  const details = [
    `Status: ${locatorStatusText(slip.status)}`,
    `Date: ${fmtFriendlyDate(slip.slip_date)}`,
    `Type: ${slip.request_type_label || slip.request_type || 'Locator'}`,
    locatorSlots(slip).length > 0 ? `Coverage: ${locatorSlots(slip).join(', ')}` : null,
    slip.office ? `${slip.request_type_location_label || 'Location'}: ${slip.office}` : null,
    slip.reason ? `Reason: ${slip.reason}` : null,
    slip.dept_head_reviewer_name ? `Department head reviewer: ${slip.dept_head_reviewer_name}` : null,
    slip.hr_reviewer_name ? `HR reviewer: ${slip.hr_reviewer_name}` : null,
    remarks ? `Remarks: ${remarks}` : null,
  ];
  const title = language === 'bisaya' ? 'Locator status' : language === 'tagalog' ? 'Status ng locator' : 'Locator status';
  const summary =
    language === 'bisaya'
      ? `Ang locator request nimo kay ${locatorStatusText(slip.status)}.`
      : language === 'tagalog'
        ? `Ang locator request mo ay ${locatorStatusText(slip.status)}.`
        : `Your locator request is ${locatorStatusText(slip.status)}.`;
  return structuredReply(language, {
    title,
    summary,
    details,
    nextStep: lower(slip.status).startsWith('pending')
      ? language === 'bisaya'
        ? 'Hulat sa review, or i-check kung naa bay remarks/attachment nga kinahanglan.'
        : language === 'tagalog'
          ? 'Hintayin ang review, o i-check kung may remarks/attachment na kailangan.'
          : 'Wait for review, or check if remarks/attachment are needed.'
      : null,
    limit: 9,
  });
}

function locatorSummaryReply(context, message) {
  const language = languageOf(message);
  const slips = locatorSlipsForMessage(context, message);
  const label = hasDateRangeHint(message) ? context.date_range?.label || 'selected period' : 'recent records';
  if (slips.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang locator slip para sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang locator slip para sa ${label}.`;
    return `I found no locator slips for ${label}.`;
  }
  const counts = slips.reduce(
    (acc, slip) => {
      const status = lower(slip.status);
      if (status === 'approved') acc.approved += 1;
      else if (status === 'pending' || status === 'pending_department_head' || status === 'pending_hr') acc.pending += 1;
      else if (status === 'rejected' || status === 'rejected_by_department_head' || status === 'rejected_by_hr') acc.rejected += 1;
      else if (status === 'cancelled' || status === 'canceled') acc.cancelled += 1;
      else acc.other += 1;
      return acc;
    },
    { pending: 0, approved: 0, rejected: 0, cancelled: 0, other: 0 }
  );
  const lines = limitedRequests(slips, 6).map(fmtLocatorSlip);
  const summary =
    language === 'bisaya'
      ? `Nakita nako ang ${slips.length} ka locator slip para sa ${label}.`
      : language === 'tagalog'
        ? `May nakita akong ${slips.length} locator slip para sa ${label}.`
        : `I found ${slips.length} locator ${plural(slips.length, 'slip')} for ${label}.`;
  return structuredReply(language, {
    title: `Locator summary (${label})`,
    summary,
    details: [
      `Pending: ${counts.pending}`,
      `Approved: ${counts.approved}`,
      `Rejected: ${counts.rejected}`,
      `Cancelled: ${counts.cancelled}`,
      ...lines,
    ],
    limit: 10,
  });
}

function locatorRequirementsReply(context, message) {
  const language = languageOf(message);
  const requestedType = requestedLocatorType(message);
  const types = (context.locator_types || []).filter((type) => locatorTypeMatches(type, requestedType));
  const visible = types.length > 0 ? types : context.locator_types || [];
  if (visible.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang locator request type rules sa system.';
    if (language === 'tagalog') return 'Wala akong nakitang locator request type rules sa system.';
    return 'I found no locator request type rules in the system.';
  }
  const lines = visible.map((type) => {
    const coverage =
      type.coverage_mode === 'wfh'
        ? 'auto WFH coverage'
        : 'manual AM/PM slot selection';
    return `${type.label || type.code}: ${type.requires_attachment ? 'attachment required' : 'no attachment required'}, ${coverage}, DTR label ${type.dtr_slot_label || type.dtr_print_label || type.code}`;
  });
  const summary =
    language === 'bisaya'
      ? 'Base sa locator type setup, mao ni ang filing rules.'
      : language === 'tagalog'
        ? 'Base sa locator type setup, ito ang filing rules.'
        : 'Based on the locator type setup, these are the filing rules.';
  return structuredReply(language, {
    title: 'Locator filing requirements',
    summary,
    details: [
      ...lines,
      'You need a valid working-day schedule for the slip date.',
      'Choose at least one covered slot: AM in, AM out, PM in, or PM out.',
      'Office/destination and reason are required.',
    ],
    nextStep:
      language === 'bisaya'
        ? 'Kung rejected or pending imong locator, ask me about its status or remarks.'
        : language === 'tagalog'
          ? 'Kung rejected or pending ang locator mo, tanungin mo ako tungkol sa status o remarks.'
          : 'If your locator is rejected or pending, ask me about its status or remarks.',
    limit: 9,
  });
}

function locatorTypeRulesForMessage(context, message) {
  const requestedType = requestedLocatorType(message);
  const types = context.locator_types || [];
  const matches = types.filter((type) => locatorTypeMatches(type, requestedType));
  return matches.length > 0 ? matches : requestedType ? [] : types;
}

function locatorAvailabilityReply(context, message) {
  const language = languageOf(message);
  const range = context.date_range || {};
  const date = range.startDate || range.endDate || null;
  const day = date ? calendarDayForDate(context, date) : null;
  const type = locatorTypeRulesForMessage(context, message)[0] || null;
  const requestedSlot = requestedDtrSlot(message);
  const requestedType = requestedLocatorType(message);
  const existing = (context.recent_locator_slips || []).filter((slip) => {
    if (date && slip.slip_date !== date) return false;
    return locatorTypeMatches(slip, requestedType);
  });
  const issues = [];
  if (!date) issues.push('No target date was detected.');
  if (day?.holiday_name && day.holiday_coverage === 'whole_day') {
    issues.push(`Date is marked as whole-day holiday: ${day.holiday_name}`);
  }
  if (day && !isCalendarWorkingDay(day)) {
    issues.push('Schedule says this is not a required-log working day.');
  }
  if (!day && date) {
    issues.push('Schedule details are not loaded for this date.');
  }

  const typeLabel = type?.label || type?.code || (requestedType ? requestedType.replace(/_/g, ' ') : 'not selected');
  const details = [
    date ? `Date: ${fmtFriendlyDate(date)}` : null,
    `Locator type: ${typeLabel}`,
    day?.shift_name
      ? `Schedule: ${day.shift_name}${fmtScheduleRange(day) ? ` (${fmtScheduleRange(day)})` : ''}`
      : null,
    day?.holiday_name ? `Holiday: ${day.holiday_name} (${day.holiday_coverage || 'whole_day'})` : null,
    requestedSlot
      ? `Requested DTR coverage: ${requestedSlot}`
      : 'DTR coverage: choose AM in, AM out, PM in, or PM out.',
    type
      ? `Attachment: ${type.requires_attachment ? 'required' : 'not required by this locator type'}`
      : 'Type rules: choose the exact locator type to check attachment rules.',
    existing.length > 0
      ? `Existing locator on this date: ${existing.map(fmtLocatorSlip).join('; ')}`
      : null,
    ...issues,
  ];
  const hasBlockingIssue = issues.some((issue) => !issue.includes('not loaded'));
  const title =
    language === 'bisaya'
      ? 'Locator filing check'
      : language === 'tagalog'
        ? 'Locator filing check'
        : 'Locator filing check';
  const summary =
    hasBlockingIssue
      ? language === 'bisaya'
        ? 'Naay issue sa initial locator check. Tan-awa ang detalye sa ubos.'
        : language === 'tagalog'
          ? 'May issue sa initial locator check. Tingnan ang detalye sa baba.'
          : 'The initial locator filing check found an issue.'
      : language === 'bisaya'
        ? 'Initial check: murag pwede ka mag-file, basta kompleto ang type, slots, destination, reason, ug required attachment.'
        : language === 'tagalog'
          ? 'Initial check: mukhang puwede kang mag-file kung kumpleto ang type, slots, destination, reason, at required attachment.'
          : 'Initial check: you can file if the type, slots, destination, reason, and required attachment are complete.';
  return structuredReply(language, {
    title,
    summary,
    details,
    nextStep:
      language === 'bisaya'
        ? 'Submit gihapon sa normal approval workflow; dili pa ni final approval.'
        : language === 'tagalog'
          ? 'I-submit pa rin sa normal approval workflow; hindi pa ito final approval.'
          : 'Submit it through the normal approval workflow; this is not final approval.',
    limit: 10,
  });
}

function locatorRejectionReasonReply(context, message) {
  const language = languageOf(message);
  const slips = locatorSlipsForMessage(context, message);
  const slip =
    slips.find((item) => rejectedStatus(item.status)) ||
    (context.recent_locator_slips || []).find((item) => rejectedStatus(item.status));
  if (!slip) {
    if (language === 'bisaya') return 'Wala koy nakitang rejected locator slip sa imong recent records.';
    if (language === 'tagalog') return 'Wala akong nakitang rejected locator slip sa recent records mo.';
    return 'I found no rejected locator slip in your recent records.';
  }
  const rejectedBy = /department_head/.test(lower(slip.status))
    ? 'department head'
    : /hr/.test(lower(slip.status))
      ? 'HR'
      : 'reviewer';
  const remarks = locatorRemarks(slip);
  const summary =
    language === 'bisaya'
      ? `Gi-reject ang locator request nimo ${fmtLocalizedDateRange(slip.slip_date, slip.slip_date, language)}.`
      : language === 'tagalog'
        ? `Na-reject ang locator request mo ${fmtLocalizedDateRange(slip.slip_date, slip.slip_date, language)}.`
        : `Your locator request ${fmtLocalizedDateRange(slip.slip_date, slip.slip_date, language)} was rejected.`;
  return structuredReply(language, {
    title: 'Locator rejection reason',
    summary,
    details: [
      fmtLocatorSlip(slip),
      `Rejected by: ${rejectedBy}`,
      remarks ? `Remarks: ${remarks}` : 'Remarks: no rejection remarks saved in the record.',
      slip.dept_head_reviewer_name ? `Department head reviewer: ${slip.dept_head_reviewer_name}` : null,
      slip.hr_reviewer_name ? `HR reviewer: ${slip.hr_reviewer_name}` : null,
    ],
    nextStep:
      language === 'bisaya'
        ? 'Kung kulang ang remarks, i-check sa reviewer or HR unsay kinahanglan usbon.'
        : language === 'tagalog'
          ? 'Kung kulang ang remarks, i-check sa reviewer o HR kung ano ang kailangang ayusin.'
          : 'If the remarks are not enough, check with the reviewer or HR what needs to be corrected.',
    limit: 7,
  });
}

function locatorApprovalOwner(slip) {
  const status = lower(slip?.status);
  if (status === 'pending_department_head') {
    return slip.dept_head_reviewer_name
      ? `department head (${slip.dept_head_reviewer_name})`
      : 'department head review';
  }
  if (status === 'pending_hr' || status === 'pending') {
    return slip.hr_reviewer_name ? `HR (${slip.hr_reviewer_name})` : 'HR review';
  }
  if (status === 'approved') {
    return slip.hr_reviewer_name ? `completed by HR (${slip.hr_reviewer_name})` : 'completed by HR';
  }
  if (/department_head/.test(status)) {
    return slip.dept_head_reviewer_name
      ? `department head (${slip.dept_head_reviewer_name})`
      : 'department head';
  }
  if (/hr/.test(status)) {
    return slip.hr_reviewer_name ? `HR (${slip.hr_reviewer_name})` : 'HR';
  }
  return 'reviewer';
}

function locatorApprovalTrackerReply(context, message) {
  const language = languageOf(message);
  const slips = locatorSlipsForMessage(context, message);
  const slip = slips.find((item) => pendingStatus(item.status)) || slips[0] || context.recent_locator_slips?.[0];
  if (!slip) {
    if (language === 'bisaya') return 'Wala koy nakitang locator slip nga ma-track sa imong account.';
    if (language === 'tagalog') return 'Wala akong nakitang locator slip na puwedeng i-track sa account mo.';
    return 'I found no locator slip to track for your account.';
  }
  const owner = locatorApprovalOwner(slip);
  const status = locatorStatusText(slip.status);
  const summary =
    pendingStatus(slip.status)
      ? language === 'bisaya'
        ? `Pending pa ang locator request nimo. Naa siya sa ${owner}.`
        : language === 'tagalog'
          ? `Pending pa ang locator request mo. Nasa ${owner} siya.`
          : `Your locator request is still pending with ${owner}.`
      : language === 'bisaya'
        ? `Dili na pending ang locator request nimo; status niya kay ${status}.`
        : language === 'tagalog'
          ? `Hindi na pending ang locator request mo; status nito ay ${status}.`
          : `Your locator request is no longer pending; its status is ${status}.`;
  return structuredReply(language, {
    title: 'Locator approval tracker',
    summary,
    details: [
      fmtLocatorSlip(slip),
      `Current step: ${owner}`,
      slip.created_at ? `Filed: ${fmtFriendlyDate(slip.created_at)}` : null,
      slip.dept_head_reviewed_at ? `Department head reviewed: ${fmtFriendlyDate(slip.dept_head_reviewed_at)}` : null,
      slip.hr_reviewed_at ? `HR reviewed: ${fmtFriendlyDate(slip.hr_reviewed_at)}` : null,
      locatorRemarks(slip) ? `Remarks: ${locatorRemarks(slip)}` : null,
    ],
    nextStep:
      pendingStatus(slip.status)
        ? language === 'bisaya'
          ? 'Kung dugay na pending, i-follow up sa current reviewer.'
          : language === 'tagalog'
            ? 'Kung matagal nang pending, i-follow up sa current reviewer.'
            : 'If it has been pending for a while, follow up with the current reviewer.'
        : null,
    limit: 8,
  });
}

function buildFastEmployeeAssistantReply(message, context, intent) {
  const text = lower(message);
  const localized = isTagalogOrBisaya(message);

  if (intent === 'today_dtr') {
    return dtrDailyRecordReply(context, message);
  }
  if (intent === 'missing_logs') {
    return dtrMissingLogsReply(context, message);
  }
  if (intent === 'dtr_daily_record') {
    return dtrDailyRecordReply(context, message);
  }
  if (intent === 'dtr_range_summary') {
    return dtrRangeSummaryReply(context, message);
  }
  if (intent === 'dtr_missing_logs') {
    return dtrMissingLogsReply(context, message);
  }
  if (intent === 'dtr_missing_log_reason') {
    return dtrMissingLogsReply(context, message, true);
  }
  if (intent === 'dtr_late_summary') {
    return dtrMinuteSummaryReply(context, message, 'late');
  }
  if (intent === 'dtr_late_reason') {
    return dtrLateReasonReply(context, message);
  }
  if (intent === 'dtr_undertime_summary') {
    return dtrMinuteSummaryReply(context, message, 'undertime');
  }
  if (intent === 'dtr_overtime_summary') {
    return dtrMinuteSummaryReply(context, message, 'overtime');
  }
  if (intent === 'dtr_absent_summary') {
    return dtrAbsentSummaryReply(context, message);
  }
  if (intent === 'dtr_status_explanation') {
    return dtrStatusExplanationReply(context, message);
  }
  if (intent === 'dtr_correction_guidance') {
    return dtrCorrectionGuidanceReply(context, message);
  }
  if (intent === 'dtr_leave_coverage_check') {
    return dtrLeaveCoverageReply(context, message);
  }
  if (intent === 'dtr_locator_coverage_check') {
    return dtrLocatorCoverageReply(context, message);
  }
  if (intent === 'dtr_holiday_check') {
    return dtrHolidayReply(context, message);
  }
  if (intent === 'dtr_schedule_context') {
    return dtrScheduleContextReply(context, message);
  }
  if (intent === 'dtr_export_guidance') {
    return dtrExportGuidanceReply(context, message);
  }
  if (intent === 'leave_balance') {
    return leaveBalanceReply(context, localized, message);
  }
  if (intent === 'latest_leave_request') {
    return latestLeaveReply(context, localized);
  }
  if (intent === 'pending_leave_requests') {
    return leaveRequestsByStatusReply(context, message, pendingStatus, {
      bisaya: 'pending',
      tagalog: 'pending',
      english: 'pending',
    });
  }
  if (intent === 'approved_leave_requests') {
    return leaveRequestsByStatusReply(context, message, approvedStatus, {
      bisaya: 'approved',
      tagalog: 'approved',
      english: 'approved',
    });
  }
  if (intent === 'rejected_leave_requests') {
    return leaveRequestsByStatusReply(context, message, rejectedStatus, {
      bisaya: 'rejected',
      tagalog: 'rejected',
      english: 'rejected',
    });
  }
  if (intent === 'leave_history') {
    return leaveHistoryReply(context, message);
  }
  if (intent === 'leave_availability_check') {
    return leaveAvailabilityReply(context, message);
  }
  if (intent === 'leave_attachment_requirement') {
    return leaveAttachmentRequirementReply(context, message);
  }
  if (intent === 'leave_overlap_check') {
    return leaveOverlapCheckReply(context, message);
  }
  if (intent === 'leave_pending_days_explanation') {
    return leavePendingDaysExplanationReply(context, message);
  }
  if (intent === 'leave_balance_after_filing') {
    return leaveBalanceAfterFilingReply(context, message);
  }
  if (intent === 'leave_request_summary') {
    return leaveRequestSummaryReply(context, message);
  }
  if (intent === 'leave_request_lookup') {
    return leaveRequestLookupReply(context, message);
  }
  if (intent === 'leave_filing_policy') {
    return leaveFilingPolicyReply(context, message);
  }
  if (intent === 'leave_form_guidance') {
    return leaveFormGuidanceReply(context, message);
  }
  if (intent === 'leave_eligibility_check') {
    return leaveEligibilityReply(context, message);
  }
  if (intent === 'leave_dtr_impact') {
    return leaveDtrImpactReply(context, message);
  }
  if (intent === 'leave_guideline_section') {
    return leaveGuidelineSectionReply(context, message);
  }
  if (intent === 'leave_type_compare') {
    return leaveTypeCompareReply(context, message);
  }
  if (intent === 'leave_guided_filing') {
    return leaveGuidedFilingReply(context, message);
  }
  if (intent === 'leave_rejection_reason') {
    return leaveRejectionReasonReply(context, message);
  }
  if (intent === 'leave_approval_tracker') {
    return leaveApprovalTrackerReply(context, message);
  }
  if (intent === 'leave_approval_history') {
    return leaveApprovalHistoryReply(context, message);
  }
  if (intent === 'leave_types') {
    return leaveTypesReply(context, message);
  }
  if (intent === 'leave_requirements') {
    return leaveRequirementsReply(context, message);
  }
  if (intent === 'latest_locator_request') {
    return locatorReply(context, localized, message);
  }
  if (intent === 'locator_status') {
    return locatorReply(context, localized, message);
  }
  if (intent === 'locator_summary') {
    return locatorSummaryReply(context, message);
  }
  if (intent === 'locator_requirements') {
    return locatorRequirementsReply(context, message);
  }
  if (intent === 'locator_availability_check') {
    return locatorAvailabilityReply(context, message);
  }
  if (intent === 'locator_rejection_reason') {
    return locatorRejectionReasonReply(context, message);
  }
  if (intent === 'locator_approval_tracker') {
    return locatorApprovalTrackerReply(context, message);
  }

  if (/\b(dtr|attendance|late|time[\s-]?in|time[\s-]?out)\b/.test(text)) {
    if (/\b(today|karon|ngayon|status|late)\b/.test(text)) {
      return dtrDailyRecordReply(context, message);
    }
  }

  return null;
}

module.exports = { buildFastEmployeeAssistantReply, requestedLeaveType };
