const { normalizeAssistantMessageForRules } = require('./dtrAssistantTextNormalizer');

function lower(value) {
  return String(value || '').toLowerCase();
}

function topicForIntent(intent) {
  const value = String(intent || '');
  if (
    value === 'today_dtr' ||
    value === 'missing_logs' ||
    value.startsWith('dtr_')
  ) {
    return 'dtr';
  }
  if (
    value === 'pending_leave_requests' ||
    value === 'approved_leave_requests' ||
    value === 'rejected_leave_requests' ||
    value === 'latest_leave_request' ||
    value.startsWith('leave_')
  ) {
    return 'leave';
  }
  if (value === 'latest_locator_request' || value.startsWith('locator_')) {
    return 'locator';
  }
  return null;
}

function explicitTopicFromMessage(message) {
  const text = lower(normalizeAssistantMessageForRules(message));
  if (
    /\b(locator|locator slip|pass slip|wfh|work from home|official business|ob|fieldwork|field work|travel order)\b/.test(
      text
    )
  ) {
    return 'locator';
  }
  if (
    /\b(leave|leaves|sick|vacation|paternity|maternity|adoption|solo parent|vawc|calamity|mandatory|forced|special privilege|vl|sl)\b/.test(
      text
    )
  ) {
    return 'leave';
  }
  if (
    /\b(dtr|attendance|daily time|time[\s-]?in|time[\s-]?out|late|undertime|overtime|absent|absence|shift|schedule|missing log|incomplete log)\b/.test(
      text
    )
  ) {
    return 'dtr';
  }
  return null;
}

function isContextDependentMessage(message) {
  const text = lower(normalizeAssistantMessageForRules(message))
    .replace(/[.!?]+$/g, '')
    .trim();
  if (!text) return false;
  if (
    /^(how about|what about|and what about|same|same one|same date|same day|that one|this one|it|that|this|also|instead|only|make it)\b/.test(
      text
    )
  ) {
    return true;
  }
  if (/\b(instead|same one|same date|same day)\b/.test(text)) return true;
  if (/^(why|ngano|bakit)\b/.test(text)) return true;
  if (
    /\b(again|another example|same field|that field|this field|translate|bisayaa?|binisayaa?|cebuano|tagaloga?|filipino|english|ingles)\b/.test(
      text
    )
  ) {
    return true;
  }
  if (
    /^(today|tomorrow|yesterday|karon|ugma|gahapon|kagahapon|bukas|kahapon|\d+(?:\.\d+)?\s*(?:days?|adlaw|araw)?|one|two|three|four|five|six|seven|eight|nine|ten)$/.test(
      text
    )
  ) {
    return true;
  }
  if (
    /^(sick|sick leave|vacation|vacation leave|maternity|maternity leave|paternity|paternity leave|adoption|adoption leave|solo parent|solo parent leave|vawc|vawc leave|calamity|calamity leave|wfh|work from home|pass slip|official business|am|pm|whole day)$/.test(
      text
    )
  ) {
    return true;
  }
  return /\b(what attachment|which attachment|what document|which document|requirements for that|same requirements)\b/.test(
    text
  );
}

function contextGate({
  message,
  memory,
  scoredIntent,
  forcedIntent,
  clarificationInterrupted = false,
  clarificationAnswered = false,
}) {
  if (!memory) {
    return {
      kind: 'standalone',
      useMemory: false,
      reason: 'no_memory',
    };
  }

  const memoryTopic = memory.topic || topicForIntent(memory.intent);
  const explicitTopic = explicitTopicFromMessage(message);
  const scoredTopic = topicForIntent(scoredIntent?.intent);
  const nextTopic = explicitTopic || scoredTopic;

  if (forcedIntent) {
    return {
      kind:
        nextTopic && memoryTopic && nextTopic !== memoryTopic
          ? 'topic_switch'
          : 'standalone',
      useMemory: false,
      reason: 'explicit_intent',
    };
  }

  if (clarificationAnswered) {
    return {
      kind: 'follow_up',
      useMemory: true,
      reason: 'clarification_answer',
    };
  }

  if (memory.pendingClarification?.intent && !clarificationInterrupted) {
    if (!explicitTopic || !memoryTopic || explicitTopic === memoryTopic) {
      return {
        kind: 'follow_up',
        useMemory: true,
        reason: 'pending_clarification',
      };
    }
  }

  if (explicitTopic && memoryTopic && explicitTopic !== memoryTopic) {
    return {
      kind: 'topic_switch',
      useMemory: false,
      reason: 'explicit_topic_switch',
    };
  }

  if (isContextDependentMessage(message)) {
    return {
      kind: 'follow_up',
      useMemory: true,
      reason: 'context_reference',
    };
  }

  if (scoredTopic && memoryTopic && scoredTopic !== memoryTopic) {
    return {
      kind: 'topic_switch',
      useMemory: false,
      reason: 'different_topic',
    };
  }

  const activeIntent =
    (nextTopic && memory.topics?.[nextTopic]?.intent) || memory.intent || null;
  const clearIntent =
    scoredIntent?.intent &&
    Number(scoredIntent.confidence || 0) >= 0.72 &&
    scoredIntent.source !== 'unclear';

  if (clearIntent && scoredIntent.intent !== activeIntent) {
    return {
      kind: 'standalone',
      useMemory: false,
      reason: 'clear_new_intent',
    };
  }

  return {
    kind: 'standalone',
    useMemory: false,
    reason: clearIntent ? 'self_contained_intent' : 'no_context_reference',
  };
}

module.exports = {
  contextGate,
  explicitTopicFromMessage,
  isContextDependentMessage,
  topicForIntent,
};
