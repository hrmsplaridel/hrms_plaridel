function buildDtrAssistantIntentMessages({ message }) {
  return [
    {
      role: 'system',
      content:
        'Classify one employee HRMS question into exactly one intent. Supported intents: today_dtr, missing_logs, dtr_daily_record, dtr_range_summary, dtr_missing_logs, dtr_missing_log_reason, dtr_late_summary, dtr_late_reason, dtr_undertime_summary, dtr_overtime_summary, dtr_absent_summary, dtr_status_explanation, dtr_correction_guidance, dtr_leave_coverage_check, dtr_locator_coverage_check, dtr_holiday_check, dtr_schedule_context, dtr_export_guidance, dtr_policy_guidance, leave_balance, pending_leave_requests, approved_leave_requests, rejected_leave_requests, leave_history, leave_availability_check, leave_attachment_requirement, leave_overlap_check, leave_pending_days_explanation, leave_balance_after_filing, leave_request_summary, leave_filing_policy, leave_form_guidance, leave_eligibility_check, leave_dtr_impact, leave_guideline_section, leave_type_compare, leave_guided_filing, leave_approval_history, leave_rejection_reason, leave_approval_tracker, leave_request_lookup, leave_types, leave_requirements, latest_leave_request, latest_locator_request, locator_status, locator_summary, locator_types, locator_requirements, locator_availability_check, locator_rejection_reason, locator_approval_tracker, unknown. Understand English, Tagalog/Filipino, and Bisaya/Cebuano. Return only compact JSON like {"intent":"missing_logs"}.',
    },
    {
      role: 'user',
      content: String(message || ''),
    },
  ];
}

function buildDtrAssistantToolPlanMessages({ message, today }) {
  return [
    {
      role: 'system',
      content:
        'You convert one employee HRMS chatbot question into a safe tool plan. Return only compact JSON. Supported intents: today_dtr, missing_logs, dtr_daily_record, dtr_range_summary, dtr_missing_logs, dtr_missing_log_reason, dtr_late_summary, dtr_late_reason, dtr_undertime_summary, dtr_overtime_summary, dtr_absent_summary, dtr_status_explanation, dtr_correction_guidance, dtr_leave_coverage_check, dtr_locator_coverage_check, dtr_holiday_check, dtr_schedule_context, dtr_export_guidance, dtr_policy_guidance, leave_balance, pending_leave_requests, approved_leave_requests, rejected_leave_requests, leave_history, leave_availability_check, leave_attachment_requirement, leave_overlap_check, leave_pending_days_explanation, leave_balance_after_filing, leave_request_summary, leave_filing_policy, leave_form_guidance, leave_eligibility_check, leave_dtr_impact, leave_guideline_section, leave_type_compare, leave_guided_filing, leave_approval_history, leave_rejection_reason, leave_approval_tracker, leave_request_lookup, leave_types, leave_requirements, latest_leave_request, latest_locator_request, locator_status, locator_summary, locator_types, locator_requirements, locator_availability_check, locator_rejection_reason, locator_approval_tracker, unknown. Understand English, Tagalog/Filipino, and Bisaya/Cebuano. Map date phrases: "aning bulana"/"karong bulana" = this month, "karong semanaha" = this week, "gahapon/kagahapon" = yesterday, "ugma" = tomorrow, "adtung/adtong/atong/niadtong/niadtung <weekday>" = previous weekday, "noong/nung <weekday>" = previous weekday, "pag/sa/noong/nung/adtong <month day>" = that date, "sa 10"/"adtong 10" = day 10 of the current month, "sunod adlaw"/"next day" = next day, "previous day"/"day before" = previous day. "naa koy duty"/"may pasok" should use dtr_schedule_context. "ngano/bakit absent" should use dtr_status_explanation. DTR policy/rules/guideline questions use dtr_policy_guidance. Locator type/list/options questions use locator_types, including "what are locator types I can file?" and follow-ups like "how about WFH?". Locator status/latest-date questions use locator_status. Locator history/count/list of requests questions use locator_summary. Locator requirements/how-to-file/attachment questions use locator_requirements. Locator can-I-file/eligible/allowed questions use locator_availability_check. Locator rejected/reason/remarks questions use locator_rejection_reason. Locator who/where/holding/waiting questions use locator_approval_tracker. Locator DTR slot coverage questions use dtr_locator_coverage_check. Do not invent HRMS data. JSON shape: {"intent":"dtr_absent_summary","dateRange":{"label":"this month","startDate":"YYYY-MM-DD","endDate":"YYYY-MM-DD"},"normalizedQuestion":"count my absences this month"}. Use today when resolving relative dates. If unsure, use null fields.',
    },
    {
      role: 'user',
      content: JSON.stringify({
        today,
        question: String(message || ''),
      }),
    },
  ];
}

function buildDtrAssistantToolAnswerMessages({ message, intent, toolAnswer, toolData }) {
  return [
    {
      role: 'system',
      content:
        'You are a friendly HRMS assistant. Answer only from the provided HRMS_TOOL_RESULT. Do not invent records, policies, or database values. Do not mention unrelated modules. Reply in the same language or language mix as the employee. If the employee uses Bisaya/Cebuano words such as "unsa", "unsay", "ngano", "pila", "naa", "akong", "nako", "imong", "nimo", "ug", or "karon", reply in Bisaya/Cebuano and do not translate it to Tagalog. If the employee uses Tagalog/Filipino words such as "ano", "bakit", "ilan", "ngayon", or "kailangan", reply in Tagalog/Filipino. Translate database-style labels into natural wording when possible, but keep exact dates, statuses, day counts, and leave type names. Keep the answer concise. Preserve useful line breaks and bullet-style structure from HRMS_TOOL_RESULT; do not collapse a structured report into one paragraph. If asked why a leave balance is small, explain using earned, used, adjusted, pending, remaining, and available values when present.',
    },
    {
      role: 'user',
      content: `${JSON.stringify({
        question: message,
        intent,
        HRMS_TOOL_RESULT: {
          answer: toolAnswer,
          data: toolData,
        },
      })}\n/no_think`,
    },
  ];
}

function buildDtrAssistantDirectMessages({ message, context }) {
  const compactContext = {
    dateRange: context.date_range,
    employee: context.employee,
    dtrRecords: context.dtr_records,
    dtrCalendarDays: context.dtr_calendar_days,
    dtrPolicies: context.dtr_policies,
    leaveBalances: context.leave_balances,
    leaveRequests: context.recent_leave_requests,
    leaveTypes: context.leave_types,
    leaveGuidelines: context.leave_guidelines,
    locatorSlips: context.recent_locator_slips,
    locatorTypes: context.locator_types,
    locatorPolicies: context.locator_policies,
  };

  return [
    {
      role: 'system',
      content:
        'You are an HRMS assistant. Answer only from the provided HRMS_CONTEXT JSON. Do not invent leave balances, statuses, policies, dates, or approvals. If the context does not contain the answer, say what is missing. Reply in the same language or language mix as the employee. If the employee uses Bisaya/Cebuano words such as "unsa", "unsay", "ngano", "pila", "naa", "akong", "nako", "imong", "nimo", "ug", or "karon", reply in Bisaya/Cebuano and do not translate it to Tagalog. If the employee uses Tagalog/Filipino words such as "ano", "bakit", "ilan", "ngayon", or "kailangan", reply in Tagalog/Filipino. Keep answers concise.',
    },
    {
      role: 'user',
      content: `${JSON.stringify({
        question: message,
        HRMS_CONTEXT: compactContext,
      })}\n/no_think`,
    },
  ];
}

module.exports = {
  buildDtrAssistantIntentMessages,
  buildDtrAssistantToolPlanMessages,
  buildDtrAssistantToolAnswerMessages,
  buildDtrAssistantDirectMessages,
};
