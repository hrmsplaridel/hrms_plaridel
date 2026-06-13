const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { chatWithDtrAssistant } = require('../services/dtrAssistant/dtrAssistantService');

const router = express.Router();
const protect = [authMiddleware];

router.post('/chat', protect, async (req, res) => {
  try {
    const result = await chatWithDtrAssistant(pool, {
      user: req.user,
      message: req.body?.message,
      intent: req.body?.intent,
    });
    res.json(result);
  } catch (err) {
    const status =
      err.statusCode ||
      (err.code === 'AI_PROVIDER_TIMEOUT'
        ? 504
        : err.code === 'AI_LOCAL_UNAVAILABLE'
          ? 503
          : err.code === 'AI_PROVIDER_FAILED'
            ? 502
            : 500);

    if (status >= 500) {
      console.error('[dtr-assistant POST /chat]', err);
    }

    res.status(status).json({
      error:
        err.providerMessage ||
        err.message ||
        'Failed to generate DTR assistant response',
      code: err.code || null,
    });
  }
});

module.exports = router;
