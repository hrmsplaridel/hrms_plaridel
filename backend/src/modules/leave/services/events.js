'use strict';
module.exports = function createLeaveComponent({ broadcastAppEvent, broadcastBiometricUpdate }) {
  /** Fire-and-forget in-app notifications; never fails the HTTP handler. */
  function notifySafe(fn) {
    Promise.resolve()
      .then(() => fn())
      .catch((e) => console.error('[leave notification]', e));
  }

  function leaveRowUserId(row = {}) {
    return row.user_id || row.employee_id || row.userId || row.employeeId || null;
  }

  function broadcastLeaveUpdated(action, row = {}, extra = {}) {
    try {
      const requestId = row.id || extra.requestId || extra.leaveRequestId || null;
      broadcastAppEvent('leave_updated', {
        action,
        requestId,
        leaveRequestId: requestId,
        userId: leaveRowUserId(row) || extra.userId || null,
        status: row.status || extra.status || null,
        updatedAt: new Date().toISOString(),
        ...extra,
      });
    } catch (e) {
      console.error('[leave websocket]', e);
    }
  }

  function broadcastDtrLeaveRefresh(action, { userId, leaveRequestId, dateFrom, dateTo } = {}) {
    try {
      if (!userId) return;
      const normalizedUserId = String(userId);
      broadcastBiometricUpdate('dtr_refresh', {
        action,
        userId: normalizedUserId,
        userIds: [normalizedUserId],
        requestId: leaveRequestId || null,
        leaveRequestId: leaveRequestId || null,
        dateFrom: dateFrom || null,
        dateTo: dateTo || null,
      });
    } catch (e) {
      console.error('[leave dtr websocket]', e);
    }
  }
  return { notifySafe, leaveRowUserId, broadcastLeaveUpdated, broadcastDtrLeaveRefresh };
};
