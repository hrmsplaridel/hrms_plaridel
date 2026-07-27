const DEFAULT_TTL_MS = 2 * 60 * 60 * 1000;
const MAX_ENTRIES = 1000;
const DEFAULT_CONVERSATION_ID = 'default';

const memory = new Map();

function nowMs() {
  return Date.now();
}

function compactToolData(data) {
  if (!data || typeof data !== 'object') return data || null;
  return JSON.parse(JSON.stringify(data));
}

function normalizeConversationId(value, { required = false } = {}) {
  const conversationId = String(value || '').trim();
  if (!conversationId) {
    if (required) {
      const err = new Error('conversationId is required');
      err.statusCode = 400;
      throw err;
    }
    return DEFAULT_CONVERSATION_ID;
  }
  if (
    conversationId.length > 96 ||
    !/^[a-zA-Z0-9][a-zA-Z0-9._:-]*$/.test(conversationId)
  ) {
    const err = new Error('conversationId is invalid');
    err.statusCode = 400;
    throw err;
  }
  return conversationId;
}

function memoryKey(userId, conversationId) {
  const userKey = String(userId || '').trim();
  if (!userKey) return null;
  return `${userKey}:${normalizeConversationId(conversationId)}`;
}

function getAssistantMemory(userId, conversationId) {
  const key = memoryKey(userId, conversationId);
  if (!key) return null;
  const entry = memory.get(key);
  if (!entry) return null;
  if (entry.expiresAt <= nowMs()) {
    memory.delete(key);
    return null;
  }
  return entry.value;
}

function setAssistantMemory(
  userId,
  value,
  ttlMs = DEFAULT_TTL_MS,
  conversationId = DEFAULT_CONVERSATION_ID
) {
  const key = memoryKey(userId, conversationId);
  if (!key) return;

  if (memory.size >= MAX_ENTRIES) {
    const firstKey = memory.keys().next().value;
    if (firstKey) memory.delete(firstKey);
  }

  memory.set(key, {
    expiresAt: nowMs() + ttlMs,
    value: {
      ...value,
      toolData: compactToolData(value.toolData),
      updatedAt: new Date().toISOString(),
    },
  });
}

function clearAssistantMemory(userId, conversationId) {
  const key = memoryKey(userId, conversationId);
  if (!key) return false;
  return memory.delete(key);
}

module.exports = {
  getAssistantMemory,
  setAssistantMemory,
  clearAssistantMemory,
  normalizeConversationId,
  DEFAULT_TTL_MS,
  DEFAULT_CONVERSATION_ID,
};
