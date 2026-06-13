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

function asNumber(value) {
  if (value == null || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function statusLabel(value) {
  return String(value || 'unknown').replace(/_/g, ' ');
}

function isTagalogOrBisaya(message) {
  const text = lower(message);
  return /\b(ano|ba|ko|akong|ngano|unsa|unsay|karon|ngayon|kumusta|pila|naa|wala|na-approve)\b/.test(
    text
  );
}

function languageOf(message) {
  const text = lower(message);
  if (/\b(ngano|unsa|unsay|unsa'y|karon|pila|naa|akong|nako|nabilin|gamay|kuwang|imong|nimo|gikan|mahimong|adlaw|kinahanglan|ug|kay)\b/.test(text)) {
    return 'bisaya';
  }
  if (/\b(ano|ngayon|ako|ko|ba|may|wala|ilan|bakit|maliit|natira|kailangan)\b/.test(text)) {
    return 'tagalog';
  }
  return 'english';
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

function requestedLeaveTypeRecord(message, context) {
  const type = requestedLeaveType(message);
  if (type) {
    return (context.leave_types || []).find((record) => leaveTypeRecordMatches(record, type)) || null;
  }
  return inferLeaveTypeFromRecords(message, context.leave_types || []);
}

function isWhyBalanceQuestion(message) {
  const text = lower(message);
  return /\b(why|ngano|bakit|gamay|small|low|maliit|nabilin|natira|remaining)\b/.test(
    text
  );
}

function hasDateRangeHint(message) {
  const text = lower(message);
  return /\b(today|yesterday|week|month|last month|this month|last week|this week|\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b/.test(
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
  return /^(rejected|rejected_by_department_head|rejected_by_hr|declined|denied)$/i.test(
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
  const days = request.days != null ? `, ${fmtDays(request.days)} day(s)` : '';
  return `${labelLeaveType(request.leave_type)} ${fmtDate(request.start_date)} to ${fmtDate(
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
      ? `attachment required because requested days reach ${fmtDays(threshold)} day(s)`
      : `attachment required when filing ${fmtDays(threshold)} day(s) or more`;
  }
  return type.requires_attachment ? 'attachment required' : 'no attachment required';
}

function workflowStatusText(status) {
  const value = String(status || '').toLowerCase();
  if (value === 'pending_department_head') return 'waiting for department head review';
  if (value === 'pending_hr' || value === 'pending') return 'waiting for HR final review';
  if (value === 'approved') return 'approved by HR';
  if (value === 'returned') return 'returned for correction';
  if (value === 'rejected_by_department_head') return 'rejected by department head';
  if (value === 'rejected_by_hr' || value === 'rejected') return 'rejected by HR';
  if (value === 'draft') return 'still in draft';
  if (value === 'cancelled') return 'cancelled';
  return statusLabel(status);
}

function firstReviewReason(request) {
  const details = request?.details || {};
  return (
    request?.reviewer_remarks ||
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
    return `${labelLeaveType(b.leave_type)}: available ${fmtDays(
      b.available_days
    )}, remaining ${fmtDays(
      b.remaining_days
    )}, pending ${fmtDays(b.pending_days)}`;
  });

  if (language === 'bisaya') {
    return `Mao ni imong leave balance: ${lines.join('; ')}.`;
  }
  if (language === 'tagalog') {
    return `Ito ang leave balance mo: ${lines.join('; ')}.`;
  }
  return `Here are your leave balances: ${lines.join('; ')}.`;
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
  )} to ${fmtDate(request.end_date)} is ${workflowStatusText(request.status)}`;
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

  const lines = limitedRequests(requests).map(fmtLeaveRequest).join('; ');
  const more = requests.length > 5 ? ` plus ${requests.length - 5} more` : '';
  if (language === 'bisaya') {
    return `Naa kay ${requests.length} ${labels.bisaya} leave request(s): ${lines}${more}.`;
  }
  if (language === 'tagalog') {
    return `May ${requests.length} ${labels.tagalog} leave request(s): ${lines}${more}.`;
  }
  return `You have ${requests.length} ${labels.english} leave request(s): ${lines}${more}.`;
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
  const lines = limitedRequests(requests).map(fmtLeaveRequest).join('; ');
  const more = requests.length > 5 ? ` plus ${requests.length - 5} more` : '';
  if (language === 'bisaya') {
    return `Mao ni imong leave history (${label}): ${lines}${more}.`;
  }
  if (language === 'tagalog') {
    return `Ito ang leave history mo (${label}): ${lines}${more}.`;
  }
  return `Here is your leave history (${label}): ${lines}${more}.`;
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
      warnings.push(`needs ${fmtDays(advanceDays)} calendar day(s) advance notice`);
    }
  }
  const maxDays = asNumber(requestedRecord?.max_days);
  if (maxDays != null && days > maxDays) {
    blockers.push(`max allowed is ${fmtDays(maxDays)} day(s)`);
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
      blockers.push(`overlap found: ${limitedRequests(overlaps, 2).map(fmtLeaveRequest).join('; ')}`);
    }
  }
  const warningText = warnings.length > 0 ? ` Warning: ${warnings.join('; ')}.` : '';
  const blockerText = blockers.length > 0 ? ` Issue: ${blockers.join('; ')}.` : '';
  const noteText = notes.length > 0 ? ` Note: ${notes.join('; ')}.` : '';
  const baseBalanceEnglish =
    available == null
      ? `I could not verify a balance row for ${type}, but I checked the filing rules for ${fmtDays(days)} day(s)`
      : `you have ${fmtDays(available)} available ${type} for ${fmtDays(days)} day(s)`;
  const baseBalanceBisaya =
    available == null
      ? `wala koy matching balance row para sa ${type}, pero na-check nako ang filing rules para sa ${fmtDays(days)} day(s)`
      : `naa kay ${fmtDays(available)} available ${type} para sa ${fmtDays(days)} day(s)`;
  const baseBalanceTagalog =
    available == null
      ? `wala akong matching balance row para sa ${type}, pero na-check ko ang filing rules para sa ${fmtDays(days)} day(s)`
      : `may ${fmtDays(available)} available ${type} para sa ${fmtDays(days)} day(s)`;

  if (language === 'bisaya') {
    if (blockers.length > 0 || enough === false) {
      const balanceText =
        enough === false
          ? `dili igo ang balance: naa kay ${fmtDays(available)} available ${type}, pero ${fmtDays(days)} day(s) imong plano`
          : baseBalanceBisaya;
      return `Dili pa limpyo ang filing check: ${balanceText}.${blockerText}${warningText}${noteText} Final approval gihapon ang HR workflow.`;
    }
    return `Pwede sa initial filing check: ${baseBalanceBisaya}.${warningText}${noteText} Dili pa ni final approval.`;
  }
  if (language === 'tagalog') {
    if (blockers.length > 0 || enough === false) {
      const balanceText =
        enough === false
          ? `hindi sapat ang balance: may ${fmtDays(available)} available ${type}, pero ${fmtDays(days)} day(s) ang plano mo`
          : baseBalanceTagalog;
      return `May issue sa filing check: ${balanceText}.${blockerText}${warningText}${noteText} Dadaan pa rin ito sa HR approval workflow.`;
    }
    return `Puwede sa initial filing check: ${baseBalanceTagalog}.${warningText}${noteText} Hindi pa ito final approval.`;
  }
  if (blockers.length > 0 || enough === false) {
    const balanceText =
      enough === false
        ? `balance is not enough: you have ${fmtDays(available)} available ${type}, but plan to file ${fmtDays(days)} day(s)`
        : baseBalanceEnglish;
    return `Filing check found an issue: ${balanceText}.${blockerText}${warningText}${noteText} This still needs the normal HR approval workflow.`;
  }
  return `Initial filing check looks okay: ${baseBalanceEnglish}.${warningText}${noteText} This is not final approval yet.`;
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
    return `${labelLeaveType(type.display_name || type.name)}: ${leaveRequirementParts(type).join(
      ', '
    )}`;
  });

  if (language === 'bisaya') {
    return `Base sa leave type records, mao ni ang filing requirements: ${lines.join(
      '; '
    )}. Kung naa kay attachment or approval question, sundon gihapon ang actual HR review workflow.`;
  }
  if (language === 'tagalog') {
    return `Base sa leave type records, ito ang filing requirements: ${lines.join(
      '; '
    )}. Susundin pa rin ang actual HR review workflow para sa approval.`;
  }
  return `Based on the leave type records, these are the filing requirements: ${lines.join(
    '; '
  )}. Approval still follows the actual HR review workflow.`;
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
    parts.push(`${type.minimum_advance_days} day(s) advance notice`);
  }
  if (type.max_days != null) {
    parts.push(`max ${fmtDays(type.max_days)} day(s)`);
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
    return `${labelLeaveType(type.display_name || type.name)}: ${attachmentRuleText(type, days)}`;
  });

  if (language === 'bisaya') return `Base sa records: ${lines.join('; ')}.`;
  if (language === 'tagalog') return `Base sa records: ${lines.join('; ')}.`;
  return `Based on the records: ${lines.join('; ')}.`;
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
    return `${labelLeaveType(type.display_name || type.name)}: ${leaveRequirementParts(type).join(
      ', '
    )}`;
  });

  if (language === 'bisaya') {
    return `Mao ni ang leave filing policy base sa records: ${lines.join('; ')}. Ang approval moagi gihapon sa HR workflow.`;
  }
  if (language === 'tagalog') {
    return `Ito ang leave filing policy base sa records: ${lines.join('; ')}. Dadaan pa rin sa HR approval workflow.`;
  }
  return `Here is the leave filing policy from the records: ${lines.join('; ')}. Approval still follows the HR workflow.`;
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

  const lines = limitedRequests(overlaps).map(fmtLeaveRequest).join('; ');
  if (language === 'bisaya') return `Naa kay overlapping leave request: ${lines}.`;
  if (language === 'tagalog') return `May overlapping leave request ka: ${lines}.`;
  return `You have overlapping leave request(s): ${lines}.`;
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
    return `${labelLeaveType(b.leave_type)} pending ${fmtDays(b.pending_days)} day(s)`;
  });
  const requestLines = limitedRequests(pendingRequests, 4).map(fmtLeaveRequest);
  const details = [...balanceLines, ...requestLines].join('; ');

  if (language === 'bisaya') return `Mao ni ang source sa imong pending leave days: ${details}.`;
  if (language === 'tagalog') return `Ito ang source ng pending leave days mo: ${details}.`;
  return `Here is the source of your pending leave days: ${details}.`;
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
    return `Kung mag-file ka ug ${fmtDays(days)} day(s) nga ${type}, gikan sa ${fmtDays(
      available
    )} available mahimong ${fmtDays(after)} ang estimated balance. Balance estimate ra ni, dili pa approval.`;
  }
  if (language === 'tagalog') {
    return `Kung mag-file ka ng ${fmtDays(days)} day(s) na ${type}, mula ${fmtDays(
      available
    )} available magiging ${fmtDays(after)} ang estimated balance. Estimate lang ito, hindi pa approval.`;
  }
  return `If you file ${fmtDays(days)} day(s) of ${type}, your estimated balance would go from ${fmtDays(
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
  if (language === 'bisaya') {
    return `Leave summary (${label}): total ${requests.length}, pending ${counts.pending}, approved ${counts.approved}, rejected ${counts.rejected}, other ${counts.other}, total days ${fmtDays(counts.days)}.`;
  }
  if (language === 'tagalog') {
    return `Leave summary (${label}): total ${requests.length}, pending ${counts.pending}, approved ${counts.approved}, rejected ${counts.rejected}, other ${counts.other}, total days ${fmtDays(counts.days)}.`;
  }
  return `Leave summary (${label}): total ${requests.length}, pending ${counts.pending}, approved ${counts.approved}, rejected ${counts.rejected}, other ${counts.other}, total days ${fmtDays(counts.days)}.`;
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
    if (language === 'bisaya') return `${base}. Wala koy nakitang reviewer remarks or reason sa record.`;
    if (language === 'tagalog') return `${base}. Wala akong nakitang reviewer remarks or reason sa record.`;
    return `${base}. I found no reviewer remarks or reason in the record.`;
  }
  const cleanReason = String(reason).replace(/[.\s]+$/, '');
  if (language === 'bisaya') return `${base}. Reason/remarks: ${cleanReason}.`;
  if (language === 'tagalog') return `${base}. Reason/remarks: ${cleanReason}.`;
  return `${base}. Reason/remarks: ${cleanReason}.`;
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
  const content = `${labelLeaveType(request.leave_type)} ${fmtDate(request.start_date)} to ${fmtDate(
    request.end_date
  )} is ${owner}.${actorText}${remarksText}`;

  if (language === 'bisaya') return content;
  if (language === 'tagalog') return content;
  return content;
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
  if (intent === 'leave_filing_policy') {
    return leaveFilingPolicyReply(context, message);
  }
  if (intent === 'leave_rejection_reason') {
    return leaveRejectionReasonReply(context, message);
  }
  if (intent === 'leave_approval_tracker') {
    return leaveApprovalTrackerReply(context, message);
  }
  if (intent === 'leave_types') {
    return leaveTypesReply(context, message);
  }
  if (intent === 'leave_requirements') {
    return leaveRequirementsReply(context, message);
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

module.exports = { buildFastEmployeeAssistantReply, requestedLeaveType };
