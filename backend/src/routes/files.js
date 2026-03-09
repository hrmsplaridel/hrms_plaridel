const express = require('express');
const path = require('path');
const fs = require('fs');
const { pool } = require('../config/db');

const router = express.Router();
const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');

/**
 * GET /api/files/avatar/:userId
 * Serve avatar image. No auth required for viewing.
 */
router.get('/avatar/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const result = await pool.query(
      'SELECT avatar_path FROM users WHERE id = $1',
      [userId]
    );
    const row = result.rows[0];
    if (!row?.avatar_path) {
      return res.status(404).json({ error: 'Avatar not found' });
    }

    const filePath = path.join(UPLOAD_DIR, row.avatar_path);
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'Avatar file not found' });
    }

    res.sendFile(path.resolve(filePath));
  } catch (err) {
    console.error('[files avatar]', err);
    res.status(500).json({ error: 'Failed to serve avatar' });
  }
});

module.exports = router;
