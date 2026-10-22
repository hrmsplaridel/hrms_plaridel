'use strict';
module.exports = function createLocatorComponent({
  LOCATOR_ATTACHMENT_SUBDIR,
  UPLOAD_DIR,
  fs,
  multer,
  path,
  resolveLocatorTypeMetadata,
  validateLocatorAttachmentForReview,
}) {
  const locatorAttachmentDir = path.join(UPLOAD_DIR, LOCATOR_ATTACHMENT_SUBDIR);

  if (!fs.existsSync(locatorAttachmentDir)) {
    fs.mkdirSync(locatorAttachmentDir, { recursive: true });
  }

  const ALLOWED_LOCATOR_ATTACHMENT_EXT = /\.(pdf|jpg|jpeg|png)$/i;

  const MAX_LOCATOR_ATTACHMENT_SIZE = 10 * 1024 * 1024;

  const locatorAttachmentStorage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, locatorAttachmentDir),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname || '').toLowerCase();
      const safeExt = ALLOWED_LOCATOR_ATTACHMENT_EXT.test(ext) ? ext : '.pdf';
      cb(null, `${Date.now()}-${Math.random().toString(36).slice(2)}${safeExt}`);
    },
  });

  const uploadLocatorAttachment = multer({
    storage: locatorAttachmentStorage,
    limits: { fileSize: MAX_LOCATOR_ATTACHMENT_SIZE, fieldSize: 3 * 1024 * 1024 },
    fileFilter: (_req, file, cb) => {
      const name = file.originalname || '';
      if (!ALLOWED_LOCATOR_ATTACHMENT_EXT.test(name)) {
        return cb(new Error('Only PDF, JPG, JPEG, or PNG files are allowed.'));
      }
      cb(null, true);
    },
  });

  function uploadLocatorAttachmentMw(req, res, next) {
    uploadLocatorAttachment.single('file')(req, res, (err) => {
      if (!err) return next();
      const message =
        err.code === 'LIMIT_FILE_SIZE'
          ? 'Attachment must be 10MB or smaller.'
          : err.message || 'Invalid attachment.';
      return res.status(400).json({ error: message });
    });
  }

  function locatorAttachmentFileExists(relativePath) {
    if (!(relativePath || '').toString().trim()) return false;
    const root = path.resolve(locatorAttachmentDir);
    const filePath = path.resolve(UPLOAD_DIR, relativePath);
    if (!filePath.startsWith(`${root}${path.sep}`)) return false;
    try {
      return fs.statSync(filePath).isFile();
    } catch (_) {
      return false;
    }
  }

  function removeLocatorAttachmentFile(relativePath) {
    if (!locatorAttachmentFileExists(relativePath)) return;
    try {
      fs.unlinkSync(path.resolve(UPLOAD_DIR, relativePath));
    } catch (_) {}
  }

  function locatorReviewAttachmentError(row) {
    const requiresAttachment = resolveLocatorTypeMetadata(row).requiresAttachment;
    return validateLocatorAttachmentForReview({
      locatorType: { requires_attachment: requiresAttachment },
      attachmentPath: row.attachment_path,
      attachmentFileExists: locatorAttachmentFileExists(row.attachment_path),
    });
  }
  return {
    locatorAttachmentDir,
    ALLOWED_LOCATOR_ATTACHMENT_EXT,
    MAX_LOCATOR_ATTACHMENT_SIZE,
    locatorAttachmentStorage,
    uploadLocatorAttachment,
    uploadLocatorAttachmentMw,
    locatorAttachmentFileExists,
    removeLocatorAttachmentFile,
    locatorReviewAttachmentError,
  };
};
