const WebSocket = require('ws');

let wss = null;

function initWebSocket() {
  wss = new WebSocket.Server({ noServer: true });

  wss.on('connection', (ws) => {
    // Optionally send initial connection success message
    ws.send(JSON.stringify({ event: 'connected' }));

    ws.on('error', console.error);
  });

  console.log('WebSocket server for biometrics initialized on /ws/biometrics');
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
