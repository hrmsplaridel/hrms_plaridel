/**
 * RSP recruitment attachments — JWT view tokens + local disk (uploads/rsp-attachments).
 */
const express = require('express');
const path = require('path');
const fs = require('fs');
const jwt = require('jsonwebtoken');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { isAttachmentPathAllowedInDb } = require('../utils/rspAttachmentPolicy');
const { getRspAttachmentsRoot } = require('../utils/rspLocalAttachment');

const router = express.Router();
const protect = [authMiddleware, requireAdmin];

const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');

/**
 * GET /api/rsp/storage/view-token?path=...&fileName=...
 * Returns { token } — use like L&D training reports:
 *   Image.network('${ApiConfig.baseUrl}/api/files/recruitment-attachment?token=...')
 * No Supabase CORS; same pattern as GET /api/files/training-report/:id
 */
router.get('/view-token', ...protect, async (req, res) => {
  const objectPath = req.query.path;
  const fileName = (req.query.fileName || '').trim();

  if (!objectPath || String(objectPath).trim() === '') {
    return res.status(400).json({ error: 'path query parameter is required' });
  }

  try {
    const allowed = await isAttachmentPathAllowedInDb(objectPath);
    if (!allowed) {
      return res.status(403).json({
        error: 'Forbidden',
        details:
          'This file path is not linked to a recruitment application in PostgreSQL.',
      });
    }
  } catch (err) {
    console.error('[rsp/storage/view-token] db policy check', err);
    return res.status(503).json({
      error: 'Database unavailable for attachment policy check',
      details: err.message,
    });
  }

  if (!process.env.JWT_SECRET) {
    return res.status(503).json({ error: 'JWT_SECRET not configured on server' });
  }

  const token = jwt.sign(
    {
      typ: 'rsp_attachment',
      path: String(objectPath).trim(),
      fn: fileName || undefined,
    },
    process.env.JWT_SECRET,
    { expiresIn: '1h' },
  );

  res.json({ token });
});

/**
 * GET /api/rsp/storage/attachment-index
 * Lists files under uploads/rsp-attachments/{applicationId}/ for admin sync UI.
 */
router.get('/attachment-index', ...protect, async (_req, res) => {
  try {
    const root = getRspAttachmentsRoot(UPLOAD_DIR);
    if (!fs.existsSync(root)) {
      return res.json([]);
    }
    const out = [];
    for (const applicationId of fs.readdirSync(root)) {
      const dir = path.join(root, applicationId);
      if (!fs.statSync(dir).isDirectory()) continue;
      for (const fileName of fs.readdirSync(dir)) {
        const fp = path.join(dir, fileName);
        if (!fs.statSync(fp).isFile()) continue;
        const relPath = `${applicationId}/${fileName}`;
        out.push({
          applicationId,
          path: relPath,
          fileName,
        });
      }
    }
    res.json(out);
  } catch (err) {
    console.error('[rsp/storage/attachment-index]', err);
    res.status(500).json({ error: 'Failed to list attachments' });
  }
});

module.exports = router;
