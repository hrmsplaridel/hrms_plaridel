const { broadcastAppEvent } = require('../websockets/appEvents');

function notifyPasswordResetRequestsChanged() {
  try {
    // Invalidation only: never send account details or codes through the event.
    broadcastAppEvent('password_reset_requests_changed', {}, { roles: ['super_admin'] });
  } catch (_) {
    // The transaction already committed. Polling recovers a missed event.
  }
}

module.exports = { notifyPasswordResetRequestsChanged };
