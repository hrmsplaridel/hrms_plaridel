const { detectAssistantLanguage } = require('./dtrAssistantLanguage');
const { explicitQuestionIntent, isWritingRequest, locatorPolicyKind, currentQuestion } = require('./dtrAssistantQuestion');
const {
  isLocatorCreditRequirementQuestion,
  scoreEmployeeAssistantIntent,
  intentDomain,
} = require('./dtrAssistantIntentService');

function lower(value) {
  return String(value || '').toLowerCase();
}

const SEGMENT_SPLIT_PATTERN =
  /\s+(?:and|ug|at|saka|then|plus|,\s*also|,\s*additionally|,\s*as well as)\s+|\?\s+(?=[A-Za-z])/i;

const MULTI_INTENT_LABELS = {
  leave_balance: 'Leave balance',
  leave_availability_check: 'Leave filing check',
  leave_guided_filing: 'Leave filing',
  dtr_missing_logs: 'Missing logs',
  dtr_late_summary: 'Late summary',
  dtr_absent_summary: 'Absences',
  dtr_hours_summary: 'Hours worked',
  dtr_correction_guidance: 'DTR correction',
  locator_status: 'Locator status',
  locator_availability_check: 'Locator filing check',
  locator_guided_filing: 'Locator filing',
  latest_leave_request: 'Latest leave request',
  pending_leave_requests: 'Pending leave',
  today_dtr: 'Today DTR',
};

const LOCALIZED_MULTI_INTENT_LABELS = {
  bisaya: {
    leave_balance: 'Leave balance',
    leave_availability_check: 'Leave filing check',
    leave_guided_filing: 'Pag-file ug leave',
    dtr_missing_logs: 'Missing logs',
    dtr_late_summary: 'Late summary',
    dtr_absent_summary: 'Absences',
    dtr_hours_summary: 'Total hours',
    dtr_correction_guidance: 'DTR correction',
    locator_status: 'Locator status',
    locator_availability_check: 'Locator filing check',
    locator_guided_filing: 'Pag-file ug locator',
    latest_leave_request: 'Pinakabag-o nga leave request',
    pending_leave_requests: 'Pending leave',
    today_dtr: 'DTR karon',
  },
  tagalog: {
    leave_balance: 'Leave balance',
    leave_availability_check: 'Leave filing check',
    leave_guided_filing: 'Pag-file ng leave',
    dtr_missing_logs: 'Missing logs',
    dtr_late_summary: 'Late summary',
    dtr_absent_summary: 'Absences',
    dtr_hours_summary: 'Total hours',
    dtr_correction_guidance: 'DTR correction',
    locator_status: 'Locator status',
    locator_availability_check: 'Locator filing check',
    locator_guided_filing: 'Pag-file ng locator',
    latest_leave_request: 'Pinakabagong leave request',
    pending_leave_requests: 'Pending leave',
    today_dtr: 'DTR ngayon',
  },
};

function splitMessageSegments(message) {
  const text = currentQuestion(message);
  if (!text) return [];
  const parts = text
    .split(/,\s*(?:and\s+)?(?=(?:yesterday|today|the latest|my |leave |sick |locator |attendance |dtr\b))|\s+(?:and|ug|at|saka|then|plus)\s+|\?\s+(?=[A-Za-z])/i)
    .map((part) => part.trim())
    .filter((part) => part.length >= 8);
  if (parts.length <= 1) return [text];
  return parts;
}

function uniqueIntents(items) {
  const seen = new Set();
  const result = [];
  for (const item of items) {
    if (!item?.intent || seen.has(item.intent)) continue;
    seen.add(item.intent);
    result.push(item);
  }
  return result;
}

function detectMultipleIntents(message, options = {}) {
  message = currentQuestion(message);
  const specific = explicitQuestionIntent(message);
  if (['request_status_overview', 'dtr_policy_guidance'].includes(specific)) return {isMulti:false, intents:[{segment:message,intent:specific,confidence:1}],segments:[message]};
  if (isWritingRequest(message) || locatorPolicyKind(message) || ['locator_type_compare', 'leave_type_compare', 'leave_form_field_help', 'locator_form_field_help', 'system_navigation_help','assistant_action_guidance','request_policy_guidance','request_checklist','dtr_comparison'].includes(specific)) {
    return { isMulti: false, intents: specific ? [{ segment: message, intent: specific, confidence: 1, domain: intentDomain(specific) }] : [], segments: [message] };
  }
  const splitSegments = splitMessageSegments(message);
  const independentBalance = splitSegments.some(segment => /\b(?:leave|sick|vacation)\b/i.test(segment) && /\b(?:credits?|balance)\b/i.test(segment) && !/\b(?:locator|wfh|pass slip)\b/i.test(segment));
  if (isLocatorCreditRequirementQuestion(message) && !independentBalance) {
    return {
      isMulti: false,
      intents: [
        {
          segment: String(message || '').trim(),
          intent: 'locator_requirements',
          confidence: 1,
          source: 'locator_credit_rule',
          domain: 'locator',
        },
      ],
      segments: [String(message || '').trim()],
    };
  }
  const segments = splitMessageSegments(message);
  const scoredSegments = segments.map((segment) => {
    let scoped = segment;
    if (/pending days/i.test(segment) && /leave|credits|balance/i.test(message)) scoped = `${segment} leave`;
    const scored = scoreEmployeeAssistantIntent(scoped, options.explicitIntent || null);
    if (/\b(?:attendance|dtr)\b/i.test(segment) && !/missing|late|undertime|overtime|policy|rules|correction|export/i.test(segment)) {
      scored.intent = 'dtr_status_explanation'; scored.confidence = 1;
    }
    if (/pending days/i.test(scoped)) { scored.intent='leave_pending_days_explanation'; scored.confidence=1; }
    if (/\b(?:sick|vacation|leave)\b/i.test(segment) && /credits?|balance/i.test(segment) && !/why|explain|pending|need|deduct/i.test(segment)) {
      scored.intent='leave_balance'; scored.confidence=1;
    }
    return {
      segment,
      intent: scored.intent,
      confidence: scored.confidence,
      source: scored.source,
      domain: intentDomain(scored.intent),
    };
  });

  const viable = scoredSegments.filter(
    (item) => item.intent && item.confidence >= 0.58
  );
  const unique = uniqueIntents(viable);

  if (unique.length >= 2) {
    return {
      isMulti: true,
      intents: unique.slice(0, 3),
      segments,
    };
  }


  return {
    isMulti: false,
    intents: unique.slice(0, 1),
    segments,
  };
}

function stripReplyForSection(reply) {
  const lines = String(reply || '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
  if (lines.length === 0) return '';
  if (lines.length === 1) return lines[0];

  const first = lines[0];
  const second = lines[1];
  const firstLooksLikeTitle =
    first.length <= 48 &&
    !/[.!?]$/.test(first) &&
    !first.includes(':') &&
    second &&
    second.length > 0;

  const bodyLines = firstLooksLikeTitle ? lines.slice(1) : lines;
  return bodyLines.slice(0, 5).join('\n');
}

function localizedLabel(intent, language) {
  return (
    LOCALIZED_MULTI_INTENT_LABELS[language]?.[intent] ||
    MULTI_INTENT_LABELS[intent] ||
    intent.replace(/_/g, ' ')
  );
}

function combineMultiIntentReplies(replies, message) {
  const language = detectAssistantLanguage(message);
  const title =
    language === 'bisaya'
      ? 'Tubag sa imong mga pangutana'
      : language === 'tagalog'
        ? 'Sagot sa mga tanong mo'
        : 'Answers to your questions';
  const intro =
    language === 'bisaya'
      ? 'Mao ni ang nakuha nako:'
      : language === 'tagalog'
        ? 'Ito ang nakuha ko:'
        : 'Here is what I found:';

  const sections = replies.map((item, index) => {
    const label = localizedLabel(item.intent, language);
    const body = stripReplyForSection(item.content);
    return `${index + 1}. ${label}\n${body}`;
  });

  return [title, intro, '', ...sections].join('\n');
}

module.exports = {
  combineMultiIntentReplies,
  detectMultipleIntents,
  splitMessageSegments,
  MULTI_INTENT_LABELS,
};
