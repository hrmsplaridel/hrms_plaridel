const WebSocket = require('ws');
const jwt = require('jsonwebtoken');

let wss = null;

function initWebSocket() {
  if (wss) return wss;

  wss = new WebSocket.Server({ noServer: true, maxPayload: 64 * 1024 });

  wss.on('connection', (ws, req) => {
    const user = authenticateRequest(req);
    if (!user?.id) {
      ws.close(1008, 'Unauthorized');
      return;
    }
    ws.user = user;
    // Optionally send initial connection success message
    ws.send(JSON.stringify({ event: 'connected' }));

    ws.on('error', console.error);
  });

  console.log('WebSocket server for biometrics initialized on /ws/biometrics');
  return wss;
}

function authenticateRequest(req) {
  try {
    const url = new URL(req.url, 'http://localhost');
    const token = url.searchParams.get('token');
    if (!token || !process.env.JWT_SECRET) return null;
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    if (payload.typ === 'refresh' || !payload.id) return null;
    return { id: String(payload.id), role: payload.role || null };
  } catch (_) {
    return null;
  }
}

/**
 * Broadcasts an event to all connected clients.
 * @param {string} eventName name of the event (e.g. 'dtr_refresh')
 * @param {object} payload additional payload data (e.g. { userId, action })
 */
function broadcastBiometricUpdate(eventName = 'dtr_refresh', payload = {}) {
  if (!wss) return;
  const dataString = JSON.stringify({ event: eventName, ...payload });
  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(dataString);
    }
  });
}

module.exports = {
  initWebSocket,
  broadcastBiometricUpdate,
};
