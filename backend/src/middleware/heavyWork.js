const {heavyWorkQueue} = require('../services/heavyWorkQueue');

function withHeavyWork(handler, {queue = heavyWorkQueue} = {}) {
  return async (req, res, next) => {
    const controller = new AbortController();
    const disconnected = () => controller.abort();
    req.once?.('aborted', disconnected);
    res.once?.('close', disconnected);
    try {
      if (req.aborted || res.destroyed) controller.abort();
      await queue.run(() => handler(req, res, next), {signal: controller.signal});
    } catch (error) {
      if (controller.signal.aborted) return;
      if (error.code === 'HEAVY_OPERATION_BUSY') {
        res.setHeader('Retry-After', String(error.retryAfterSeconds));
        return res.status(503).json({
          error: error.message, code: error.code, retryAfterSeconds: error.retryAfterSeconds,
        });
      }
      if (next) return next(error);
      throw error;
    } finally {
      req.removeListener?.('aborted', disconnected);
      res.removeListener?.('close', disconnected);
    }
  };
}
module.exports = {withHeavyWork};
