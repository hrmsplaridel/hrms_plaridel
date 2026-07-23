const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const {
  chatWithDtrAssistant,
  getDtrAssistantModelProfiles,
  resetDtrAssistantChat,
} = require('../services/dtrAssistant/dtrAssistantService');
const { getDtrExport } = require('../services/dtrAssistant/dtrAssistantExportService');
const {
  submitDtrAssistantFeedback,
} = require('../services/dtrAssistant/dtrAssistantFeedbackService');
const {
  dtrAssistantChatBurstLimiter,
  dtrAssistantChatHourlyLimiter,
  dtrAssistantResetLimiter,
  dtrAssistantFeedbackLimiter,
  dtrAssistantExportLimiter,
} = require('../middleware/rateLimiters');

const router = express.Router();
const protect = [authMiddleware];

router.get('/models', protect, async (_req, res) => {
  res.json(getDtrAssistantModelProfiles());
});

router.get(
  '/exports/:token',
  protect,
  dtrAssistantExportLimiter,
  async (req, res) => {
    const file = getDtrExport(req.params.token, req.user.id);
    if (!file) {
      return res.status(404).json({ error: 'Export expired or not found.' });
    }
    res.setHeader('Content-Type', file.mimeType);
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${file.filename.replace(/"/g, '')}"`
    );
    res.send(file.buffer);
  }
);

router.post(
  '/chat',
  protect,
  dtrAssistantChatBurstLimiter,
  dtrAssistantChatHourlyLimiter,
  async (req, res) => {
    try {
      const result = await chatWithDtrAssistant(pool, {
        user: req.user,
        message: req.body?.message,
        intent: req.body?.intent,
        modelProfile: req.body?.modelProfile,
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
  }
);

router.post('/reset', protect, dtrAssistantResetLimiter, async (req, res) => {
  try {
    res.json(resetDtrAssistantChat(req.user));
  } catch (err) {
    const status = err.statusCode || 500;
    if (status >= 500) {
      console.error('[dtr-assistant POST /reset]', err);
    }
    res.status(status).json({
      error: err.message || 'Failed to reset assistant chat',
    });
  }
});

router.post(
  '/feedback',
  protect,
  dtrAssistantFeedbackLimiter,
  async (req, res) => {
    try {
      const saved = await submitDtrAssistantFeedback(pool, {
        userId: req.user.id,
        messageId: req.body?.messageId,
        rating: req.body?.rating,
        intent: req.body?.intent,
        provider: req.body?.provider,
        model: req.body?.model,
        modelProfile: req.body?.modelProfile,
        promptPreview: req.body?.promptPreview,
        intentConfidence: req.body?.intentConfidence,
        intentSource: req.body?.intentSource,
        contentPreview: req.body?.contentPreview,
        comment: req.body?.comment,
      });
      res.json({ ok: true, feedback: saved });
    } catch (err) {
      const status = err.statusCode || 500;
      if (status >= 500) {
        console.error('[dtr-assistant POST /feedback]', err);
      }
      res.status(status).json({
        error: err.message || 'Failed to save assistant feedback',
      });
    }
  }
);

module.exports = router;
