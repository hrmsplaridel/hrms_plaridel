const WebSocket = require('ws');
const jwt = require('jsonwebtoken');
const { pool } = require('../config/db');

let wss = null;
let resetGeneration = 0;

async function parseUserFromRequest(req) {
  try {
    const url = new URL(req.url, 'http://localhost');
    const token = url.searchParams.get('token');
    if (!token || !process.env.JWT_SECRET) return null;

    const payload = jwt.verify(token, process.env.JWT_SECRET);
    if (payload.typ === 'refresh') return null;
    const result = await pool.query('SELECT id, email, role, is_active, employment_status, auth_version FROM users WHERE id = $1', [payload.id]);
    const account = result.rows[0];
    if (!account || !account.is_active || account.employment_status !== 'active' ||
        (payload.auth_version || 0) !== (account.auth_version || 0)) return null;

    return {
      id: payload.id ? String(payload.id) : null,
      email: account.email || null,
      role: account.role || null,
      auth_version: account.auth_version || 0,
    };
  } catch (_) {
    return null;
  }
}

function initAppEventsWebSocket() {
  if (wss) return wss;

  wss = new WebSocket.Server({ noServer: true, maxPayload: 64 * 1024 });

  wss.on('connection', async (ws, req) => {
    const generation = resetGeneration;
    const user = await parseUserFromRequest(req);
    if (!user?.id || generation !== resetGeneration) {
      ws.close(1008, 'Unauthorized');
      return;
    }
    if (ws.readyState !== WebSocket.OPEN) return;

    ws.user = user;
    ws.send(
      JSON.stringify({
        event: 'connected',
        payload: { userId: user.id },
        createdAt: new Date().toISOString(),
      })
    );

    ws.on('error', console.error);
  });

  console.log('Authenticated app WebSocket initialized on /ws/app');
  return wss;
}

function normalizeIds(value) {
  if (value == null) return [];
  const list = Array.isArray(value) ? value : [value];
  return list.map((item) => String(item).trim()).filter(Boolean);
}

function disconnectUserSessions(userId) {
  resetGeneration++;
  if (!wss) return;
  for (const client of wss.clients) {
    if (client.user?.id === String(userId)) client.close(1008, 'Session expired');
  }
}

function broadcastAppEvent(eventName, payload = {}, options = {}) {
  if (!wss) return 0;

  const targetUserIds = new Set(normalizeIds(options.userIds ?? options.userId));
  const targetRoles = new Set(normalizeIds(options.roles));
  const data = JSON.stringify({
    event: eventName,
    payload,
    createdAt: new Date().toISOString(),
  });

  let sent = 0;
  wss.clients.forEach((client) => {
    if (client.readyState !== WebSocket.OPEN) return;
    const user = client.user;
    if (!user?.id) return;
    if (targetUserIds.size > 0 && !targetUserIds.has(user.id)) return;
    if (targetRoles.size > 0 && !targetRoles.has(user.role)) return;
    client.send(data);
    sent += 1;
  });
  return sent;
}

module.exports = {
  initAppEventsWebSocket,
  broadcastAppEvent,
  disconnectUserSessions,
};
