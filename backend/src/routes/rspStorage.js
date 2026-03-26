/**
 * RSP recruitment attachments — signed URLs + view tokens via Supabase service role.
 */
const express = require('express');
const jwt = require('jsonwebtoken');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { isAttachmentPathAllowedInDb } = require('../utils/rspAttachmentPolicy');

const router = express.Router();
const protect = [authMiddleware, requireAdmin];

/**
 * Encode object path segments for Supabase Storage sign URL (path inside bucket).
 */
function encodeObjectPath(objectPath) {
  return String(objectPath)
    .replace(/^\/+/, '')
    .split('/')
    .filter((s) => s.length > 0)
    .map(encodeURIComponent)
    .join('/');
}

/**
 * Supabase returns signedURL as a path suffix; combine with project URL.
 */
function toAbsoluteSignedUrl(projectUrl, signedRelative) {
  if (!signedRelative) return signedRelative;
  if (signedRelative.startsWith('http')) return signedRelative;
  const base = projectUrl.replace(/\/$/, '');
  const rel = signedRelative.startsWith('/')
    ? signedRelative
    : `/${signedRelative}`;
  if (rel.startsWith('/storage/v')) {
    return `${base}${rel}`;
  }
  if (rel.startsWith('/object/')) {
    return `${base}/storage/v1${rel}`;
  }
  return `${base}${rel}`;
}

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
 * GET /api/rsp/storage/signed-url?path=...&bucket=...
 * Returns { url: string } — direct Supabase signed URL (fallback for clients).
 */
router.get('/signed-url', ...protect, async (req, res) => {
  const objectPath = req.query.path;
  const bucket =
    req.query.bucket ||
    process.env.SUPABASE_STORAGE_BUCKET ||
    'recruitment-attachments';

  if (!objectPath || String(objectPath).trim() === '') {
    return res.status(400).json({ error: 'path query parameter is required' });
  }

  try {
    const allowed = await isAttachmentPathAllowedInDb(objectPath);
    if (!allowed) {
      return res.status(403).json({
        error: 'Forbidden',
        details:
          'This file path is not linked to a recruitment application in PostgreSQL. ' +
          'Ensure attachment_path / storage prefix matches an application id.',
      });
    }
  } catch (err) {
    console.error('[rsp/storage/signed-url] db policy check', err);
    return res.status(503).json({
      error: 'Database unavailable for attachment policy check',
      details: err.message,
    });
  }

  const supabaseUrl = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !serviceKey) {
    return res.status(503).json({
      error: 'Storage signing not configured',
      details:
        'Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in backend .env (service role from Supabase Project Settings → API).',
    });
  }

  const encodedPath = encodeObjectPath(objectPath);
  const signEndpoint = `${supabaseUrl}/storage/v1/object/sign/${encodeURIComponent(
    bucket,
  )}/${encodedPath}`;

  const expiresIn = Math.min(
    Math.max(parseInt(req.query.expiresIn || '3600', 10) || 3600, 60),
    604800,
  );

  try {
    const r = await fetch(signEndpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${serviceKey}`,
        apikey: serviceKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ expiresIn }),
    });

    const text = await r.text();
    let data;
    try {
      data = text ? JSON.parse(text) : {};
    } catch {
      return res.status(502).json({
        error: 'Invalid response from storage',
        details: text?.slice(0, 200),
      });
    }

    if (!r.ok) {
      return res.status(r.status >= 400 ? r.status : 502).json({
        error: data.error || data.message || 'Failed to sign URL',
        details: data,
      });
    }

    const relative =
      data.signedURL ||
      data.signedUrl ||
      data.signed_url ||
      (typeof data === 'string' ? data : null);

    if (!relative || typeof relative !== 'string') {
      return res.status(502).json({
        error: 'Unexpected sign response',
        details: data,
      });
    }

    const url = toAbsoluteSignedUrl(supabaseUrl, relative);

    return res.json({ url, expiresIn });
  } catch (err) {
    console.error('[rsp/storage/signed-url]', err);
    return res.status(500).json({
      error: err.message || 'Failed to create signed URL',
    });
  }
});

module.exports = router;
