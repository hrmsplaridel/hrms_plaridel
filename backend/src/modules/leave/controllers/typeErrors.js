'use strict';
module.exports = function createLeaveComponent({}) {
  function sendLeaveTypeWriteError(res, err, action) {
    if (err && err.statusCode) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (err?.code === '23505') {
      return res.status(409).json({ error: 'Leave type key already exists' });
    }
    if (err?.code === '22P02' || err?.code === '23514') {
      return res.status(400).json({
        error: 'Leave type settings contain an invalid value or custom-field configuration.',
      });
    }
    if (err?.code === '42703') {
      return res.status(500).json({
        error: 'Leave type database setup is outdated. Apply the latest database migration.',
      });
    }
    return res.status(500).json({ error: `Failed to ${action} leave type` });
  }
  return { sendLeaveTypeWriteError };
};
