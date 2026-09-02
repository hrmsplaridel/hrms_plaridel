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
  issueDtrAssistantFeedbackToken,
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
    const controller = new AbortController();
    const abortRequest = () => controller.abort();
    const abortDisconnectedResponse = () => {
      if (!res.writableEnded) controller.abort();
    };
    req.once('aborted', abortRequest);
    res.once('close', abortDisconnectedResponse);
    try {
      const result = await chatWithDtrAssistant(pool, {
        user: req.user,
        message: req.body?.message,
        intent: req.body?.intent,
        modelProfile: req.body?.modelProfile,
        conversationId: req.body?.conversationId,
        externalConsentVersion: req.body?.externalConsentVersion,
        signal: controller.signal,
      });
      if (controller.signal.aborted || res.destroyed) return;
      if (result?.message?.id) {
        result.message.feedbackToken = issueDtrAssistantFeedbackToken({
          userId: req.user.id,
          messageId: result.message.id,
          intent: result.message.intent,
          provider: result.message.provider,
          model: result.message.model,
          modelProfile: result.message.modelProfile,
          intentConfidence: result.message.intentConfidence,
          intentSource: result.message.intentSource,
          prompt: result.message.promptPreview,
          response: result.message.content,
        });
      }
      res.json(result);
    } catch (err) {
      if (controller.signal.aborted || res.destroyed) return;
      const status =
        err.statusCode ||
        (err.code === 'ASSISTANT_REQUEST_ABORTED'
          ? 499
          : err.code === 'AI_PROVIDER_TIMEOUT'
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
    } finally {
      req.off('aborted', abortRequest);
      res.off('close', abortDisconnectedResponse);
    }
  }
);

router.post('/reset', protect, dtrAssistantResetLimiter, async (req, res) => {
  try {
    res.json(resetDtrAssistantChat(req.user, req.body?.conversationId));
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
        feedbackToken: req.body?.feedbackToken,
        rating: req.body?.rating,
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
        code: err.code || null,
      });
    }
  }
);

module.exports = router;
