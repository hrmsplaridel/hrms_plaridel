function buildDtrAssistantIntentMessages({ message }) {
  return [
    {
      role: 'system',
      content:
        'Classify one employee HRMS question into exactly one intent. Supported intents: today_dtr, missing_logs, leave_balance, pending_leave_requests, approved_leave_requests, rejected_leave_requests, leave_history, leave_availability_check, leave_attachment_requirement, leave_overlap_check, leave_pending_days_explanation, leave_balance_after_filing, leave_request_summary, leave_filing_policy, leave_rejection_reason, leave_approval_tracker, leave_types, leave_requirements, latest_leave_request, latest_locator_request, unknown. Understand English, Tagalog/Filipino, and Bisaya/Cebuano. Return only compact JSON like {"intent":"missing_logs"}.',
    },
    {
      role: 'user',
      content: String(message || ''),
    },
  ];
}

function buildDtrAssistantToolAnswerMessages({ message, intent, toolAnswer, toolData }) {
  return [
    {
      role: 'system',
      content:
        'You are a friendly HRMS assistant. Answer only from the provided HRMS_TOOL_RESULT. Do not invent records, policies, or database values. Do not mention unrelated modules. Reply in the same language or language mix as the employee. If the employee uses Bisaya/Cebuano words such as "unsa", "unsay", "ngano", "pila", "naa", "akong", "nako", "imong", "nimo", "ug", or "karon", reply in Bisaya/Cebuano and do not translate it to Tagalog. If the employee uses Tagalog/Filipino words such as "ano", "bakit", "ilan", "ngayon", or "kailangan", reply in Tagalog/Filipino. Translate database-style labels into natural wording when possible, but keep exact dates, statuses, day counts, and leave type names. Keep the answer concise, usually 1 to 4 sentences. If asked why a leave balance is small, explain using earned, used, adjusted, pending, remaining, and available values when present.',
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
    leaveBalances: context.leave_balances,
    leaveRequests: context.recent_leave_requests,
    leaveTypes: context.leave_types,
    locatorSlips: context.recent_locator_slips,
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
  buildDtrAssistantToolAnswerMessages,
  buildDtrAssistantDirectMessages,
};
