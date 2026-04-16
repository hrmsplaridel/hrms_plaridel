const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();

const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');
const AVATAR_SUBDIR = 'avatars';
const TRAINING_REPORT_SUBDIR = 'training-reports';

// Ensure upload directory exists
const avatarDir = path.join(UPLOAD_DIR, AVATAR_SUBDIR);
if (!fs.existsSync(avatarDir)) {
  fs.mkdirSync(avatarDir, { recursive: true });
}

const trainingReportDir = path.join(UPLOAD_DIR, TRAINING_REPORT_SUBDIR);
if (!fs.existsSync(trainingReportDir)) {
  fs.mkdirSync(trainingReportDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, avatarDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    const safeExt = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].includes(ext.toLowerCase()) ? ext : '.jpg';
    cb(null, `${uuidv4()}${safeExt}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
  fileFilter: (_req, file, cb) => {
    const allowed = /\.(jpg|jpeg|png|gif|webp)$/i.test(file.originalname);
    cb(null, allowed);
  },
});

// Separate storage for training report attachments (images + documents)
const trainingStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, trainingReportDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.dat';
    const safeExt = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.pdf', '.doc', '.docx']
            .includes(ext.toLowerCase())
      ? ext
      : '.dat';
    cb(null, `${uuidv4()}${safeExt}`);
  },
});

const trainingUpload = multer({
  storage: trainingStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (_req, file, cb) => {
    const allowed = /\.(jpg|jpeg|png|gif|webp|pdf|doc|docx)$/i.test(
      file.originalname
    );
    cb(null, allowed);
  },
});

/**
 * POST /api/upload/avatar
 * multipart/form-data: file (image)
 * Updates user's avatar_path and returns path.
 */
router.post('/avatar', authMiddleware, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const relPath = `${AVATAR_SUBDIR}/${req.file.filename}`;

    await pool.query(
      'UPDATE users SET avatar_path = $1, updated_at = now() WHERE id = $2',
      [relPath, req.user.id]
    );

    res.json({
      path: relPath,
      url: `/api/files/avatar/${req.user.id}`,
    });
  } catch (err) {
    console.error('[upload avatar]', err);
    res.status(500).json({ error: 'Failed to upload avatar' });
  }
});

/**
 * POST /api/upload/avatar/for/:userId
 * Admin uploads avatar for another user.
 */
router.post(
  '/avatar/for/:userId',
  authMiddleware,
  requireAdmin,
  upload.single('file'),
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
      }
      const targetUserId = req.params.userId;
      const relPath = `${AVATAR_SUBDIR}/${req.file.filename}`;

      const result = await pool.query(
        'UPDATE users SET avatar_path = $1, updated_at = now() WHERE id = $2 RETURNING id',
        [relPath, targetUserId]
      );
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'User not found' });
      }
      res.json({
        path: relPath,
        url: `/api/files/avatar/${targetUserId}`,
      });
    } catch (err) {
      console.error('[upload avatar for]', err);
      res.status(500).json({ error: 'Failed to upload avatar' });
    }
  }
);

module.exports = router;

/**
 * POST /api/upload/training-report
 * multipart/form-data: file (image or document)
 * Returns relative path and metadata; caller links it to a report row.
 */
router.post(
  '/training-report',
  authMiddleware,
  trainingUpload.single('file'),
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
      }

      const relPath = `${TRAINING_REPORT_SUBDIR}/${req.file.filename}`;

      res.json({
        path: relPath,
        originalName: req.file.originalname,
        mimeType: req.file.mimetype,
      });
    } catch (err) {
      console.error('[upload training-report]', err);
      res.status(500).json({ error: 'Failed to upload training report file' });
    }
  }
);
