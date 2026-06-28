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

function mergePrefill(previous = {}, next = {}) {
  const merged = { ...previous };
  for (const [key, value] of Object.entries(next)) {
    if (value == null || value === '') continue;
    merged[key] = value;
  }
  return merged;
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

function buildLeaveActionPayload({ text, memory, leaveType, rangePayload }) {
  const stored =
    memory?.topics?.leave?.leavePrefill ||
    memory?.leavePrefill ||
    {};
  const extracted = extractLeavePrefill(text, memory);
  const leavePrefill = mergePrefill(stored, extracted);

  return {
    ...rangePayload,
    leaveType,
    ...(leavePrefill.reason ? { reason: leavePrefill.reason } : {}),
    ...(leavePrefill.locationDetails ? { locationDetails: leavePrefill.locationDetails } : {}),
    ...(leavePrefill.locationOption ? { locationOption: leavePrefill.locationOption } : {}),
  };
}

function buildLocatorActionPayload({ text, memory, locatorType, rangePayload }) {
  const stored =
    memory?.topics?.locator?.locatorPrefill ||
    memory?.locatorPrefill ||
    {};
  const extracted = extractLocatorPrefill(text, memory);
  const locatorPrefill = mergePrefill(stored, extracted);
  const slipDate = rangePayload.startDate || rangePayload.endDate || null;

  return {
    ...rangePayload,
    locatorType,
    ...(slipDate ? { slipDate } : {}),
    ...(locatorPrefill.reason ? { reason: locatorPrefill.reason } : {}),
    ...(locatorPrefill.destination ? { destination: locatorPrefill.destination } : {}),
    ...(locatorPrefill.amIn === true ? { amIn: true } : {}),
    ...(locatorPrefill.amOut === true ? { amOut: true } : {}),
    ...(locatorPrefill.pmIn === true ? { pmIn: true } : {}),
    ...(locatorPrefill.pmOut === true ? { pmOut: true } : {}),
  };
}

function nextTopicPrefill(topic, text, memory, previousTopicState = {}) {
  if (topic === 'leave') {
    return mergePrefill(previousTopicState.leavePrefill || {}, extractLeavePrefill(text, memory));
  }
  if (topic === 'locator') {
    return mergePrefill(previousTopicState.locatorPrefill || {}, extractLocatorPrefill(text, memory));
  }
  return null;
}

module.exports = {
  buildLeaveActionPayload,
  buildLocatorActionPayload,
  extractLeavePrefill,
  extractLocatorPrefill,
  nextTopicPrefill,
};
