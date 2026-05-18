const WebSocket = require('ws');
const jwt = require('jsonwebtoken');

let wss = null;

function parseUserFromRequest(req) {
  try {
    const url = new URL(req.url, 'http://localhost');
    const token = url.searchParams.get('token');
    if (!token || !process.env.JWT_SECRET) return null;

    const payload = jwt.verify(token, process.env.JWT_SECRET);
    if (payload.typ === 'refresh') return null;

    return {
      id: payload.id ? String(payload.id) : null,
      email: payload.email || null,
      role: payload.role || null,
    };
  } catch (_) {
    return null;
  }
}

function initAppEventsWebSocket() {
  if (wss) return wss;

  wss = new WebSocket.Server({ noServer: true });

  wss.on('connection', (ws, req) => {
    const user = parseUserFromRequest(req);
    if (!user?.id) {
      ws.close(1008, 'Unauthorized');
      return;
    }

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
};
