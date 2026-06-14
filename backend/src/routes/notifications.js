const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const {
  listNotifications,
  countUnread,
  markRead,
  markAllRead,
  mapRowToApi,
} = require('../services/notificationService');
const {
  registerToken,
  unregisterToken,
} = require('../services/fcmPushService');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/notifications — list for current user
router.get('/', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const limit = req.query?.limit;
    const unreadOnly = String(req.query?.unread_only || '') === '1' || String(req.query?.unread_only || '').toLowerCase() === 'true';
    const rows = await listNotifications(pool, userId, {
      limit: limit ? parseInt(limit, 10) : 50,
      unreadOnly,
    });
    res.json(rows.map(mapRowToApi));
  } catch (err) {
    console.error('[notifications GET]', err);
    const missingTable = err?.code === '42P01';
    res.status(500).json({
      error: missingTable
        ? 'Notifications table missing. Run backend/scripts/migrate-user-notifications.sql'
        : 'Failed to fetch notifications',
    });
  }
});

// GET /api/notifications/unread-count
router.get('/unread-count', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const c = await countUnread(pool, userId);
    res.json({ unread_count: c });
  } catch (err) {
    console.error('[notifications GET unread-count]', err);
    res.status(500).json({ error: 'Failed to count notifications' });
  }
});

// POST /api/notifications/push-token — register/update the current device FCM token
router.post('/push-token', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });

  const { token, platform, device_id: deviceId } = req.body || {};
  if (!token || String(token).trim().length < 20) {
    return res.status(400).json({ error: 'Valid FCM token is required' });
  }

  try {
    const row = await registerToken(pool, {
      userId,
      token,
      platform,
      deviceId,
    });
    res.json({ ok: true, id: row?.id });
  } catch (err) {
    console.error('[notifications POST push-token]', err);
    const missingTable = err?.code === '42P01';
    res.status(500).json({
      error: missingTable
        ? 'Push token table missing. Run backend/scripts/migrate-user-push-tokens.sql'
        : 'Failed to register push token',
    });
  }
});

// DELETE /api/notifications/push-token — revoke the current device FCM token
router.delete('/push-token', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });

  const { token } = req.body || {};
  if (!token) return res.status(400).json({ error: 'FCM token is required' });

  try {
    await unregisterToken(pool, { userId, token });
    res.json({ ok: true });
  } catch (err) {
    console.error('[notifications DELETE push-token]', err);
    res.status(500).json({ error: 'Failed to unregister push token' });
  }
});

// PATCH /api/notifications/:id/read
router.patch('/:id/read', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  try {
    const ok = await markRead(pool, id, userId);
    if (!ok) return res.status(404).json({ error: 'Notification not found' });
    res.json({ ok: true });
  } catch (err) {
    console.error('[notifications PATCH read]', err);
    res.status(500).json({ error: 'Failed to update notification' });
  }
});

// POST /api/notifications/read-all
router.post('/read-all', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    await markAllRead(pool, userId);
    res.json({ ok: true });
  } catch (err) {
    console.error('[notifications POST read-all]', err);
    res.status(500).json({ error: 'Failed to mark notifications read' });
  }
});

module.exports = router;
