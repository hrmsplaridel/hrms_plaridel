const crypto = require('crypto');

const EXTERNAL_AI_CONSENT_VERSION = '2026-09-02-v1';

function pick(source, fields) {
  if (!source || typeof source !== 'object') return null;
  const result = {};
  for (const field of fields) {
    if (source[field] !== undefined) result[field] = source[field];
  }
  return result;
}

function pickList(items, fields) {
  return (Array.isArray(items) ? items : [])
    .map((item) => pick(item, fields))
    .filter(Boolean);
}

const DATE_RANGE_FIELDS = ['label', 'startDate', 'endDate'];
const DTR_RECORD_FIELDS = [
  'attendance_date',
  'time_in',
  'break_out',
  'break_in',
  'time_out',
  'total_hours',
  'late_minutes',
  'undertime_minutes',
  'overtime_minutes',
  'status',
  'pm_status',
  'source',
  'holiday_name',
  'holiday_type',
  'leave_type',
];
const CALENDAR_DAY_FIELDS = [
  'attendance_date',
  'shift_name',
  'start_time',
  'end_time',
  'break_end',
  'punch_mode',
  'grace_period_minutes',
  'working_days',
  'holiday_name',
  'holiday_type',
  'holiday_coverage',
];
const LEAVE_BALANCE_FIELDS = [
  'leave_type',
  'earned_days',
  'used_days',
  'pending_days',
  'adjusted_days',
  'remaining_days',
  'available_days',
  'as_of_date',
  'last_accrual_date',
];
const LEAVE_REQUEST_FIELDS = [
  'leave_type',
  'leave_type_key',
  'start_date',
  'end_date',
  'days',
  'status',
  'has_attachment',
  'reviewed_at',
  'approved_at',
  'created_at',
  'updated_at',
];
const LEAVE_REVIEW_FIELDS = [
  ...LEAVE_REQUEST_FIELDS,
  'reviewer_name',
  'approver_name',
  'reviewer_remarks',
  'recommendation_remarks',
  'disapproval_reason',
  'latest_history',
];
const LEAVE_TYPE_FIELDS = [
  'name',
  'display_name',
  'description',
  'employee_can_file',
  'admin_only',
  'allows_past_dates',
  'requires_attachment',
  'requires_attachment_when_over_days',
  'max_days',
  'minimum_advance_days',
  'sex_eligibility',
  'affects_dtr_normally',
  'balance_ledger_type',
  'entitlement_basis',
  'employee_detail_schema',
];
const LOCATOR_SLIP_FIELDS = [
  'slip_date',
  'request_type',
  'request_type_label',
  'request_type_short_label',
  'dtr_slot_label',
  'dtr_print_label',
  'request_type_requires_attachment',
  'request_type_coverage_mode',
  'coverage',
  'status',
  'dept_head_reviewed_at',
  'hr_reviewed_at',
  'revoked_at',
  'month_end_reconciliation_required',
  'month_end_reconciled_at',
  'created_at',
  'updated_at',
];
const LOCATOR_REVIEW_FIELDS = [
  ...LOCATOR_SLIP_FIELDS,
  'dept_head_remarks',
  'hr_remarks',
  'dept_head_reviewer_name',
  'hr_reviewer_name',
  'revoked_by_name',
  'revocation_reason',
];
const LOCATOR_TYPE_FIELDS = [
  'code',
  'label',
  'short_label',
  'location_label',
  'location_hint',
  'dtr_slot_label',
  'dtr_print_label',
  'requires_attachment',
  'coverage_mode',
  'sort_order',
];

function dateRange(context) {
  return pick(context?.date_range, DATE_RANGE_FIELDS);
}

function dtrData(context, { records = true, calendar = true } = {}) {
  return {
    dateRange: dateRange(context),
    ...(records
      ? { records: pickList(context?.dtr_records, DTR_RECORD_FIELDS) }
      : {}),
    ...(calendar
      ? { calendarDays: pickList(context?.dtr_calendar_days, CALENDAR_DAY_FIELDS) }
      : {}),
  };
}

function leaveRequestData(context, { review = false } = {}) {
  return pickList(
    context?.recent_leave_requests,
    review ? LEAVE_REVIEW_FIELDS : LEAVE_REQUEST_FIELDS
  );
}

function locatorSlipData(context, { review = false } = {}) {
  return pickList(
    context?.recent_locator_slips,
    review ? LOCATOR_REVIEW_FIELDS : LOCATOR_SLIP_FIELDS
  );
}

function buildExternalToolData(intent, context) {
  if (intent === 'today_dtr') {
    return {
      dateRange: dateRange(context),
      record: pick(context?.dtr_records?.[0], DTR_RECORD_FIELDS),
    };
  }

  if (intent === 'dtr_policy_guidance' || intent === 'dtr_export_guidance') {
    return {
      dateRange: dateRange(context),
      dtrPolicies: context?.dtr_policies || [],
    };
  }

  if (intent === 'dtr_holiday_check' || intent === 'dtr_schedule_context') {
    return {
      ...dtrData(context, { records: false }),
      dtrPolicies: context?.dtr_policies || [],
    };
  }

  if (intent === 'dtr_leave_coverage_check') {
    return {
      ...dtrData(context),
      leaveRequests: leaveRequestData(context),
    };
  }

  if (intent === 'dtr_locator_coverage_check') {
    return {
      ...dtrData(context),
      locatorSlips: locatorSlipData(context),
      locatorPolicies: context?.locator_policies || [],
    };
  }

  if (
    intent === 'missing_logs' ||
    intent === 'dtr_daily_record' ||
    intent === 'dtr_range_summary' ||
    intent === 'dtr_missing_logs' ||
    intent === 'dtr_missing_log_reason' ||
    intent === 'dtr_late_summary' ||
    intent === 'dtr_late_reason' ||
    intent === 'dtr_undertime_summary' ||
    intent === 'dtr_overtime_summary' ||
    intent === 'dtr_absent_summary' ||
    intent === 'dtr_status_explanation' ||
    intent === 'dtr_correction_guidance' ||
    intent === 'dtr_hours_summary'
  ) {
    return {
      ...dtrData(context),
      dtrPolicies: context?.dtr_policies || [],
    };
  }

  if (intent === 'leave_balance' || intent === 'leave_balance_projection') {
    return {
      balances: pickList(context?.leave_balances, LEAVE_BALANCE_FIELDS),
    };
  }

  if (
    intent === 'leave_rejection_reason' ||
    intent === 'leave_approval_tracker' ||
    intent === 'leave_approval_history'
  ) {
    return {
      dateRange: dateRange(context),
      requests: leaveRequestData(context, { review: true }),
    };
  }

  if (
    intent === 'pending_leave_requests' ||
    intent === 'approved_leave_requests' ||
    intent === 'rejected_leave_requests' ||
    intent === 'leave_history' ||
    intent === 'leave_overlap_check' ||
    intent === 'leave_pending_days_explanation' ||
    intent === 'leave_request_summary' ||
    intent === 'leave_request_lookup' ||
    intent === 'latest_leave_request'
  ) {
    return {
      dateRange: dateRange(context),
      requests: leaveRequestData(context),
    };
  }

  if (intent === 'leave_availability_check' || intent === 'leave_balance_after_filing') {
    return {
      balances: pickList(context?.leave_balances, LEAVE_BALANCE_FIELDS),
      requests: leaveRequestData(context),
      annualUsage: context?.leave_annual_usage || [],
      leaveTypes: pickList(context?.leave_types, LEAVE_TYPE_FIELDS),
      leaveGuidelines: context?.leave_guidelines || [],
      extraction: context?.assistant_extraction || null,
    };
  }

  if (
    intent === 'leave_types' ||
    intent === 'leave_attachment_requirement' ||
    intent === 'leave_filing_policy' ||
    intent === 'leave_form_guidance' ||
    intent === 'leave_form_field_help' ||
    intent === 'leave_eligibility_check' ||
    intent === 'leave_dtr_impact' ||
    intent === 'leave_guideline_section' ||
    intent === 'leave_type_compare' ||
    intent === 'leave_guided_filing' ||
    intent === 'leave_requirements'
  ) {
    return {
      balances: pickList(context?.leave_balances, LEAVE_BALANCE_FIELDS),
      leaveTypes: pickList(context?.leave_types, LEAVE_TYPE_FIELDS),
      leaveGuidelines: context?.leave_guidelines || [],
      leaveGuidelineCatalog: context?.leave_guideline_catalog || [],
    };
  }

  if (
    intent === 'locator_rejection_reason' ||
    intent === 'locator_approval_tracker'
  ) {
    return {
      dateRange: dateRange(context),
      slips: locatorSlipData(context, { review: true }),
      locatorTypes: pickList(context?.locator_types, LOCATOR_TYPE_FIELDS),
      locatorPolicies: context?.locator_policies || [],
    };
  }

  if (
    intent === 'latest_locator_request' ||
    intent === 'locator_status' ||
    intent === 'locator_summary' ||
    intent === 'locator_types' ||
    intent === 'locator_requirements' ||
    intent === 'locator_form_field_help' ||
    intent === 'locator_guided_filing' ||
    intent === 'locator_availability_check'
  ) {
    return {
      dateRange: dateRange(context),
      slips: locatorSlipData(context),
      locatorTypes: pickList(context?.locator_types, LOCATOR_TYPE_FIELDS),
      locatorPolicies: context?.locator_policies || [],
    };
  }

  return {};
}

function buildExternalDirectContext(context) {
  return {
    dateRange: dateRange(context),
    dtrPolicies: context?.dtr_policies || [],
    leaveTypes: pickList(context?.leave_types, LEAVE_TYPE_FIELDS),
    leaveGuidelines: context?.leave_guidelines || [],
    locatorTypes: pickList(context?.locator_types, LOCATOR_TYPE_FIELDS),
    locatorPolicies: context?.locator_policies || [],
  };
}

function assertExternalConsent(profile, consentVersion) {
  if (!profile?.external) return;
  if (String(consentVersion || '').trim() === EXTERNAL_AI_CONSENT_VERSION) return;
  const err = new Error(
    'Confirm external AI data processing before using this model.'
  );
  err.statusCode = 400;
  err.code = 'EXTERNAL_AI_CONSENT_REQUIRED';
  throw err;
}

function disclosureEvent({ userId, profile, purpose, intent, data }) {
  const subjectHash = crypto
    .createHash('sha256')
    .update(String(userId || ''))
    .digest('hex')
    .slice(0, 16);
  return {
    event: 'dtr_assistant_external_ai_disclosure',
    occurredAt: new Date().toISOString(),
    subjectHash,
    provider: profile?.provider || null,
    modelProfile: profile?.id || null,
    purpose: purpose || null,
    intent: intent || null,
    dataCategories: Object.keys(data || {}).sort(),
    consentVersion: EXTERNAL_AI_CONSENT_VERSION,
  };
}

function logExternalDisclosure(input) {
  if (!input.profile?.external) return null;
  const event = disclosureEvent(input);
  console.info('[dtr-assistant-external-ai]', JSON.stringify(event));
  return event;
}

module.exports = {
  EXTERNAL_AI_CONSENT_VERSION,
  assertExternalConsent,
  buildExternalDirectContext,
  buildExternalToolData,
  disclosureEvent,
  logExternalDisclosure,
};
