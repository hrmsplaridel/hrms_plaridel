const { detectAssistantLanguage } = require('./dtrAssistantLanguage');
const {
  extractMessageEntities,
  extractDayCount,
  normalizeLeaveTypeHint,
  normalizeLocatorTypeHint,
} = require('./dtrAssistantMessageExtraction');
const { isLeaveCreditRequirementQuestion } = require('./dtrAssistantIntentService');
const { parseAssistantDateRange } = require('../../utils/dateRangeParser');

const GUIDED_FILING_INTENTS = new Set([
  'leave_guided_filing',
  'leave_availability_check',
  'locator_guided_filing',
  'locator_availability_check',
]);

function lower(value) {
  return String(value || '').toLowerCase();
}

function hasDateHint(text, memory, context) {
  if (context?.date_range?.startDate) {
    const label = lower(context.date_range.label);
    if (label && label !== 'today') return true;
    if (/\b(today|karon|ugma|tomorrow|yesterday|gahapon|week|month|semana|bulan)\b/i.test(text)) {
      return true;
    }
  }
  const parsed = parseAssistantDateRange(String(text || ''));
  if (parsed?.startDate) {
    const label = lower(parsed.label);
    return label && label !== 'today';
  }
  if (memory?.dateRange?.startDate && memory.dateRange.label !== 'today') return true;
  return false;
}

function resolveLeaveType(text, memory, context) {
  const fromText = normalizeLeaveTypeHint(text);
  if (fromText) return fromText;
  if (memory?.leaveType) return memory.leaveType;
  if (memory?.topics?.leave?.leaveType) return memory.topics.leave.leaveType;
  const types = context?.leave_types || [];
  for (const type of types) {
    const code = lower(type.code || type.leave_type || '');
    if (code && lower(text).includes(code.replace(/_/g, ' '))) return code;
  }
  return null;
}

function resolveLocatorType(text, memory) {
  const fromText = normalizeLocatorTypeHint(text);
  if (fromText) return fromText;
  if (memory?.locatorType) return memory.locatorType;
  if (memory?.topics?.locator?.locatorType) return memory.topics.locator.locatorType;
  return null;
}

function hasDayCountHint(text, memory) {
  if (memory?.dayCount != null && Number.isFinite(Number(memory.dayCount))) {
    return Number(memory.dayCount) > 0;
  }
  return (
    extractDayCount(text) != null ||
    extractDayCount(memory?.lastUserMessage || '') != null
  );
}

function isSingleDayRange(range) {
  const startDate = String(range?.startDate || '').slice(0, 10);
  const endDate = String(range?.endDate || startDate).slice(0, 10);
  return Boolean(startDate && endDate === startDate);
}

function hasSingleDayDateHint(text, memory, context, dateKnown) {
  if (!dateKnown) return false;
  const parsed = parseAssistantDateRange(String(text || ''));
  if (isSingleDayRange(parsed)) return true;
  if (isSingleDayRange(memory?.dateRange)) return true;
  return isSingleDayRange(context?.date_range);
}

function missingLeaveFields({ text, memory, context, intent }) {
  const fields = [];
  const leaveType = resolveLeaveType(text, memory, context);
  const dateKnown = hasDateHint(text, memory, context);
  if (!leaveType) fields.push('leaveType');
  if (!dateKnown) fields.push('date');
  if (
    (intent === 'leave_availability_check' || intent === 'leave_guided_filing') &&
    !hasDayCountHint(text, memory) &&
    !hasSingleDayDateHint(text, memory, context, dateKnown)
  ) {
    fields.push('days');
  }
  return { fields, leaveType };
}

function missingLocatorFields({ text, memory, context, intent }) {
  const fields = [];
  const locatorType = resolveLocatorType(text, memory);
  const storedDestination =
    memory?.topics?.locator?.locatorPrefill?.destination ||
    memory?.locatorPrefill?.destination ||
    null;
  if (!locatorType) fields.push('locatorType');
  if (!hasDateHint(text, memory, context)) fields.push('date');
  if (
    (intent === 'locator_availability_check' || intent === 'locator_guided_filing') &&
    locatorType === 'locator' &&
    !storedDestination &&
    !extractMessageEntities(text, memory).locatorPrefill.destination
  ) {
    fields.push('destination');
  }
  return { fields, locatorType };
}

function missingDtrCorrectionFields({ text, memory, context }) {
  const fields = [];
  if (!hasDateHint(text, memory, context)) fields.push('date');
  const entities = extractMessageEntities(text, memory);
  if (!entities.dtrSlot) fields.push('slot');
  return { fields };
}

const LEAVE_TYPE_LABELS = {
  sick: 'sick leave',
  vacation: 'vacation leave',
  maternity: 'maternity leave',
  paternity: 'paternity leave',
  adoption: 'adoption leave',
  solo_parent: 'solo parent leave',
  vawc: 'VAWC leave',
  calamity: 'calamity leave',
  mandatory: 'mandatory leave',
  special_privilege: 'special privilege leave',
};

const LOCATOR_TYPE_LABELS = {
  work_from_home: 'Work From Home',
  pass_slip: 'pass slip',
  locator: 'Official Business',
};

function leaveTypeLabel(code) {
  if (!code) return null;
  return LEAVE_TYPE_LABELS[code] || `${String(code).replace(/_/g, ' ')} leave`;
}

function locatorTypeLabel(code) {
  if (!code) return null;
  return LOCATOR_TYPE_LABELS[code] || String(code).replace(/_/g, ' ');
}

function dateLabel(value, language) {
  const label = lower(value).trim();
  if (!label) return null;
  if (label === 'tomorrow') {
    return language === 'bisaya' ? 'ugma' : language === 'tagalog' ? 'bukas' : 'tomorrow';
  }
  if (label === 'today') {
    return language === 'bisaya' ? 'karon' : language === 'tagalog' ? 'ngayon' : 'today';
  }
  if (label === 'yesterday') {
    return language === 'bisaya'
      ? 'gahapon'
      : language === 'tagalog'
        ? 'kahapon'
        : 'yesterday';
  }
  return String(value).trim();
}

function daysLabel(count, language) {
  if (count == null) return null;
  if (language === 'bisaya') return `${count} ka adlaw`;
  if (language === 'tagalog') return `${count} araw`;
  return `${count} day${Number(count) === 1 ? '' : 's'}`;
}

const FIELD_ORDER = {
  leave: ['leaveType', 'date', 'days'],
  locator: ['locatorType', 'date', 'destination'],
  dtr: ['date', 'slot'],
};

// Builds a short acknowledgement of the value the employee just provided so the
// guided flow reads like a conversation instead of repeating the same header.
function acknowledgedValue(nextField, topic, language, known) {
  const order = FIELD_ORDER[topic] || [];
  const index = order.indexOf(nextField);
  if (index <= 0) return null;
  for (let i = index - 1; i >= 0; i -= 1) {
    const field = order[i];
    if (field === 'leaveType' && known.leaveType) return leaveTypeLabel(known.leaveType);
    if (field === 'locatorType' && known.locatorType) {
      return locatorTypeLabel(known.locatorType);
    }
    if (field === 'date' && known.date) return dateLabel(known.date, language);
    if (field === 'days' && known.days != null) return daysLabel(known.days, language);
    if (field === 'destination' && known.destination) return known.destination;
  }
  return null;
}

function guidedOpener(language) {
  if (language === 'bisaya') return 'Sige, tabangan tika.';
  if (language === 'tagalog') return 'Sige, tutulungan kita.';
  return 'Sure, I can help with that.';
}

function guidedAcknowledgement(value, language) {
  if (language === 'bisaya') return `Sige, ${value}.`;
  if (language === 'tagalog') return `Sige, ${value}.`;
  return `Got it — ${value}.`;
}

function clarificationQuestion(field, topic, language) {
  if (topic === 'leave') {
    if (field === 'leaveType') {
      return language === 'bisaya'
        ? 'Unsa nga leave type? (sick leave, vacation leave, special leave, uban pa)'
        : language === 'tagalog'
          ? 'Anong leave type? (sick leave, vacation leave, special leave, iba pa)'
          : 'Which leave type do you want? (sick leave, vacation leave, special leave, etc.)';
    }
    if (field === 'date') {
      return language === 'bisaya'
        ? 'Para asa nga petsa imong i-file? (pananglitan: ugma, June 30, or 2 days starting Monday)'
        : language === 'tagalog'
          ? 'Para sa anong petsa mo ifa-file? (halimbawa: bukas, June 30, o 2 days starting Monday)'
          : 'For what date(s) should I check or file? (e.g. tomorrow, June 30, or 2 days starting Monday)';
    }
    if (field === 'days') {
      return language === 'bisaya'
        ? 'Pila ka adlaw imong gusto i-file?'
        : language === 'tagalog'
          ? 'Ilang araw ang gusto mong i-file?'
          : 'How many day(s) do you want to file?';
    }
  }

  if (topic === 'locator') {
    if (field === 'locatorType') {
      return language === 'bisaya'
        ? 'Unsa nga locator type? Official Business, Pass Slip, o Work From Home (WFH)?'
        : language === 'tagalog'
          ? 'Anong locator type? Official Business, Pass Slip, o Work From Home (WFH)?'
          : 'Which locator type? Official Business, Pass Slip, or Work From Home (WFH)?';
    }
    if (field === 'date') {
      return language === 'bisaya'
        ? 'Asa nga workday ang imong locator slip? (pananglitan: ugma or June 30)'
        : language === 'tagalog'
          ? 'Para sa anong workday ang locator slip? (halimbawa: bukas o June 30)'
          : 'Which workday should the locator slip cover? (e.g. tomorrow or June 30)';
    }
    if (field === 'destination') {
      return language === 'bisaya'
        ? 'Asa ang imong destination/office? (pananglitan: Cebu City Hall)'
        : language === 'tagalog'
          ? 'Saan ang destination/office mo? (halimbawa: Cebu City Hall)'
          : 'What destination or office should I use? (e.g. Cebu City Hall)';
    }
  }

  if (topic === 'dtr') {
    if (field === 'date') {
      return language === 'bisaya'
        ? 'Asa nga petsa ang missing/incorrect log? (pananglitan: kagahapon AM out)'
        : language === 'tagalog'
          ? 'Sa anong petsa ang missing/incorrect log? (halimbawa: kahapon AM out)'
          : 'Which date has the missing or incorrect log? (e.g. yesterday AM out)';
    }
    if (field === 'slot') {
      return language === 'bisaya'
        ? 'Unsa nga slot ang kulang o sayop? AM in, AM out, PM in, o PM out?'
        : language === 'tagalog'
          ? 'Aling slot ang kulang o mali? AM in, AM out, PM in, o PM out?'
          : 'Which slot is missing or wrong? AM in, AM out, PM in, or PM out?';
    }
  }

  return null;
}

function isPendingClarificationAnswer(text, memory) {
  const pending = memory?.pendingClarification;
  if (!pending?.field) return false;

  const value = String(text || '').trim();
  const normalized = lower(value);
  const wordCount = normalized.split(/\s+/).filter(Boolean).length;
  const asksForInformation =
    /\b(requirements?|attachment|documents?|status|remarks?|reason|why|ngano|bakit|how to|unsaon|paano|who|kinsa|sino|policy|rules?|balance|credits?)\b/.test(
      normalized
    );
  const mentionsLeave =
    /\b(leave|sick|vacation|maternity|paternity|adoption|solo parent|vawc|calamity|vl|sl)\b/.test(
      normalized
    );
  const mentionsLocator =
    /\b(locator|locator slip|pass slip|wfh|work from home|official business|fieldwork)\b/.test(
      normalized
    );
  const mentionsDtr =
    /\b(dtr|attendance|time[\s-]?in|time[\s-]?out|late|undertime|overtime|absent|missing log|pm out|am out|pm in|am in)\b/.test(
      normalized
    );
  const changesTopic =
    (pending.topic === 'leave' && (mentionsLocator || mentionsDtr)) ||
    (pending.topic === 'locator' && (mentionsLeave || mentionsDtr)) ||
    (pending.topic === 'dtr' && (mentionsLeave || mentionsLocator));
  if (asksForInformation || changesTopic) return false;

  if (pending.field === 'leaveType') {
    return Boolean(normalizeLeaveTypeHint(value));
  }
  if (pending.field === 'locatorType') {
    return Boolean(normalizeLocatorTypeHint(value));
  }
  if (pending.field === 'date') {
    const hasExplicitDateText =
      /\b(today|tomorrow|yesterday|karon|ugma|gahapon|kagahapon|ngayon|bukas|kahapon|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|week|month|semana|semanaha|bulan|bulana|buwan|buwana|pay\s*period|cutoff|next day|following day|sunod adlaw|previous day|day before)\b/.test(
        normalized
      ) ||
      /\b\d{4}-\d{2}-\d{2}\b/.test(normalized) ||
      /\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}\b/.test(
        normalized
      );
    return hasExplicitDateText && Boolean(parseAssistantDateRange(value)?.startDate);
  }
  if (pending.field === 'days') {
    return wordCount <= 8 && extractDayCount(value) != null;
  }
  if (pending.field === 'destination') {
    return wordCount <= 12 && !/[?]$/.test(normalized);
  }
  if (pending.field === 'slot') {
    return /\b(am in|am out|pm in|pm out|time in|time out)\b/.test(normalized);
  }
  return false;
}

function interruptsPendingClarification(text, memory) {
  if (!memory?.pendingClarification?.field) return false;
  if (isPendingClarificationAnswer(text, memory)) return false;
  const value = lower(text);
  return (
    /[?]$/.test(value.trim()) ||
    /\b(what|why|how|when|where|who|which|can|could|do i|does|is|are|need|unsa|ngano|pila|asa|kinsa|pwede|puwede|kinahanglan|ano|bakit|ilan|saan|sino|kailangan)\b/.test(
      value
    )
  );
}

function evaluateGuidedClarification({ intent, text, context, memory }) {
  if (!GUIDED_FILING_INTENTS.has(intent)) return null;
  if (isLeaveCreditRequirementQuestion(text)) return null;

  const language = detectAssistantLanguage(text);
  let topic = 'leave';
  let fields = [];
  let leaveType = null;
  let locatorType = null;

  if (intent.startsWith('leave_')) {
    const leave = missingLeaveFields({ text, memory, context, intent });
    fields = leave.fields;
    leaveType = leave.leaveType;
    topic = 'leave';
  } else if (intent.startsWith('locator_')) {
    const locator = missingLocatorFields({ text, memory, context, intent });
    fields = locator.fields;
    locatorType = locator.locatorType;
    topic = 'locator';
  } else if (intent === 'dtr_correction_guidance') {
    const dtr = missingDtrCorrectionFields({ text, memory, context });
    fields = dtr.fields;
    topic = 'dtr';
  }

  if (fields.length === 0) return null;

  const nextField = fields[0];
  const question = clarificationQuestion(nextField, topic, language);
  if (!question) return null;

  const known = {
    leaveType,
    locatorType,
    date: memory?.dateRange?.label || context?.date_range?.label || null,
    days: memory?.dayCount ?? null,
    destination: memory?.locatorPrefill?.destination || null,
  };
  const ackValue = acknowledgedValue(nextField, topic, language, known);
  const leadIn = ackValue
    ? guidedAcknowledgement(ackValue, language)
    : guidedOpener(language);

  return {
    intent,
    topic,
    content: `${leadIn} ${question}`,
    pendingClarification: {
      topic,
      intent,
      field: nextField,
      fieldsRemaining: fields.slice(1),
      leaveType,
      locatorType,
    },
  };
}

function applyPendingClarificationAnswer(text, memory) {
  const pending = memory?.pendingClarification;
  if (!pending?.field) return null;

  const patch = {
    leaveType: pending.leaveType || null,
    locatorType: pending.locatorType || null,
    leavePrefill: null,
    locatorPrefill: null,
    dateRange: null,
    pendingClarification: null,
  };
  if (!isPendingClarificationAnswer(text, memory)) {
    patch.pendingClarification = { ...pending };
    return patch;
  }

  const value = String(text || '').trim();
  const entities = extractMessageEntities(value);
  const parsedDateRange = parseAssistantDateRange(value);
  const suppliedDateRange = hasDateHint(
    value,
    null,
    { date_range: parsedDateRange }
  )
    ? parsedDateRange
    : null;

  if (pending.field === 'leaveType') {
    patch.leaveType = normalizeLeaveTypeHint(value) || pending.leaveType;
  } else if (pending.field === 'locatorType') {
    patch.locatorType = normalizeLocatorTypeHint(value) || pending.locatorType;
  } else if (pending.field === 'date') {
    patch.dateRange = parsedDateRange;
  } else if (pending.field === 'days') {
    const dayCount = extractDayCount(value);
    if (dayCount == null) {
      patch.pendingClarification = {
        topic: pending.topic,
        intent: pending.intent,
        field: 'days',
        fieldsRemaining: pending.fieldsRemaining || [],
        leaveType: pending.leaveType || patch.leaveType || null,
        locatorType: pending.locatorType || patch.locatorType || null,
      };
      return patch;
    }
    patch.dayCount = dayCount;
  } else if (pending.field === 'destination') {
    patch.locatorPrefill = {
      destination: entities.locatorPrefill?.destination || value,
    };
  } else if (pending.field === 'slot') {
    const slot = lower(value);
    if (slot.includes('am in')) patch.dtrSlot = 'AM in';
    else if (slot.includes('am out')) patch.dtrSlot = 'AM out';
    else if (slot.includes('pm in')) patch.dtrSlot = 'PM in';
    else if (slot.includes('pm out')) patch.dtrSlot = 'PM out';
  }

  if (pending.topic === 'leave') {
    patch.leaveType = patch.leaveType || entities.leaveType || pending.leaveType || null;
    patch.dateRange = patch.dateRange || suppliedDateRange;
    if (entities.dayCount != null) patch.dayCount = entities.dayCount;
    if (patch.dayCount == null && isSingleDayRange(patch.dateRange)) {
      patch.dayCount = 1;
    }
    if (Object.keys(entities.leavePrefill || {}).length > 0) {
      patch.leavePrefill = entities.leavePrefill;
    }
  } else if (pending.topic === 'locator') {
    patch.locatorType =
      patch.locatorType || entities.locatorType || pending.locatorType || null;
    patch.dateRange = patch.dateRange || suppliedDateRange;
    if (Object.keys(entities.locatorPrefill || {}).length > 0) {
      patch.locatorPrefill = {
        ...(patch.locatorPrefill || {}),
        ...entities.locatorPrefill,
      };
    }
  } else if (pending.topic === 'dtr') {
    patch.dateRange = patch.dateRange || suppliedDateRange;
    patch.dtrSlot = patch.dtrSlot || entities.dtrSlot || null;
  }

  const fieldResolved = (field) => {
    if (field === 'leaveType') return Boolean(patch.leaveType);
    if (field === 'locatorType') return Boolean(patch.locatorType);
    if (field === 'date') return Boolean(patch.dateRange?.startDate);
    if (field === 'days') return Number(patch.dayCount) > 0;
    if (field === 'destination') {
      return Boolean(patch.locatorPrefill?.destination);
    }
    if (field === 'slot') return Boolean(patch.dtrSlot);
    return false;
  };
  const remaining = (pending.fieldsRemaining || []).filter(
    (field) => !fieldResolved(field)
  );
  if (remaining.length > 0) {
    patch.pendingClarification = {
      topic: pending.topic,
      intent: pending.intent,
      field: remaining[0],
      fieldsRemaining: remaining.slice(1),
      leaveType: patch.leaveType || pending.leaveType || null,
      locatorType: patch.locatorType || pending.locatorType || null,
    };
  }

  return patch;
}

module.exports = {
  GUIDED_FILING_INTENTS,
  applyPendingClarificationAnswer,
  evaluateGuidedClarification,
  interruptsPendingClarification,
  isPendingClarificationAnswer,
};
