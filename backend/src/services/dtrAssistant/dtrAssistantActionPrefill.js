const {
  extractLeavePrefill,
  extractLocatorPrefill,
  prefillSourceText,
} = require('./dtrAssistantMessageExtraction');

function mergePrefill(previous = {}, next = {}) {
  const merged = { ...previous };
  for (const [key, value] of Object.entries(next)) {
    if (value == null || value === '') continue;
    merged[key] = value;
  }
  return merged;
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
    locatorType:
      locatorType ||
      memory?.topics?.locator?.locatorType ||
      memory?.locatorType ||
      null,
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
    const stored = mergePrefill(
      memory?.leavePrefill || {},
      previousTopicState.leavePrefill || {}
    );
    return mergePrefill(stored, extractLeavePrefill(text, memory));
  }
  if (topic === 'locator') {
    const stored = mergePrefill(
      memory?.locatorPrefill || {},
      previousTopicState.locatorPrefill || {}
    );
    return mergePrefill(stored, extractLocatorPrefill(text, memory));
  }
  return null;
}

module.exports = {
  buildLeaveActionPayload,
  buildLocatorActionPayload,
  extractLeavePrefill,
  extractLocatorPrefill,
  mergePrefill,
  nextTopicPrefill,
  prefillSourceText,
};
