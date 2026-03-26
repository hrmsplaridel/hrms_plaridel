const path = require('path');

const RSP_SUBDIR = 'rsp-attachments';

function getRspAttachmentsRoot(uploadDir) {
  return path.resolve(uploadDir, RSP_SUBDIR);
}

/**
 * Safe absolute path for a stored object, or null if path is unsafe.
 * Expected shape: {applicationId}/{fileName} (same as Supabase object key).
 */
function resolveLocalRspAttachment(uploadDir, objectPath) {
  const rel = String(objectPath ?? '')
    .trim()
    .replace(/^\/+/, '')
    .replace(/\\/g, '/');
  if (!rel || rel.includes('..')) return null;
  const segments = rel.split('/').filter((s) => s.length > 0);
  if (segments.length < 2) return null;

  const root = getRspAttachmentsRoot(uploadDir);
  const full = path.resolve(root, ...segments);
  const rootWithSep = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
  if (!full.startsWith(rootWithSep) && full !== root) return null;
  return full;
}

module.exports = {
  RSP_SUBDIR,
  getRspAttachmentsRoot,
  resolveLocalRspAttachment,
};
