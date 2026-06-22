const { normalizeAssistantMessageForRules } = require('./dtrAssistantTextNormalizer');

function lower(value) {
  return String(value || '').toLowerCase();
}

const LEAVE_TOPIC_PATTERN =
  /\b(leave|leaves|vl|sl|sick|vacation|paternity|maternity|adoption|solo parent|vawc|calamity|mandatory|forced|special privilege)\b/;

function isLeaveHowToFileQuestion(text) {
  if (
    /\b(requirements?|requirement|attachment|attachments?|document|documents|docs|proof|supporting|need|needed|kinahanglan|kailangan)\b/.test(
      text
    )
  ) {
    return false;
  }
  return /\b(how can i file|how do i file|how to file|how can i apply|how do i apply|how to apply|steps? to file|procedure.*file|guide.*file|paano.*file|paano.*apply|unsaon.*file|unsaon.*apply|paunsa.*file|pag file|pag-file)\b/.test(
    text
  );
}

function isLeaveGuidelineSectionQuestion(text) {
  return /\b(general rules?|filing deadlines?|deadlines?|supporting documents?|attachments?|leave credits?|credits and limits?|commutation|monetization|monetisation|terminal leave|guidelines?|guideline sections?|guidelines?.*(?:leave types?|types of leave)|leave types?.*guidelines?|types of leave.*guidelines?|explain.*guidelines?|explain.*deadlines?|explain.*credits?|explain.*documents?)\b/.test(
    text
  );
}

function isLeaveTypeExplanationQuestion(text) {
  const hasExplainWord =
    /\b(explain|describe|details?|detail|tell me about|what is|what are|meaning|pasabot|ibig sabihin|i-explain|explain daw|explain na)\b/.test(
      text
    );
  if (!hasExplainWord) return false;
  if (/\b(dtr|attendance|locator|pass slip|wfh|official business|ob)\b/.test(text)) return false;
  return (
    LEAVE_TOPIC_PATTERN.test(text) ||
    /\b(leave types?|types of leave|all leaves?|available leaves?)\b/.test(text)
  );
}

function normalizeIntent(value) {
  const intent = String(value || '').trim().toLowerCase();
  return [
    'today_dtr',
    'missing_logs',
    'dtr_daily_record',
    'dtr_range_summary',
    'dtr_missing_logs',
    'dtr_missing_log_reason',
    'dtr_late_summary',
    'dtr_late_reason',
    'dtr_undertime_summary',
    'dtr_overtime_summary',
    'dtr_absent_summary',
    'dtr_status_explanation',
    'dtr_correction_guidance',
    'dtr_leave_coverage_check',
    'dtr_locator_coverage_check',
    'dtr_holiday_check',
    'dtr_schedule_context',
    'dtr_export_guidance',
    'dtr_policy_guidance',
    // Calculated intents
    'dtr_hours_summary',
    'leave_balance_projection',
    // Leave intents
    'leave_balance',
    'pending_leave_requests',
    'approved_leave_requests',
    'rejected_leave_requests',
    'leave_history',
    'leave_availability_check',
    'leave_attachment_requirement',
    'leave_overlap_check',
    'leave_pending_days_explanation',
    'leave_balance_after_filing',
    'leave_request_summary',
    'leave_filing_policy',
    'leave_form_guidance',
    'leave_eligibility_check',
    'leave_dtr_impact',
    'leave_guideline_section',
    'leave_type_compare',
    'leave_guided_filing',
    'leave_approval_history',
    'leave_rejection_reason',
    'leave_approval_tracker',
    'leave_request_lookup',
    'leave_types',
    'leave_requirements',
    'latest_leave_request',
    'latest_locator_request',
    'locator_status',
    'locator_summary',
    'locator_types',
    'locator_requirements',
    'locator_availability_check',
    'locator_rejection_reason',
    'locator_approval_tracker',
  ].includes(intent)
    ? intent
    : null;
}

const FUZZY_INTENT_PROFILES = [
  {
    intent: 'dtr_absent_summary',
    phrases: [
      'how many absences',
      'how many absent',
      'pila absent',
      'pila kabuok absent',
      'naa koy absent',
      'absent this month',
      'absent karong bulana',
      'absence summary',
      'no record this month',
    ],
  },
  {
    intent: 'dtr_missing_logs',
    phrases: [
      'missing logs',
      'missing log',
      'incomplete dtr',
      'kulang logs',
      'kuwang logs',
      'walay log',
      'wala log',
      'do i have missing logs',
    ],
  },
  {
    intent: 'dtr_missing_log_reason',
    phrases: [
      'why are my dtr logs missing',
      'why my dtr logs missing',
      'why is my dtr incomplete',
      'reason missing dtr logs',
      'explain missing dtr logs',
      'ngano wala logs dtr',
      'ngano wala ang logs sa akong dtr',
      'bakit kulang dtr logs',
    ],
  },
  {
    intent: 'dtr_correction_guidance',
    phrases: [
      'how do i fix my missing logs',
      'fix missing logs',
      'correct missing logs',
      'dtr correction',
      'how to correct dtr',
      'paano i correct dtr',
      'unsaon pag correct dtr',
    ],
  },
  {
    intent: 'today_dtr',
    phrases: [
      'did i time in today',
      'did i time out today',
      'have i timed in today',
      'did i clock in today',
      'did i log in today',
    ],
  },
  {
    intent: 'dtr_status_explanation',
    phrases: [
      'dtr status',
      'attendance status',
      'why absent',
      'ngano absent',
      'bakit absent',
      'explain my dtr',
      'unsay status sa akong dtr',
    ],
  },
  {
    intent: 'dtr_schedule_context',
    phrases: [
      'current shift',
      'my shift',
      'schedule today',
      'work schedule',
      'naa koy duty',
      'may pasok',
      'office hours',
    ],
  },
  {
    intent: 'dtr_late_summary',
    phrases: ['late summary', 'how many late', 'pila late', 'tardy this month', 'late records'],
  },
  {
    intent: 'dtr_undertime_summary',
    phrases: ['undertime summary', 'how many undertime', 'early out', 'short hours', 'kulang oras'],
  },
  {
    intent: 'dtr_overtime_summary',
    phrases: ['overtime summary', 'over time', 'ot hours', 'how many overtime'],
  },
  {
    intent: 'dtr_export_guidance',
    phrases: ['export dtr', 'download dtr', 'print dtr', 'dtr pdf', 'dtr excel', 'dtr report'],
  },
  {
    intent: 'dtr_policy_guidance',
    phrases: ['dtr rules', 'attendance rules', 'dtr policy', 'attendance policy', 'dtr guidelines'],
  },
  {
    intent: 'leave_balance',
    phrases: [
      'leave balance',
      'sick leave balance',
      'vacation leave balance',
      'remaining leave',
      'available leave',
      'leave credits',
      'pila leave balance',
      'pila akong sick leave',
      'ngano gamay leave balance',
    ],
  },
  {
    intent: 'leave_guideline_section',
    phrases: [
      'explain leave types',
      'explain sick leave',
      'explain vacation leave',
      'leave type guidelines',
      'guidelines of leave types',
      'leave guidelines',
      'filing deadlines',
      'supporting documents',
      'leave credits and limits',
      'what is sick leave',
      'unsay pasabot sick leave',
    ],
  },
  {
    intent: 'leave_requirements',
    phrases: [
      'leave requirements',
      'requirements sick leave',
      'requirements maternity leave',
      'unsay requirements',
      'ano requirements',
      'kinahanglan leave',
      'kailangan leave',
    ],
  },
  {
    intent: 'leave_attachment_requirement',
    phrases: [
      'attachment requirement',
      'medical certificate',
      'med cert',
      'supporting document',
      'need attachment',
      'need med cert',
      'kinahanglan attachment',
    ],
  },
  {
    intent: 'leave_form_guidance',
    phrases: ['how to file leave', 'how can i file leave', 'paano mag file leave', 'unsaon pag file leave', 'leave form'],
  },
  {
    intent: 'leave_availability_check',
    phrases: ['can i file leave', 'pwede mag file leave', 'eligible to file leave', 'can file sick leave', 'can file vacation'],
  },
  {
    intent: 'leave_types',
    phrases: ['leave types', 'types of leave', 'available leave types', 'what leave types', 'list leave types'],
  },
  {
    intent: 'leave_approval_tracker',
    phrases: ['who is holding leave', 'kinsa nag hold leave', 'where is my leave', 'pending with leave'],
  },
  {
    intent: 'pending_leave_requests',
    phrases: [
      'show my pending leave requests',
      'pending leave requests',
      'my pending leave',
      'leave requests pending',
      'pending leave',
      'naa pending leave',
      'may pending leave',
    ],
  },
  {
    intent: 'leave_rejection_reason',
    phrases: ['why rejected leave', 'ngano gi reject leave', 'bakit rejected leave', 'leave rejection reason'],
  },
  {
    intent: 'leave_history',
    phrases: ['leave history', 'my leave requests', 'show my leaves', 'leave records'],
  },
  {
    intent: 'locator_types',
    phrases: ['locator types', 'types of locator', 'what is wfh', 'what is pass slip', 'how about wfh', 'available locator'],
  },
  {
    intent: 'locator_status',
    phrases: ['locator status', 'locator approved', 'locator accepted', 'na approve locator', 'latest locator', 'where is locator'],
  },
  {
    intent: 'locator_requirements',
    phrases: ['locator requirements', 'how to file locator', 'locator attachment', 'pass slip requirements', 'wfh requirements'],
  },
  {
    intent: 'locator_availability_check',
    phrases: ['can i file locator', 'can file pass slip', 'pwede locator', 'pwede wfh', 'file locator tomorrow'],
  },
  {
    intent: 'locator_summary',
    phrases: ['locator history', 'locator summary', 'how many locator', 'list locator requests', 'accepted locator count', 'approved locator count', 'pila accepted locator'],
  },
  {
    intent: 'locator_rejection_reason',
    phrases: ['why rejected locator', 'ngano gi reject locator', 'locator rejection reason'],
  },
  {
    intent: 'locator_approval_tracker',
    phrases: [
      'who is holding locator',
      'kinsa nag hold locator',
      'pending with locator',
      'where is locator request',
      'nasaan locator request',
      'nasaan na locator request',
      'asa na locator request',
    ],
  },
  // Calculated intents
  {
    intent: 'dtr_hours_summary',
    phrases: [
      'how many hours did i work',
      'total hours worked',
      'hours this month',
      'pila ka oras nagtrabaho',
      'pila oras this month',
      'total oras nako',
      'working hours this month',
      'how much hours did i render',
      'hours rendered',
      'ilan oras nagtrabaho',
      'total hours this week',
      'pila oras this week',
    ],
  },
  {
    intent: 'leave_balance_projection',
    phrases: [
      'if i take 1 day what remains',
      'if i file leave how much left',
      'balance after taking days',
      'remaining balance if i file',
      'pila mabilin kung mag file',
      'pila matira kung mag leave',
      'how much leave will i have left',
      'if i take sick leave how many days left',
      'after filing how much remains',
      'magkano mabilin kung mag file ug',
    ],
  },
];

function tokenize(value) {
  return lower(value)
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .split(/\s+/)
    .filter((token) => token.length > 1);
}

function levenshtein(a, b) {
  if (a === b) return 0;
  if (!a) return b.length;
  if (!b) return a.length;
  const prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  const curr = Array(b.length + 1).fill(0);
  for (let i = 1; i <= a.length; i += 1) {
    curr[0] = i;
    for (let j = 1; j <= b.length; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(
        curr[j - 1] + 1,
        prev[j] + 1,
        prev[j - 1] + cost
      );
    }
    for (let j = 0; j <= b.length; j += 1) prev[j] = curr[j];
  }
  return prev[b.length];
}

function tokenSimilarity(a, b) {
  if (!a || !b) return 0;
  if (a === b) return 1;
  if (a.length >= 4 && b.length >= 4 && (a.startsWith(b) || b.startsWith(a))) return 0.88;
  const maxLen = Math.max(a.length, b.length);
  if (maxLen <= 2) return 0;
  const distance = levenshtein(a, b);
  const ratio = 1 - distance / maxLen;
  if (maxLen <= 4) return ratio >= 0.75 ? ratio : 0;
  return ratio >= 0.68 ? ratio : 0;
}

function phraseSimilarity(queryTokens, phrase) {
  const phraseTokens = tokenize(phrase);
  if (phraseTokens.length === 0 || queryTokens.length === 0) return 0;
  const scores = phraseTokens.map((phraseToken) =>
    Math.max(...queryTokens.map((queryToken) => tokenSimilarity(queryToken, phraseToken)))
  );
  const average = scores.reduce((sum, score) => sum + score, 0) / scores.length;
  const coverage = scores.filter((score) => score >= 0.68).length / phraseTokens.length;
  return average * 0.65 + coverage * 0.35;
}

function scoreFuzzyIntents(message) {
  const normalized = normalizeAssistantMessageForRules(message);
  const queryTokens = tokenize(normalized);
  const scores = FUZZY_INTENT_PROFILES.map((profile) => {
    const phraseScores = profile.phrases.map((phrase) => phraseSimilarity(queryTokens, phrase));
    const best = Math.max(0, ...phraseScores);
    const second = phraseScores
      .slice()
      .sort((a, b) => b - a)[1] || 0;
    return {
      intent: profile.intent,
      confidence: Math.min(1, best * 0.88 + second * 0.12),
      source: 'fuzzy',
    };
  })
    .filter((item) => item.confidence > 0)
    .sort((a, b) => b.confidence - a.confidence);

  return {
    normalizedText: normalized,
    top: scores[0] || null,
    runnerUp: scores[1] || null,
    scores: scores.slice(0, 5),
  };
}

function intentDomain(intent) {
  if (!intent) return null;
  if (
    intent.startsWith('dtr_') ||
    intent === 'today_dtr' ||
    intent === 'missing_logs'
  ) {
    return 'dtr';
  }
  if (
    intent.startsWith('leave_') ||
    intent === 'pending_leave_requests' ||
    intent === 'approved_leave_requests' ||
    intent === 'rejected_leave_requests' ||
    intent === 'latest_leave_request'
  ) {
    return 'leave';
  }
  if (intent.startsWith('locator_') || intent === 'latest_locator_request') {
    return 'locator';
  }
  return null;
}

function hasIntentDomainSignal(message, intent) {
  const domain = intentDomain(intent);
  if (!domain) return true;
  const text = lower(normalizeAssistantMessageForRules(message));
  if (domain === 'dtr') {
    return /\b(dtr|attendance|daily time|log|logs|time[\s-]?in|time[\s-]?out|clock[\s-]?in|clock[\s-]?out|late|undertime|overtime|absent|absent[s]?|absence|absences|absnt|absnts|abssent|abssents|incomplete|present|duty|pasok|sched|schedule|shift|holiday|missing|kulang|kuwang|oras|hours)\b/.test(
      text
    );
  }
  if (domain === 'leave') {
    return /\b(leave|leaves|vl|sl|sick|vacation|paternity|maternity|adoption|solo parent|vawc|calamity|mandatory|forced|special privilege|credits?|balance|medical certificate|med cert)\b/.test(
      text
    );
  }
  if (domain === 'locator') {
    return /\b(locator|locator slip|pass slip|wfh|work from home|official business|ob request|ob|on field|field work|fieldwork|out of office|outside office|travel order)\b/.test(
      text
    );
  }
  return true;
}

function shouldAllowFuzzyOverride(ruleIntent, fuzzyIntent, message) {
  if (!ruleIntent || !fuzzyIntent || ruleIntent === fuzzyIntent) return false;
  if (!hasIntentDomainSignal(message, fuzzyIntent)) return false;

  const protectedRuleIntents = new Set([
    'dtr_missing_log_reason',
    'dtr_correction_guidance',
    'pending_leave_requests',
    'leave_approval_tracker',
    'leave_rejection_reason',
    'locator_approval_tracker',
    'locator_rejection_reason',
  ]);
  if (protectedRuleIntents.has(ruleIntent)) return false;

  if (ruleIntent === 'today_dtr' && fuzzyIntent === 'dtr_daily_record') return false;
  if (ruleIntent === 'pending_leave_requests' && fuzzyIntent === 'leave_history') return false;
  if (ruleIntent === 'locator_approval_tracker' && fuzzyIntent === 'latest_locator_request') return false;
  if (ruleIntent === 'dtr_missing_log_reason' && fuzzyIntent === 'dtr_missing_logs') return false;
  if (ruleIntent === 'dtr_correction_guidance' && fuzzyIntent === 'dtr_missing_logs') return false;

  return true;
}

function scoreEmployeeAssistantIntent(message, explicitIntent) {
  const forcedIntent = normalizeIntent(explicitIntent);
  if (forcedIntent) {
    return {
      intent: forcedIntent,
      confidence: 1,
      source: 'explicit',
      needsAiPlan: false,
      fuzzy: scoreFuzzyIntents(message),
    };
  }

  const fuzzy = scoreFuzzyIntents(message);
  const ruleIntent = detectEmployeeAssistantIntentByRules(message, null);
  const top = fuzzy.top;
  const runnerUp = fuzzy.runnerUp;
  const ruleScore =
    fuzzy.scores.find((item) => item.intent === ruleIntent)?.confidence || 0;

  if (ruleIntent) {
    if (
      top &&
      top.intent !== ruleIntent &&
      shouldAllowFuzzyOverride(ruleIntent, top.intent, message) &&
      top.confidence >= 0.72 &&
      top.confidence - ruleScore >= 0.16
    ) {
      return {
        intent: top.intent,
        confidence: top.confidence,
        source: 'fuzzy_override',
        needsAiPlan: top.confidence < 0.78,
        fuzzy,
        ruleIntent,
      };
    }

    const confidence = Math.max(ruleScore, ruleScore >= 0.5 ? 0.84 : 0.74);
    return {
      intent: ruleIntent,
      confidence,
      source: ruleScore >= 0.5 ? 'rules_fuzzy' : 'rules',
      needsAiPlan: confidence < 0.78,
      fuzzy,
      ruleIntent,
    };
  }

  const margin = top && runnerUp ? top.confidence - runnerUp.confidence : top?.confidence || 0;
  if (
    top &&
    top.confidence >= 0.62 &&
    margin >= 0.08 &&
    hasIntentDomainSignal(message, top.intent)
  ) {
    return {
      intent: top.intent,
      confidence: top.confidence,
      source: 'fuzzy',
      needsAiPlan: top.confidence < 0.72,
      fuzzy,
      ruleIntent: null,
    };
  }

  return {
    intent: null,
    confidence: top?.confidence || 0,
    source: 'unclear',
    needsAiPlan: true,
    fuzzy,
    ruleIntent: null,
  };
}

function detectEmployeeAssistantIntentByRules(message, explicitIntent) {
  const forcedIntent = normalizeIntent(explicitIntent);
  if (forcedIntent) return forcedIntent;

  const text = lower(normalizeAssistantMessageForRules(message));
  const hasDtrTopic =
    /\b(dtr|attendance|daily time|log|logs|time[\s-]?in|time[\s-]?out|late|undertime|overtime|absent|absence|incomplete|present|duty|pasok|sched|schedule|shift|missing|kulang|kuwang)\b/.test(
      text
    );
  const hasDateTopic =
    /\b(date|day|today|tomorrow|yesterday|ugma|kagahapon|gahapon|karon|ngayon|karong adlawa|sunod|miaging|niaging|adtong|adtung|atong|niadtong|niadtung|noong|nung|next day|following day|sunod adlaw|previous day|day before|ana|ato|adto|same day|same date|pay\s*period|payroll\s*period|cutoff|cut-off|cut off|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b|\b(?:sa|pag|noong|nung|adtong|adtung|atong|niadtong|niadtung)\s+\d{1,2}\b/.test(
      text
    );
  const hasLocatorTopic =
    /\b(locator|locator slip|pass slip|wfh|work from home|official business|ob request|ob|on field|field work|fieldwork|out of office|outside office|travel order)\b/.test(
      text
    );

  if (hasLocatorTopic) {
    if (
      /\b(types?|kinds?|options?|available.*locator|locator.*available|what.*locator.*file|which.*locator.*file|what.*type|which.*type|what is.*(wfh|work from home|pass slip|official business|ob|fieldwork)|unsa.*(wfh|work from home|pass slip|official business|ob|fieldwork)|ano.*(wfh|work from home|pass slip|official business|ob|fieldwork)|unsa.*type|unsay.*type|ano.*type|list.*locator|how about|what about)\b/.test(text) &&
      !/\b(status|approve|approved|accepted|pending|rejected|returned|cancelled|canceled|latest|last|recent|remarks|reason|who|where|asa|kinsa|sino|holding|waiting)\b/.test(text)
    ) {
      return 'locator_types';
    }
    if (
      /\b(covered|cover|covers|sakop|coverage|na cover|na-cover)\b/.test(text) &&
      /\b(dtr|attendance|missing|incomplete|log|logs|am in|am out|pm in|pm out|time[\s-]?in|time[\s-]?out)\b/.test(text)
    ) {
      return 'dtr_locator_coverage_check';
    }
    if (
      /\b(why|ngano|bakit|reason|remarks|comment|rejected|reject|declined|denied|gi reject|gireject|not approved)\b/.test(text)
    ) {
      return 'locator_rejection_reason';
    }
    if (
      /\b(who|kinsa|sino|where|asa|asa na|nasaan|nasan|saan|kanino|holding|hold|pending with|waiting|awaiting|naa.*kinsa|nasa.*kanino|nasa.*saan)\b/.test(text)
    ) {
      return 'locator_approval_tracker';
    }
    if (
      /\b(can i file|can file|pwede.*file|puwede.*file|pwede ba|puwede ba|allowed|eligible|eligibility|qualified|available.*file|file.*tomorrow|file.*today|file.*ugma|file.*karon)\b/.test(text)
    ) {
      return 'locator_availability_check';
    }
    if (
      /\b(requirements?|requirement|attachment|document|docs|need|needed|kinahanglan|kailangan|rules?|policy|how to file|how do i file|unsaon|paano|pwede|can i file|slots?|coverage)\b/.test(text)
    ) {
      return 'locator_requirements';
    }
    if (
      /\b(summary|summarize|summarise|overview|recap|total|count|counts|pila|kabuok|ilan|how many|history|list|show|records|requests|rejected|approved|accepted|pending|cancelled|canceled|this month|this week|month|week|bulan|bulana|semana|semanaha)\b/.test(text)
    ) {
      return 'locator_summary';
    }
    if (
      /\b(status|approve|approved|accepted|na-approve|pending|rejected|returned|cancelled|canceled|where|asa|kinsa|sino|who|holding|waiting|latest|last|recent|remarks|reason)\b/.test(text) ||
      hasDateTopic
    ) {
      return 'locator_status';
    }
    return 'latest_locator_request';
  }

  if (
    /\b(export|download|print|pdf|excel|csv|report)\b/.test(text) &&
    /\b(dtr|attendance|daily time)\b/.test(text)
  ) {
    return 'dtr_export_guidance';
  }

  // --- Calculated intents ---

  if (
    /\b(how many hours|total hours|hours worked|hours rendered|ilan oras|pila.*oras|pila ka oras|oras nako|working hours|hours this)\b/.test(text) &&
    (hasDtrTopic || /\b(month|week|semana|semanaha|bulan|bulana|buwan|buwana|aning bulana|pay\s*period|payroll\s*period|cutoff|cut-off|cut off)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b/.test(text))
  ) {
    return 'dtr_hours_summary';
  }

  if (
    /\b(if i (take|file|avail)|if i mag|kung mag file|kung mag take|kung kumuha|if i use|magkano mabilin|pila mabilin|pila matira|balance.*after|after.*filing|remaining.*if|what.*remain.*if|what.*left.*if|how much.*left.*if|balance projection|project.*leave|calculate.*leave)\b/.test(text) &&
    /\b(\d+|one|two|three|four|five|usa|duha|tulo|upat|lima|isa|dalawa|tatlo|apat)\b/.test(text) &&
    /\b(leave|sick|vacation|sl|vl|day|days|adlaw)\b/.test(text)
  ) {
    return 'leave_balance_projection';
  }

  if (
    /\b(policy|policies|rule|rules|guideline|guidelines|requirements?|requirement|how.*dtr.*work|attendance.*policy|attendance.*rules)\b/.test(text) &&
    (hasDtrTopic || /\b(dtr|attendance|daily time)\b/.test(text))
  ) {
    return 'dtr_policy_guidance';
  }

  if (
    /\b(schedule|shift|work schedule|duty schedule|office hours|sched|sked|duty|pasok|work day|working day|required[-\s]?log|naa.*duty|may.*pasok|naa.*trabaho|may.*trabaho)\b/.test(text) &&
    (hasDtrTopic || hasDateTopic || /\b(naa|may|ba|ko|ako|akong|nako)\b/.test(text))
  ) {
    return 'dtr_schedule_context';
  }

  if (
    /\b(fix|correct|correction|adjust|manual|buhaton|unsa buhaton|ano gagawin|how to fix|resolve)\b/.test(
      text
    ) &&
    /\b(dtr|attendance|log|logs|missing|incomplete|time[\s-]?in|time[\s-]?out|late|undertime)\b/.test(
      text
    )
  ) {
    return 'dtr_correction_guidance';
  }

  if (
    /\b(why|ngano|bakit|reason|explain|what.*missing|what.*kulang|unsa.*missing|unsa.*kulang|ngano.*wala|bakit.*wala)\b/.test(text) &&
    /\b(am in|am out|pm in|pm out|time[\s-]?in|time[\s-]?out|log|logs|dtr)\b/.test(text)
  ) {
    return 'dtr_missing_log_reason';
  }

  if (
    /\b(why|ngano|bakit|unsa.*pasabot|ano.*ibig.*sabihin|explain|reason)\b/.test(text) &&
    /\b(absent|absence|no record|walay record|wala.*record|wala.*dtr|missing|incomplete)\b/.test(text)
  ) {
    return 'dtr_status_explanation';
  }

  if (
    /\b(complete|completed|kompleto|kumpleto|okay|ok|status)\b/.test(text) &&
    /\b(dtr|attendance|log|logs|time[\s-]?in|time[\s-]?out)\b/.test(text)
  ) {
    return hasDateTopic ? 'dtr_status_explanation' : 'dtr_missing_logs';
  }

  if (
    /\b(fix|correct|correction|adjust|manual|buhaton|unsa buhaton|ano gagawin|how to fix|resolve)\b/.test(
      text
    ) &&
    /\b(dtr|attendance|log|logs|missing|incomplete|time[\s-]?in|time[\s-]?out|late|undertime)\b/.test(
      text
    )
  ) {
    return 'dtr_correction_guidance';
  }

  if (
    /\b(covered|cover|covers|why|ngano|bakit|on leave)\b/.test(text) &&
    /\b(leave|vl|sl)\b/.test(text) &&
    /\b(dtr|attendance|absent|missing|incomplete|on leave|date)\b/.test(text)
  ) {
    return 'dtr_leave_coverage_check';
  }

  if (
    /\b(covered|cover|covers|sakop|covered ba|na cover|na-cover|locator|pass slip|wfh|official business|ob)\b/.test(text) &&
    /\b(locator|pass slip|wfh|official business|ob)\b/.test(text) &&
    /\b(dtr|attendance|missing|incomplete|log|logs|date|am in|am out|pm in|pm out|time[\s-]?in|time[\s-]?out)\b/.test(text)
  ) {
    return 'dtr_locator_coverage_check';
  }

  if (
    /\b(holiday|holidays|regular holiday|special holiday|walay work|no work|walay klase|nonworking|non-working)\b/.test(text) &&
    (hasDtrTopic || hasDateTopic)
  ) {
    return 'dtr_holiday_check';
  }

  if (
    /\b(why|ngano|bakit|reason|explain)\b/.test(text) &&
    /\b(late)\b/.test(text)
  ) {
    return 'dtr_late_reason';
  }

  if (
    /\b(late|lates|tardy|tardiness)\b/.test(text) &&
    (hasDtrTopic || /\b(month|week|semana|semanaha|bulan|bulana|buwan|buwana|aning bulana|today|yesterday|kagahapon|gahapon|adtong|adtung|atong|niadtong|niadtung|pay\s*period|payroll\s*period|cutoff|cut-off|cut off)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b/.test(text))
  ) {
    return 'dtr_late_summary';
  }

  if (
    /\b(undertime|under time|early out|early-out|short hours|kulang.*oras)\b/.test(text) &&
    (hasDtrTopic || /\b(month|week|semana|semanaha|bulan|bulana|buwan|buwana|aning bulana|adtong|adtung|atong|niadtong|niadtung|pay\s*period|payroll\s*period|cutoff|cut-off|cut off)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b/.test(text))
  ) {
    return 'dtr_undertime_summary';
  }

  if (
    /\b(overtime|over time|ot)\b/.test(text) &&
    (hasDtrTopic || /\b(month|week|semana|semanaha|bulan|bulana|buwan|buwana|aning bulana|adtong|adtung|atong|niadtong|niadtung|pay\s*period|payroll\s*period|cutoff|cut-off|cut off)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b/.test(text))
  ) {
    return 'dtr_overtime_summary';
  }

  if (
    /\b(absent|absence|absences|pasabot|no record|walay record|wala.*record|wala.*dtr|pila.*absent|ilan.*absent|how many.*absent)\b/.test(text) &&
    (hasDtrTopic || /\b(month|week|semana|semanaha|bulan|bulana|buwan|buwana|aning bulana|today|yesterday|kagahapon|gahapon|adtong|adtung|atong|niadtong|niadtung|pay\s*period|payroll\s*period|cutoff|cut-off|cut off)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b/.test(text))
  ) {
    return 'dtr_absent_summary';
  }

  if (
    /\b(why|ngano|bakit|reason|explain|what.*missing|what.*kulang|unsa.*missing|unsa.*kulang|ngano.*wala|bakit.*wala)\b/.test(
      text
    ) &&
    /\b(dtr|attendance|log|logs|time[\s-]?in|time[\s-]?out|am in|am out|pm in|pm out|incomplete|missing)\b/.test(text)
  ) {
    return 'dtr_missing_log_reason';
  }

  if (
    /\b(missing|incomplete|kulang|kuwang|wala|no log|nolog|logs?|entries|kompleto|kumpleto|complete)\b/.test(text) &&
    /\b(logs?|dtr|attendance|time[\s-]?in|time[\s-]?out|am in|am out|pm in|pm out|this week|week|semanaha|semana|karon|ngayon|pay\s*period|payroll\s*period|cutoff|cut-off|cut off)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b/.test(
      text
    )
  ) {
    return 'dtr_missing_logs';
  }

  if (
    /\b(present|complete|kompleto|kumpleto|status)\b/.test(text) &&
    /\b(summary|summarize|summarise|overview|recap|total|count|counts|pila|kabuok|how many|month|week|semana|semanaha|bulan|bulana|buwan|buwana|aning bulana|pay\s*period|payroll\s*period|cutoff|cut-off|cut off|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b/.test(
      text
    ) &&
    !LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'dtr_range_summary';
  }

  if (
    /\b(status|explain|why|ngano|bakit|unsa.*pasabot|ano.*ibig.*sabihin)\b/.test(text) &&
    /\b(dtr|attendance|incomplete|absent|on leave|holiday|present|no record|missing)\b/.test(text)
  ) {
    return 'dtr_status_explanation';
  }

  if (
    /\b(summary|summarize|summarise|overview|recap|total|count|counts|pila|kabuok|how many|hours|oras)\b/.test(
      text
    ) &&
    /\b(dtr|attendance|daily time|late|undertime|overtime|absent|hours|oras)\b/.test(text)
  ) {
    return 'dtr_range_summary';
  }

  if (
    hasDtrTopic &&
    /\b(week|semana|semanaha|month|bulan|bulana|buwan|buwana|last week|this week|next week|last month|this month|next month|aning bulana|karong semana|karong semanaha|karong bulan|karong bulana|pay\s*period|payroll\s*period|cutoff|cut-off|cut off)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b/.test(
      text
    )
  ) {
    return 'dtr_range_summary';
  }

  if (
    hasDtrTopic &&
    /\b(?:from\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo)\s*(?:to|until|through|-|–)\s*(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo)\b/.test(
      text
    )
  ) {
    return 'dtr_range_summary';
  }

  if (
    /\b(did i|have i|did my|have my)\b/.test(text) &&
    /\b(time[\s-]?in|time[\s-]?out|clock[\s-]?in|clock[\s-]?out|log[\s-]?in|log[\s-]?out)\b/.test(
      text
    ) &&
    /\b(today|karon|ngayon|karong adlawa|this day)\b/.test(text)
  ) {
    return 'today_dtr';
  }

  if (
    /\b(dtr|attendance|daily time|time[\s-]?in|time[\s-]?out|am in|pm out)\b/.test(text) &&
    /\b(today|tomorrow|yesterday|ugma|kagahapon|gahapon|karon|ngayon|karong adlawa|this day|status|time[\s-]?in|time[\s-]?out|adtong|adtung|atong|niadtong|niadtung|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2})\b/.test(
      text
    )
  ) {
    return 'dtr_daily_record';
  }

  if (
    /\b(missing|incomplete|kulang|kuwang|wala|absent|no log|nolog|logs?|entries)\b/.test(
      text
    ) &&
    /\b(logs?|dtr|attendance|time[\s-]?in|time[\s-]?out|this week|week|semanaha|semana|karon|ngayon)\b/.test(
      text
    )
  ) {
    return 'missing_logs';
  }

  if (
    /\b(summary|summarize|summarise|overview|recap|total|count|counts)\b/.test(text) &&
    /\b(leave|leaves|request|requests)\b/.test(text)
  ) {
    return 'leave_request_summary';
  }

  if (
    /\b(who|kinsa|sino|where|asa|kanino|holding|hold|pending with|waiting|awaiting|nasa.*kanino|naa.*kinsa)\b/.test(
      text
    ) &&
    /\b(leave|request|approval|approve|pending|status)\b/.test(text)
  ) {
    return 'leave_approval_tracker';
  }

  if (
    /\b(history|timeline|steps|who approved|who reviewed|kinsa.*approve|kinsa.*review|approval history|review history|action history)\b/.test(
      text
    ) &&
    /\b(leave|request|approval|approved|review|timeline)\b/.test(text)
  ) {
    return 'leave_approval_history';
  }

  if (
    /\b(why|ngano|bakit|gamay|small|low|maliit|nabilin|natira|remaining)\b/.test(
      text
    ) &&
    /\b(balance|credit|credits|available|remaining|leave balance|sick leave|vacation leave|vl|sl)\b/.test(
      text
    )
  ) {
    return 'leave_balance';
  }

  if (
    /\b(why|ngano|bakit|reason|remarks|comment|returned|rejected|declined|denied|gi reject|gibalik|binalik)\b/.test(
      text
    ) &&
    /\b(leave|request|rejected|returned|declined|denied)\b/.test(text)
  ) {
    return 'leave_rejection_reason';
  }

  if (
    /\b((what|which|unsa|unsay|ano).*(leave type|gi file|g-file|filed)|gi file|g-file|filed|did i file|akong.*file|ko.*file|leave type)\b/.test(
      text
    ) &&
    /\b(leave|type|filed|gi file|g-file|request|april|may|june|july|august|september|october|november|december|january|february|march|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec|\d{4}-\d{2}-\d{2})\b/.test(
      text
    ) &&
    /\b(on|sa|adtung|adtong|atong|niadtong|niadtung|that|to|date|day|today|tomorrow|yesterday|ugma|kagahapon|gahapon|sunod|miaging|niaging|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|april|may|june|july|august|september|october|november|december|january|february|march|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\b/.test(
      text
    )
  ) {
    return 'leave_request_lookup';
  }

  if (
    /\b(compare|difference|different|versus| vs |vs\.|unsa.*kalahi|kalahi|pagkaiba|lain.*sa|compare.*leave)\b/.test(
      ` ${text} `
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_type_compare';
  }

  if (
    /\b(attachment|attachments|document|documents|docs|proof|medical certificate|med cert|need.*attach|required.*attach|what.*attach|which.*attach|kinahanglan.*attach|kailangan.*attach)\b/.test(
      text
    ) &&
    (LEAVE_TOPIC_PATTERN.test(text) || !/\b(dtr|attendance|locator|pass slip|wfh|official business|ob)\b/.test(text))
  ) {
    return 'leave_attachment_requirement';
  }

  if (
    isLeaveTypeExplanationQuestion(text) ||
    isLeaveGuidelineSectionQuestion(text) &&
    (LEAVE_TOPIC_PATTERN.test(text) || !/\b(dtr|attendance|locator|pass slip|wfh|official business|ob)\b/.test(text))
  ) {
    return 'leave_guideline_section';
  }

  if (
    /\b(dtr|attendance|daily time|on leave|mahitabo.*dtr|effect.*dtr|impact.*dtr|mark.*dtr|marked.*leave|attendance status)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_dtr_impact';
  }

  if (
    /\b(eligible|eligibility|qualified|qualification|avail|entitled|pwede ba ko|pwede ko|pwede akong|puwede ba ako|qualified ba|eligible ba)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text) &&
    !/\b(\d+\s*(day|days|adlaw)|tomorrow|today|yesterday|ugma|kagahapon|gahapon|\d{4}-\d{2}-\d{2})\b/.test(text)
  ) {
    return 'leave_eligibility_check';
  }

  if (
    isLeaveHowToFileQuestion(text) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_form_guidance';
  }

  if (
    /\b(fill|fill up|field|fields|form|details|what to put|what should i put|i-fill|input|reason field|location|delivery|sick nature)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_form_guidance';
  }

  if (
    /\b(help me file|guide me file|assist me file|tabangi.*file|tabangi ko|mag file ko|mag-file ko|i want to file|gusto ko mag file|gusto nako mag file)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_guided_filing';
  }

  if (
    /\b(pending days|pending balance|pending leave days|asa.*pending|where.*pending|why.*pending|ngano.*pending|bakit.*pending)\b/.test(
      text
    ) &&
    /\b(leave|balance|days|pending)\b/.test(text)
  ) {
    return 'leave_pending_days_explanation';
  }

  if (
    /\b(after filing|mabilin|matira|nabilin|natira|remaining after|balance after|pila.*mabilin|pila.*nabilin|how much.*remain|what.*remain)\b/.test(
      text
    ) &&
    /\b(\d+|day|days|adlaw|leave|sick|vacation|vl|sl)\b/.test(text)
  ) {
    return 'leave_balance_after_filing';
  }

  if (
    /\b(overlap|conflict|already|existing|naa.*leave|may.*leave|on leave|leave.*date|same date|ana nga date)\b/.test(
      text
    ) &&
    /\b(leave|date|day|today|tomorrow|yesterday|ugma|kagahapon|gahapon|sunod|miaging|niaging|adtong|adtung|atong|niadtong|niadtung|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\b/.test(
      text
    )
  ) {
    return 'leave_overlap_check';
  }

  if (
    /\b(attachment|attachments|document|documents|docs|proof|supporting|medical certificate|med cert|need.*attach|required.*attach|kinahanglan.*attach)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_attachment_requirement';
  }

  if (
    /\b(policy|rule|rules|advance|before|deadline|how many days before|pila.*days.*before|kanus-a|when.*file|max|maximum|limit|allowed|pwede.*past|past date|late filing)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_filing_policy';
  }

  if (
    /\b(requirements?|requirement|attachment|document|docs|needed|need|kinahanglan|unsa.*kinahanglan|ano.*kailangan|file.*request|pag file|pag-file)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_requirements';
  }

  if (
    /\b(enough|sapat|kaya|pwede|can i file|can file|file.*leave|leave.*file|available.*for)\b/.test(
      text
    ) &&
    (LEAVE_TOPIC_PATTERN.test(text) || /\b\d+\b/.test(text))
  ) {
    return 'leave_availability_check';
  }

  if (
    /\b(leave types|types of leave|available leave types|unsa.*leave type|ano.*leave type|what leave types)\b/.test(
      text
    )
  ) {
    return 'leave_types';
  }

  if (
    /\b(pending leave|leave.*pending|naa.*pending.*leave|may.*pending.*leave|pending.*request)\b/.test(
      text
    )
  ) {
    return 'pending_leave_requests';
  }

  if (
    /\b(leave request|latest leave|last leave|leave status|status.*leave|ano status.*leave|na-approve.*leave|approved na ba.*leave)\b/.test(
      text
    )
  ) {
    return 'latest_leave_request';
  }

  if (
    /\b(show.*approved.*leave|list.*approved.*leave|all.*approved.*leave|my approved leave|approved leaves|approved.*request)\b/.test(
      text
    )
  ) {
    return 'approved_leave_requests';
  }

  if (
    /\b(rejected leave|leave.*rejected|declined leave|deny.*leave|rejected.*request|gi reject.*leave)\b/.test(
      text
    )
  ) {
    return 'rejected_leave_requests';
  }

  if (
    /\b(leave history|history.*leave|my leaves|leaves nako|leave requests|show.*leave|list.*leave)\b/.test(
      text
    )
  ) {
    return 'leave_history';
  }

  if (
    /\b(leave balance|leave balances|leave credit|leave credits|credits|balance|available leave|remaining leave|pila.*leave|leave.*pila|ilan.*leave|leave.*ilan|sick leave|vacation leave|paternity leave|maternity leave|adoption leave)\b/.test(
      text
    )
  ) {
    return 'leave_balance';
  }

  if (
    /\b(locator|locator slip|pass slip|wfh|work from home|official business|ob request|ob|on field|field work|fieldwork|out of office|outside office|travel order)\b/.test(text) &&
    /\b(types?|kinds?|options?|available.*locator|locator.*available|what.*locator.*file|which.*locator.*file|what.*type|which.*type|what is.*(wfh|work from home|pass slip|official business|ob|fieldwork)|unsa.*(wfh|work from home|pass slip|official business|ob|fieldwork)|ano.*(wfh|work from home|pass slip|official business|ob|fieldwork)|unsa.*type|unsay.*type|ano.*type|list.*locator|how about|what about)\b/.test(text)
  ) {
    return 'locator_types';
  }

  if (
    /\b(locator|locator slip|pass slip|wfh|work from home|official business|ob request|ob|on field|field work|fieldwork|out of office|outside office|travel order)\b/.test(text) &&
    /\b(requirements?|requirement|attachment|document|docs|need|needed|kinahanglan|kailangan|rules?|policy|how to file|how do i file|unsaon|paano|pwede|can i file|coverage|cover|slots?)\b/.test(text)
  ) {
    return 'locator_requirements';
  }

  if (
    /\b(locator|locator slip|pass slip|wfh|work from home|official business|ob request|ob|on field|field work|fieldwork|out of office|outside office|travel order)\b/.test(text) &&
    /\b(summary|summarize|summarise|overview|recap|total|count|counts|pila|kabuok|ilan|how many|history|list|show|records|requests|this month|this week|month|week|bulan|bulana|semana|semanaha)\b/.test(text)
  ) {
    return 'locator_summary';
  }

  if (
    /\b(locator|locator slip|pass slip|wfh|work from home|official business|ob request|ob|on field|field work|fieldwork|out of office|outside office|travel order|na-approve|approved.*locator|accepted.*locator|status.*locator)\b/.test(text) &&
    /\b(status|approve|approved|accepted|pending|rejected|returned|cancelled|canceled|where|asa|kinsa|sino|who|holding|waiting|latest|last|recent|today|tomorrow|yesterday|ugma|gahapon|kagahapon|date|january|february|march|april|may|june|july|august|september|october|november|december|\d{4}-\d{2}-\d{2})\b/.test(text)
  ) {
    return 'locator_status';
  }

  if (
    /\b(locator|pass slip|locator slip|wfh|work from home|official business|ob request|on field|field work|fieldwork|out of office|outside office|travel order|na-approve|approved.*locator|accepted.*locator|status.*locator)\b/.test(
      text
    )
  ) {
    return 'latest_locator_request';
  }

  if (
    /\b(dtr|attendance|late|time[\s-]?in|time[\s-]?out|status)\b/.test(text) &&
    /\b(today|tomorrow|yesterday|ugma|kagahapon|gahapon|karon|ngayon|karong adlawa|this day|late|status|time[\s-]?in|time[\s-]?out)\b/.test(
      text
    )
  ) {
    return 'today_dtr';
  }

  // Catch-all for calculated intents that may appear in broader phrasing
  if (
    /\b(how many hours|total hours|hours worked|hours rendered|pila.*oras|ilan oras|working hours)\b/.test(text)
  ) {
    return 'dtr_hours_summary';
  }

  if (
    /\b(if i (take|file|avail|use)|kung mag file|kung mag take|pila mabilin|pila matira|balance after|remaining if|left if|magkano mabilin)\b/.test(text) &&
    /\b(leave|sick|vacation|sl|vl|day|days|adlaw|\d+)\b/.test(text)
  ) {
    return 'leave_balance_projection';
  }

  return null;
}

function detectEmployeeAssistantIntent(message, explicitIntent) {
  return scoreEmployeeAssistantIntent(message, explicitIntent).intent;
}

module.exports = {
  detectEmployeeAssistantIntent,
  normalizeIntent,
  scoreEmployeeAssistantIntent,
  scoreFuzzyIntents,
};
