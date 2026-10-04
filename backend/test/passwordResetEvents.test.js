const test = require('node:test');
const assert = require('node:assert/strict');
const { initAppEventsWebSocket } = require('../src/websockets/appEvents');
const { notifyPasswordResetRequestsChanged } = require('../src/services/passwordResetEvents');

test('reset queue invalidations reach only super-admin sockets without account data', () => {
  const server = initAppEventsWebSocket();
  const deliveries = [];
  for (const role of ['super_admin', 'admin', 'employee']) {
    server.clients.add({ readyState: 1, user: { id: role, role }, send: data => deliveries.push({ role, data: JSON.parse(data) }) });
  }
  try {
    notifyPasswordResetRequestsChanged();
    assert.equal(deliveries.length, 1);
    assert.equal(deliveries[0].role, 'super_admin');
    assert.equal(deliveries[0].data.event, 'password_reset_requests_changed');
    assert.deepEqual(deliveries[0].data.payload, {});
  } finally { server.clients.clear(); server.close(); }
});
