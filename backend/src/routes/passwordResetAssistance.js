const express = require('express');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');
const { authPasswordResetLimiter } = require('../middleware/rateLimiters');
const { createPasswordResetAssistance } = require('../services/passwordResetAssistance');
const service = createPasswordResetAssistance();
const publicRouter = express.Router();
const adminRouter = express.Router();
const respond = work => async (req, res) => {
  try { res.json(await work(req)); }
  catch (error) {
    // Do not expose provider responses or request credentials in logs/responses.
    res.status(error.status || 503).json({ error: error.status ? error.message : 'Password reset assistance is temporarily unavailable' });
  }
};
publicRouter.post('/', authPasswordResetLimiter, respond(req => service.request(req.body?.email)));
adminRouter.use(authMiddleware, requireSuperAdmin);
adminRouter.get('/', respond(req => service.list(req.query)));
adminRouter.post('/:id/send', respond(req => service.send(req.params.id, req.user.id, req.body?.verified)));
adminRouter.post('/:id/close', respond(req => service.close(req.params.id, req.user.id)));
module.exports = { publicRouter, adminRouter };
