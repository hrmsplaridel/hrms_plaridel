const fs = require('fs');
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

function _normName(name) {
  return String(name ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

/**
 * When the exact stored path is missing (e.g. folder renamed / re-apply),
 * try to recover by matching the original display file name under:
 * 1) same application folder
 * 2) any rsp-attachments application folder
 *
 * Multer names look like: `{kind}_{timestamp}_{originalName}`
 */
function findLocalRspAttachment(uploadDir, objectPath, originalFileName) {
  const exact = resolveLocalRspAttachment(uploadDir, objectPath);
  if (exact && fs.existsSync(exact)) return exact;

  const root = getRspAttachmentsRoot(uploadDir);
  if (!fs.existsSync(root)) return null;

  const rel = String(objectPath ?? '')
    .trim()
    .replace(/^\/+/, '')
    .replace(/\\/g, '/');
  const appId = rel.split('/').filter(Boolean)[0] || '';
  const storedBase = path.basename(rel);
  const wantOrig = _normName(originalFileName);
  const wantStored = _normName(storedBase);

  const matchInDir = (dir) => {
    let names;
    try {
      names = fs.readdirSync(dir);
    } catch (_) {
      return null;
    }
    // Exact basename first.
    for (const name of names) {
      if (_normName(name) === wantStored) {
        const full = path.join(dir, name);
        if (fs.statSync(full).isFile()) return full;
      }
    }
    if (!wantOrig) return null;
    // Prefer suffix match: *_Original Name.pdf
    for (const name of names) {
      const n = _normName(name);
      if (n === wantOrig || n.endsWith(`_${wantOrig}`) || n.endsWith(wantOrig)) {
        const full = path.join(dir, name);
        if (fs.statSync(full).isFile()) return full;
      }
    }
    return null;
  };

  if (appId) {
    const appDir = path.join(root, appId);
    if (fs.existsSync(appDir) && fs.statSync(appDir).isDirectory()) {
      const hit = matchInDir(appDir);
      if (hit) return hit;
    }
  }

  // Cross-folder recovery (same person re-applied under a new application id).
  try {
    for (const id of fs.readdirSync(root)) {
      if (appId && id === appId) continue;
      const dir = path.join(root, id);
      if (!fs.statSync(dir).isDirectory()) continue;
      const hit = matchInDir(dir);
      if (hit) return hit;
    }
  } catch (_) {
    /* ignore */
  }

  return null;
}

module.exports = {
  RSP_SUBDIR,
  getRspAttachmentsRoot,
  resolveLocalRspAttachment,
  findLocalRspAttachment,
};
