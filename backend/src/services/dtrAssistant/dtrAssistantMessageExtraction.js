const { parseAssistantDateRange } = require('../../utils/dateRangeParser');

function lower(value) {
  return String(value || '').toLowerCase();
}

function compact(value, max = 180) {
  return String(value || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function prefillSourceText(text, memory) {
  const chunks = [];
  if (text) chunks.push(String(text));
  if (memory?.lastUserMessage) chunks.push(memory.lastUserMessage);
  for (const topic of ['leave', 'locator']) {
    if (memory?.topics?.[topic]?.text) chunks.push(memory.topics[topic].text);
  }
  for (const turn of memory?.history || []) {
    if (turn?.text) chunks.push(turn.text);
  }
  return chunks.join(' ').replace(/\s+/g, ' ').trim();
}

function trimPrefillValue(value) {
  const trimmed = compact(value, 180);
  if (!trimmed) return null;
  const stopMatch = trimmed.match(
    /^(.+?)(?:\s+(?:for|because|due to|kay|tungod|para|tomorrow|ugma|today|on|from|help|file|leave|locator|wfh)\b|[.?!]|$)/i
  );
  const candidate = compact(stopMatch?.[1] || trimmed, 180);
  return candidate.length >= 3 ? candidate : null;
}

function firstCapture(text, patterns) {
  for (const pattern of patterns) {
    const match = text.match(pattern);
    const value = trimPrefillValue(match?.[1] || match?.[0]);
    if (value) return value;
  }
  return null;
}

function normalizeLeaveTypeHint(value) {
  const text = lower(value);
  if (!text) return null;
  if (/\bsick|sl\b/.test(text)) return 'sick';
  if (/\bvacation|vl\b/.test(text)) return 'vacation';
  if (/\bmaternity\b/.test(text)) return 'maternity';
  if (/\bpaternity\b/.test(text)) return 'paternity';
  if (/\badoption\b/.test(text)) return 'adoption';
  if (/\bsolo parent\b/.test(text)) return 'solo_parent';
  if (/\bvawc\b/.test(text)) return 'vawc';
  if (/\bcalamity\b/.test(text)) return 'calamity';
  if (/\bmandatory|forced\b/.test(text)) return 'mandatory';
  if (/\bspecial privilege\b/.test(text)) return 'special_privilege';
  return null;
}

function normalizeLocatorTypeHint(value) {
  const text = lower(value);
  if (!text) return null;
  if (/\bwfh|work from home\b/.test(text)) return 'work_from_home';
  if (/\bpass slip\b/.test(text)) return 'pass_slip';
  if (/\bofficial business|\bob\b|\blocator\b/.test(text)) return 'locator';
  return null;
}

function normalizeDtrSlotHint(value) {
  const text = lower(value);
  if (!text) return null;
  if (/\bam in|time in am\b/.test(text)) return 'AM in';
  if (/\bam out\b/.test(text)) return 'AM out';
  if (/\bpm in\b/.test(text)) return 'PM in';
  if (/\bpm out|time out pm\b/.test(text)) return 'PM out';
  return null;
}

const DAY_COUNT_WORDS = {
  one: 1,
  isa: 1,
  usa: 1,
  uno: 1,
  two: 2,
  duha: 2,
  dos: 2,
  dalawa: 2,
  three: 3,
  tulo: 3,
  tres: 3,
  tatlo: 3,
  four: 4,
  upat: 4,
  kwatro: 4,
  apat: 4,
  five: 5,
  lima: 5,
  singko: 5,
  six: 6,
  unom: 6,
  seven: 7,
  pito: 7,
  eight: 8,
  walo: 8,
  nine: 9,
  siyam: 9,
  ten: 10,
  napulo: 10,
};

function parseDayCountToken(token) {
  const normalized = lower(token);
  if (!normalized) return null;
  if (Object.prototype.hasOwnProperty.call(DAY_COUNT_WORDS, normalized)) {
    return DAY_COUNT_WORDS[normalized];
  }
  const value = Number(normalized);
  return Number.isFinite(value) && value > 0 ? value : null;
}

function extractDayCount(text) {
  const source = lower(String(text || '').trim());
  if (!source) return null;

  const patterns = [
    /\b(\d+(?:\.\d+)?)\s*(?:day|days|adlaw|ka\s*adlaw|araw)\b/,
    /\b(?:file|take|use|mag[- ]?file)\s+(?:ug\s+)?(\d+(?:\.\d+)?)\b/,
    /\b(\d+(?:\.\d+)?)\b/,
  ];
  for (const pattern of patterns) {
    const match = source.match(pattern);
    if (!match?.[1]) continue;
    const value = Number(match[1]);
    if (Number.isFinite(value) && value > 0 && value <= 365) return value;
  }

  const wordMatch = source.match(
    /\b(one|two|three|four|five|six|seven|eight|nine|ten|isa|usa|uno|duha|dos|dalawa|tulo|tres|tatlo|upat|kwatro|apat|lima|singko|unom|walo|siyam|napulo)\b(?:\s*(?:ka\s*)?(?:day|days|adlaw|araw))?\b/
  );
  if (wordMatch?.[1]) {
    const value = parseDayCountToken(wordMatch[1]);
    if (value != null) return value;
  }

  return null;
}

function extractLeavePrefill(text, memory) {
  const source = prefillSourceText(text, memory);
  if (!source) return {};

  const result = {};
  const reason = firstCapture(source, [
    /\b(?:for|because|due to|kay|tungod sa|para sa|reason(?:\s+is)?(?:\s*:)?)\s+(.{8,120}?)(?:[.?!]|,\s*(?:from|starting|until|on|sa|ugma|tomorrow|today|june|january|february|march|april|may|july|august|september|october|november|december)\b|$)/i,
  ]);
  if (reason && !/^(?:sick|vacation|leave|tomorrow|ugma|today)\b/i.test(reason)) {
    result.reason = reason;
  }

  const location = firstCapture(source, [
    /\blocation(?:\s+details|\s+is)?(?:\s*:)?\s+(.{3,100})/i,
    /\b(?:in|at|sa)\s+([A-Z][A-Za-z0-9\s,.-]{3,80})/,
    /\b(?:destination|destinasyon)(?:\s*:)?\s+(.{3,100})/i,
  ]);
  if (location && !/^(?:the|a|an|my|leave|file)\b/i.test(location)) {
    result.locationDetails = location;
  }

  if (/\babroad\b|\boutside (?:the )?philippines\b|\bluwag sa pilipinas\b/i.test(source)) {
    result.locationOption = 'abroad';
  } else if (
    /\bwithin (?:the )?philippines\b|\bsulod sa pilipinas\b|\bwithin ph\b|\bnasa pilipinas\b/i.test(
      source
    )
  ) {
    result.locationOption = 'within_philippines';
  }

  return result;
}

function extractLocatorPrefill(text, memory) {
  const source = prefillSourceText(text, memory);
  if (!source) return {};

  const result = {};
  const reason = firstCapture(source, [
    /\b(?:reason(?:\s+is)?(?:\s*:)?|because|due to|kay|tungod sa|para sa)\s+(.{8,120}?)(?:[.?!]|$)/i,
  ]);
  if (reason) result.reason = reason;

  const destination = firstCapture(source, [
    /\b(?:destination|office|location|punto|destinasyon)(?:\s+is|\s*:)?\s+(.{3,100})/i,
    /\b(?:at|in|sa)\s+(?:the\s+)?([A-Z][A-Za-z0-9\s,.-]{3,80})/,
  ]);
  if (destination) result.destination = destination;

  if (/\bwhole day\b|\bwhole-day\b|\btibuok adlaw\b|\bbuong araw\b/i.test(source)) {
    result.amIn = true;
    result.amOut = true;
    result.pmIn = true;
    result.pmOut = true;
  } else if (/\bam only\b|\bam slot\b|\bAM only\b/i.test(source)) {
    result.amIn = true;
    result.amOut = true;
  } else if (/\bpm only\b|\bpm slot\b|\bPM only\b/i.test(source)) {
    result.pmIn = true;
    result.pmOut = true;
  }

  return result;
}

function extractMessageEntities(text, memory = null) {
  const source = prefillSourceText(text, memory);
  const current = String(text || '');
  const leavePrefill = extractLeavePrefill(text, memory);
  const locatorPrefill = extractLocatorPrefill(text, memory);
  const dateRange = parseAssistantDateRange(source);
  const hasDateHint =
    Boolean(dateRange?.startDate) &&
    !/^(today|karon)$/i.test(String(dateRange.label || ''));

  // The latest message wins for type/slot/day hints; only fall back to memory
  // context when the current message does not state one itself. This prevents a
  // previously chosen leave type (e.g. sick) from overriding a new one (vacation).
  return {
    leaveType: normalizeLeaveTypeHint(current) || normalizeLeaveTypeHint(source),
    locatorType: normalizeLocatorTypeHint(current) || normalizeLocatorTypeHint(source),
    dayCount: extractDayCount(current) ?? extractDayCount(source),
    dtrSlot: normalizeDtrSlotHint(current) || normalizeDtrSlotHint(source),
    dateRange: hasDateHint ? dateRange : null,
    leavePrefill,
    locatorPrefill,
    reason: leavePrefill.reason || locatorPrefill.reason || null,
    destination: locatorPrefill.destination || leavePrefill.locationDetails || null,
    locationDetails: leavePrefill.locationDetails || null,
    locationOption: leavePrefill.locationOption || null,
  };
}

function mergePlannerExtraction(rulesExtraction, plannerExtraction) {
  const rules = rulesExtraction || {};
  const planner = plannerExtraction || {};
  const mergedLeavePrefill = {
    ...(rules.leavePrefill || {}),
    ...(planner.leavePrefill || {}),
  };
  if (planner.reason && !mergedLeavePrefill.reason) mergedLeavePrefill.reason = planner.reason;
  if (planner.locationDetails && !mergedLeavePrefill.locationDetails) {
    mergedLeavePrefill.locationDetails = planner.locationDetails;
  }
  if (planner.locationOption && !mergedLeavePrefill.locationOption) {
    mergedLeavePrefill.locationOption = planner.locationOption;
  }

  const mergedLocatorPrefill = {
    ...(rules.locatorPrefill || {}),
    ...(planner.locatorPrefill || {}),
  };
  if (planner.reason && !mergedLocatorPrefill.reason) mergedLocatorPrefill.reason = planner.reason;
  if (planner.destination && !mergedLocatorPrefill.destination) {
    mergedLocatorPrefill.destination = planner.destination;
  }
  for (const slot of ['amIn', 'amOut', 'pmIn', 'pmOut']) {
    if (planner[slot] === true) mergedLocatorPrefill[slot] = true;
  }

  return {
    leaveType: planner.leaveType || rules.leaveType || null,
    locatorType: planner.locatorType || rules.locatorType || null,
    dayCount: planner.dayCount ?? rules.dayCount ?? null,
    dtrSlot: planner.dtrSlot || rules.dtrSlot || null,
    dateRange: planner.dateRange || rules.dateRange || null,
    leavePrefill: mergedLeavePrefill,
    locatorPrefill: mergedLocatorPrefill,
    reason: planner.reason || rules.reason || null,
    destination: planner.destination || rules.destination || null,
    locationDetails: planner.locationDetails || rules.locationDetails || null,
    locationOption: planner.locationOption || rules.locationOption || null,
  };
}

function normalizePlannerExtraction(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const leaveType = normalizeLeaveTypeHint(raw.leaveType);
  const locatorType = normalizeLocatorTypeHint(raw.locatorType);
  const dtrSlot = normalizeDtrSlotHint(raw.dtrSlot || raw.slot);
  const dayCountRaw = raw.dayCount ?? raw.days;
  const dayCount =
    dayCountRaw == null || dayCountRaw === ''
      ? null
      : Number.isFinite(Number(dayCountRaw))
        ? Number(dayCountRaw)
        : null;
  const leavePrefill = {};
  const locatorPrefill = {};
  if (raw.reason) {
    const reason = trimPrefillValue(raw.reason);
    if (reason) {
      leavePrefill.reason = reason;
      locatorPrefill.reason = reason;
    }
  }
  if (raw.destination) {
    const destination = trimPrefillValue(raw.destination);
    if (destination) locatorPrefill.destination = destination;
  }
  if (raw.locationDetails) {
    const locationDetails = trimPrefillValue(raw.locationDetails);
    if (locationDetails) leavePrefill.locationDetails = locationDetails;
  }
  if (raw.locationOption) {
    const option = lower(raw.locationOption);
    if (option.includes('abroad')) leavePrefill.locationOption = 'abroad';
    if (option.includes('within')) leavePrefill.locationOption = 'within_philippines';
  }
  for (const slot of ['amIn', 'amOut', 'pmIn', 'pmOut']) {
    if (raw[slot] === true || lower(raw[slot]) === 'true') locatorPrefill[slot] = true;
  }

  return {
    leaveType,
    locatorType,
    dayCount,
    dtrSlot,
    dateRange: null,
    leavePrefill,
    locatorPrefill,
    reason: leavePrefill.reason || locatorPrefill.reason || null,
    destination: locatorPrefill.destination || null,
    locationDetails: leavePrefill.locationDetails || null,
    locationOption: leavePrefill.locationOption || null,
  };
}

module.exports = {
  extractMessageEntities,
  extractLeavePrefill,
  extractLocatorPrefill,
  mergePlannerExtraction,
  normalizePlannerExtraction,
  prefillSourceText,
  normalizeLeaveTypeHint,
  normalizeLocatorTypeHint,
  normalizeDtrSlotHint,
  extractDayCount,
};
