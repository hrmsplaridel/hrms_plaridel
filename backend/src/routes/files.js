const express = require('express');
const path = require('path');
const fs = require('fs');
const jwt = require('jsonwebtoken');
const { pool } = require('../config/db');
const { isAttachmentPathAllowedInDb } = require('../utils/rspAttachmentPolicy');
const { fetchSupabaseObjectResponse } = require('../utils/supabaseStorageFetch');

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

/**
 * GET /api/files/recruitment-attachment?token=...&download=1
 * Proxy applicant files from Supabase Storage (same idea as training-report files).
 * Token is minted by GET /api/rsp/storage/view-token (admin only). No Bearer header
 * required — matches how L&D uses Image.network against /api/files/training-report/:id.
 */
router.get('/recruitment-attachment', async (req, res) => {
  const token = req.query.token;
  const asDownload =
    req.query.download === '1' || req.query.download === 'true';

  if (!token || String(token).trim() === '') {
    return res.status(400).json({ error: 'token query parameter is required' });
  }

  if (!process.env.JWT_SECRET) {
    return res.status(503).json({ error: 'Server misconfiguration' });
  }

  try {
    const payload = jwt.verify(String(token).trim(), process.env.JWT_SECRET);
    if (payload.typ !== 'rsp_attachment' || !payload.path) {
      return res.status(403).json({ error: 'Invalid token' });
    }

    const objectPath = String(payload.path).trim();
    const allowed = await isAttachmentPathAllowedInDb(objectPath);
    if (!allowed) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const r = await fetchSupabaseObjectResponse(objectPath);
    if (!r.ok) {
      const errText = await r.text();
      console.error(
        '[files recruitment-attachment] storage',
        r.status,
        errText?.slice(0, 200),
      );
      return res.status(r.status >= 400 ? r.status : 502).json({
        error: 'Could not load file from storage',
        details: errText?.slice(0, 120),
      });
    }

    const contentType =
      r.headers.get('content-type') || 'application/octet-stream';
    res.setHeader('Content-Type', contentType);

    const safeName = (payload.fn || path.basename(objectPath) || 'attachment')
      .replace(/[^\w.\- ()]/g, '_')
      .slice(0, 180);
    if (asDownload) {
      res.setHeader(
        'Content-Disposition',
        `attachment; filename="${safeName}"`,
      );
    } else {
      res.setHeader('Cache-Control', 'private, max-age=300');
    }

    const buf = Buffer.from(await r.arrayBuffer());
    res.send(buf);
  } catch (e) {
    if (e.name === 'JsonWebTokenError' || e.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Invalid or expired link' });
    }
    if (e.statusCode === 503) {
      return res.status(503).json({
        error: 'Storage not configured',
        details: e.message,
      });
    }
    console.error('[files recruitment-attachment]', e);
    res.status(500).json({ error: 'Failed to serve attachment' });
  }
});

/**
 * GET /api/files/training-report/:attachmentId
 * Serve a training report attachment by its ID.
 */
router.get('/training-report/:attachmentId', async (req, res) => {
  try {
    const { attachmentId } = req.params;
    const result = await pool.query(
      'SELECT file_path FROM training_report_attachments WHERE id = $1',
      [attachmentId]
    );
    const row = result.rows[0];
    if (!row?.file_path) {
      return res.status(404).json({ error: 'Attachment not found' });
    }

    const filePath = path.join(UPLOAD_DIR, row.file_path);
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'Attachment file not found' });
    }

    res.sendFile(path.resolve(filePath));
  } catch (err) {
    console.error('[files training-report]', err);
    res.status(500).json({ error: 'Failed to serve attachment' });
  }
});

module.exports = router;
