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

function removeOldAvatarIfDifferent(oldRelPath, newRelPath) {
  if (!oldRelPath || oldRelPath === newRelPath) return;
  const oldPath = path.resolve(UPLOAD_DIR, oldRelPath);
  removeAvatarFile(oldPath, 'old avatar');
}

function removeAvatarFile(filePath, label) {
  const allowedRoot = path.resolve(avatarDir);
  const resolved = path.resolve(filePath);
  if (!resolved.startsWith(`${allowedRoot}${path.sep}`)) return;
  fs.unlink(resolved, (err) => {
    if (err && err.code !== 'ENOENT') {
      console.warn(`[upload avatar] failed to delete ${label}`, err);
    }
  });
}

const updateAvatarSql = `
  WITH old_user AS (
    SELECT avatar_path AS old_avatar_path
    FROM users
    WHERE id = $2
  ),
  updated_user AS (
    UPDATE users
    SET avatar_path = $1, updated_at = now()
    WHERE id = $2
    RETURNING id, avatar_path AS new_avatar_path
  )
  SELECT updated_user.id, updated_user.new_avatar_path, old_user.old_avatar_path
  FROM updated_user
  LEFT JOIN old_user ON true
`;

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
    const extOk = /\.(jpg|jpeg|png|gif|webp)$/i.test(file.originalname || '');
    const mimeOk = /^image\/(jpeg|png|gif|webp)$/i.test(file.mimetype || '');
    cb(null, extOk && mimeOk);
  },
});

// Separate storage for training report attachments (images + PDF only)
const trainingStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, trainingReportDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.dat';
    const safeExt = ['.jpg', '.jpeg', '.png', '.pdf'].includes(ext.toLowerCase())
      ? ext
      : '.dat';
    cb(null, `${uuidv4()}${safeExt}`);
  },
});

const trainingUpload = multer({
  storage: trainingStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (_req, file, cb) => {
    const allowed = /\.(jpg|jpeg|png|pdf)$/i.test(file.originalname);
    cb(null, allowed);
  },
});

function fileSignatureMatches(filePath, ext) {
  let fd;
  try {
    fd = fs.openSync(filePath, 'r');
    const header = Buffer.alloc(12);
    const count = fs.readSync(fd, header, 0, header.length, 0);
    const hex = header.subarray(0, count).toString('hex');
    if (ext === '.pdf') return header.subarray(0, 5).toString() === '%PDF-';
    if (ext === '.png') return hex.startsWith('89504e470d0a1a0a');
    if (ext === '.jpg' || ext === '.jpeg') return hex.startsWith('ffd8ff');
    if (ext === '.gif') return header.subarray(0, 6).toString() === 'GIF87a' || header.subarray(0, 6).toString() === 'GIF89a';
    if (ext === '.webp') return header.subarray(0, 4).toString() === 'RIFF' && header.subarray(8, 12).toString() === 'WEBP';
    return false;
  } catch (_) {
    return false;
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

/**
 * POST /api/upload/avatar
 * multipart/form-data: file (image)
 * Updates user's avatar_path and returns path.
 */
router.post('/avatar', authMiddleware, upload.single('file'), async (req, res) => {
  let avatarUpdated = false;
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }
    if (!fileSignatureMatches(req.file.path, path.extname(req.file.filename).toLowerCase())) {
      removeAvatarFile(req.file.path, 'invalid avatar upload');
      return res.status(400).json({ error: 'Uploaded file content does not match its image type' });
    }

    const relPath = `${AVATAR_SUBDIR}/${req.file.filename}`;

    const result = await pool.query(updateAvatarSql, [relPath, req.user.id]);
    if (result.rowCount === 0) {
      removeAvatarFile(req.file.path, 'avatar for missing user');
      return res.status(404).json({ error: 'User not found' });
    }
    avatarUpdated = true;
    const row = result.rows[0];
    removeOldAvatarIfDifferent(row.old_avatar_path, row.new_avatar_path);

    res.json({
      path: relPath,
      url: `/api/files/avatar/${req.user.id}`,
    });
  } catch (err) {
    if (!avatarUpdated && req.file?.path) {
      removeAvatarFile(req.file.path, 'failed avatar upload');
    }
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
    let avatarUpdated = false;
    try {
      if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
      }
      const targetUserId = req.params.userId;
      const relPath = `${AVATAR_SUBDIR}/${req.file.filename}`;

      const result = await pool.query(updateAvatarSql, [relPath, targetUserId]);
      if (result.rowCount === 0) {
        removeAvatarFile(req.file.path, 'avatar for missing user');
        return res.status(404).json({ error: 'User not found' });
      }
      avatarUpdated = true;
      const row = result.rows[0];
      removeOldAvatarIfDifferent(row.old_avatar_path, row.new_avatar_path);
      res.json({
        path: relPath,
        url: `/api/files/avatar/${targetUserId}`,
      });
    } catch (err) {
      if (!avatarUpdated && req.file?.path) {
        removeAvatarFile(req.file.path, 'failed avatar upload');
      }
      console.error('[upload avatar for]', err);
      res.status(500).json({ error: 'Failed to upload avatar' });
    }
  }
);

module.exports = router;

/**
 * POST /api/upload/training-report
 * multipart/form-data: file (JPG/PNG/PDF only)
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
      if (!fileSignatureMatches(req.file.path, path.extname(req.file.filename).toLowerCase())) {
        removeAvatarFile(req.file.path, 'invalid avatar upload');
        return res.status(400).json({ error: 'Uploaded file content does not match its image type' });
      }
      const ext = path.extname(req.file.filename).toLowerCase();
      if (!fileSignatureMatches(req.file.path, ext)) {
        fs.unlinkSync(req.file.path);
        return res.status(400).json({ error: 'Uploaded file content does not match its file type' });
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
