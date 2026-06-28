const DEFAULT_TTL_MS = 2 * 60 * 60 * 1000;
const MAX_ENTRIES = 1000;

const memory = new Map();

function nowMs() {
  return Date.now();
}

function compactToolData(data) {
  if (!data || typeof data !== 'object') return data || null;
  return JSON.parse(JSON.stringify(data));
}

function getAssistantMemory(userId) {
  const key = String(userId || '');
  if (!key) return null;
  const entry = memory.get(key);
  if (!entry) return null;
  if (entry.expiresAt <= nowMs()) {
    memory.delete(key);
    return null;
  }
  return entry.value;
}

function setAssistantMemory(userId, value, ttlMs = DEFAULT_TTL_MS) {
  const key = String(userId || '');
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

function clearAssistantMemory(userId) {
  const key = String(userId || '');
  if (!key) return false;
  return memory.delete(key);
}

module.exports = {
  getAssistantMemory,
  setAssistantMemory,
  clearAssistantMemory,
  DEFAULT_TTL_MS,
};
