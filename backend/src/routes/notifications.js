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
    res.status(500).json({ error: 'Failed to fetch notifications' });
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
