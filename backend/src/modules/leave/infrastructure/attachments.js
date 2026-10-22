'use strict';
module.exports = function createLeaveComponent({
  LEAVE_ATTACHMENT_SUBDIR,
  UPLOAD_DIR,
  fs,
  multer,
  path,
  uuidv4,
}) {
  // Ensure leave attachment directory exists
  const leaveAttachmentDir = path.join(UPLOAD_DIR, LEAVE_ATTACHMENT_SUBDIR);

  if (!fs.existsSync(leaveAttachmentDir)) {
    fs.mkdirSync(leaveAttachmentDir, { recursive: true });
  }

  const ALLOWED_LEAVE_ATTACHMENT_EXT = /\.(pdf|jpg|jpeg|png)$/i;

  const MAX_LEAVE_ATTACHMENT_SIZE = 10 * 1024 * 1024;

  // 10MB

  const leaveAttachmentStorage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, leaveAttachmentDir),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname) || '.pdf';
      const safeExt = ALLOWED_LEAVE_ATTACHMENT_EXT.test(ext) ? ext : '.pdf';
      cb(null, `lr_${uuidv4()}${safeExt}`);
    },
  });

  const uploadLeaveAttachment = multer({
    storage: leaveAttachmentStorage,
    limits: { fileSize: MAX_LEAVE_ATTACHMENT_SIZE },
    fileFilter: (_req, file, cb) => {
      const ext = path.extname(file.originalname || '').toLowerCase();
      const ok = ['.pdf', '.jpg', '.jpeg', '.png'].includes(ext);
      if (!ok) cb(new Error('Allowed file types: PDF, JPG, JPEG, PNG'), false);
      else cb(null, true);
    },
  });

  const uploadLeaveAttachmentMemory = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: MAX_LEAVE_ATTACHMENT_SIZE },
    fileFilter: (_req, file, cb) => {
      const ext = path.extname(file.originalname || '').toLowerCase();
      const ok = ['.pdf', '.jpg', '.jpeg', '.png'].includes(ext);
      if (!ok) cb(new Error('Allowed file types: PDF, JPG, JPEG, PNG'), false);
      else cb(null, true);
    },
  });

  function uploadLeaveAttachmentMw(req, res, next) {
    uploadLeaveAttachment.single('file')(req, res, (err) => {
      if (err) {
        if (err.message === 'Allowed file types: PDF, JPG, JPEG, PNG') {
          return res.status(400).json({ error: err.message });
        }
        if (err.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({ error: 'File too large. Max 10MB.' });
        }
        return next(err);
      }
      next();
    });
  }

  function uploadLeaveAttachmentMemoryMw(req, res, next) {
    uploadLeaveAttachmentMemory.single('file')(req, res, (err) => {
      if (err) {
        if (err.message === 'Allowed file types: PDF, JPG, JPEG, PNG') {
          return res.status(400).json({ error: err.message });
        }
        if (err.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({ error: 'File too large. Max 10MB.' });
        }
        return next(err);
      }
      next();
    });
  }

  function storedLeaveAttachmentFromMemoryFile(file) {
    if (!file || !Buffer.isBuffer(file.buffer)) return null;
    const ext = path.extname(file.originalname || '').toLowerCase();
    const safeExt = ['.pdf', '.jpg', '.jpeg', '.png'].includes(ext) ? ext : '.pdf';
    const filename = `lr_${uuidv4()}${safeExt}`;
    const filePath = path.join(leaveAttachmentDir, filename);
    const relPath = `${LEAVE_ATTACHMENT_SUBDIR}/${filename}`;
    try {
      fs.writeFileSync(filePath, file.buffer);
    } catch (err) {
      cleanupStoredLeaveAttachment(relPath);
      throw err;
    }
    return {
      originalName: file.originalname || filename,
      relPath,
      mimeType: file.mimetype || null,
    };
  }

  function cleanupStoredLeaveAttachment(relPath) {
    if (!relPath) return;
    try {
      const uploadRoot = path.resolve(UPLOAD_DIR);
      const filePath = path.resolve(uploadRoot, String(relPath));
      if (filePath !== uploadRoot && !filePath.startsWith(`${uploadRoot}${path.sep}`)) {
        return;
      }
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    } catch (err) {
      console.error('[leave attachment cleanup]', err);
    }
  }

  function storedLeaveAttachmentExists(relPath) {
    if (!relPath) return false;
    try {
      const uploadRoot = path.resolve(UPLOAD_DIR);
      const filePath = path.resolve(uploadRoot, String(relPath));
      if (filePath !== uploadRoot && !filePath.startsWith(`${uploadRoot}${path.sep}`)) {
        return false;
      }
      return fs.existsSync(filePath) && fs.statSync(filePath).isFile();
    } catch (_) {
      return false;
    }
  }
  return {
    leaveAttachmentDir,
    ALLOWED_LEAVE_ATTACHMENT_EXT,
    MAX_LEAVE_ATTACHMENT_SIZE,
    leaveAttachmentStorage,
    uploadLeaveAttachment,
    uploadLeaveAttachmentMemory,
    uploadLeaveAttachmentMw,
    uploadLeaveAttachmentMemoryMw,
    storedLeaveAttachmentFromMemoryFile,
    cleanupStoredLeaveAttachment,
    storedLeaveAttachmentExists,
  };
};
