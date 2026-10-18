'use strict';
module.exports = function createLocatorComponent({ broadcastAppEvent }) {
  function notifySafe(fn) {
    Promise.resolve()
      .then(() => fn())
      .catch((e) => console.error('[locator notification]', e));
  }

  function broadcastLocatorUpdated(action, row = {}, extra = {}) {
    try {
      const slipId = row.id || extra.slipId || null;
      broadcastAppEvent('locator_updated', {
        action,
        slipId,
        locatorSlipId: slipId,
        userId: row.employee_id || row.userId || extra.userId || null,
        status: row.status || extra.status || null,
        updatedAt: new Date().toISOString(),
        ...extra,
      });
    } catch (e) {
      console.error('[locator websocket]', e);
    }
  }

  function broadcastLocatorTypeUpdated(action, row = {}, extra = {}) {
    try {
      broadcastAppEvent('locator_type_updated', {
        action,
        locatorTypeId: row.id || extra.locatorTypeId || null,
        code: row.code || extra.code || null,
        isActive: typeof row.is_active === 'boolean' ? row.is_active : (extra.isActive ?? null),
        updatedAt: new Date().toISOString(),
        ...extra,
      });
    } catch (e) {
      console.error('[locator type websocket]', e);
    }
  }
  return { notifySafe, broadcastLocatorUpdated, broadcastLocatorTypeUpdated };
};
