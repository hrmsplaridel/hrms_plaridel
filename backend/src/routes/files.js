const express = require('express');
const path = require('path');
const fs = require('fs');
const os = require('os');
const jwt = require('jsonwebtoken');
const { execFile } = require('child_process');
const { pool } = require('../config/db');
const { isAttachmentPathAllowedInDb } = require('../utils/rspAttachmentPolicy');
const { fetchSupabaseObjectResponse } = require('../utils/supabaseStorageFetch');
const {
  resolveLocalRspAttachment,
} = require('../utils/rspLocalAttachment');

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
  const asPreview =
    req.query.preview === '1' || req.query.preview === 'true';

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

    const localAbs = resolveLocalRspAttachment(UPLOAD_DIR, objectPath);
    if (localAbs && fs.existsSync(localAbs)) {
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
        // Encourage inline rendering (especially for PDFs inside iframes).
        res.setHeader(
          'Content-Disposition',
          `inline; filename="${safeName}"`,
        );

        const extLower = path.extname(localAbs).toLowerCase();
        const isOfficeDoc =
          extLower === '.doc' ||
          extLower === '.docx' ||
          extLower === '.xls' ||
          extLower === '.xlsx' ||
          extLower === '.ppt' ||
          extLower === '.pptx';
        if (asPreview && isOfficeDoc) {
          try {
            const pdfBuf = await convertOfficeFileToPdf(localAbs, extLower);
            const pdfName = safeName.replace(/\.[^./\\]+$/i, '.pdf');
            res.setHeader('Content-Disposition', `inline; filename="${pdfName}"`);
            res.setHeader('Content-Type', 'application/pdf');
            return res.send(pdfBuf);
          } catch (e) {
            const msg =
              'Word preview failed. ' +
              'To preview .doc/.docx inline, install LibreOffice (soffice) on the backend server ' +
              'and ensure `soffice` is available in PATH.';
            return res
              .status(200)
              .type('text/html')
              .send(`<html><body><pre>${escapeHtml(msg)}<br/><br/>Error: ${escapeHtml(
                e?.message ? String(e.message) : String(e),
              )}</pre></body></html>`);
          }
        }
        if (extLower === '.pdf') res.setHeader('Content-Type', 'application/pdf');
        if (extLower === '.png') res.setHeader('Content-Type', 'image/png');
        if (extLower === '.jpg' || extLower === '.jpeg') {
          res.setHeader('Content-Type', 'image/jpeg');
        }
        if (extLower === '.gif') res.setHeader('Content-Type', 'image/gif');
        if (extLower === '.webp') res.setHeader('Content-Type', 'image/webp');
        if (extLower === '.doc') res.setHeader('Content-Type', 'application/msword');
        if (extLower === '.docx')
          res.setHeader(
            'Content-Type',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          );
      }
      return res.sendFile(path.resolve(localAbs));
    }

    const supabaseUrl = (process.env.SUPABASE_URL || '').trim();
    const supabaseKey = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
    if (!supabaseUrl || !supabaseKey) {
      return res
        .status(404)
        .type('text/plain')
        .send(
          'Attachment not found on this server. ' +
            'Expected: uploads/rsp-attachments/. ' +
            'Supabase is not configured (set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY).',
        );
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

    // Optional: inline preview conversion for Office docs stored in Supabase.
    const objectLower = String(objectPath).toLowerCase();
    const isOfficeDocStored =
      objectLower.endsWith('.doc') ||
      objectLower.endsWith('.docx') ||
      objectLower.endsWith('.xls') ||
      objectLower.endsWith('.xlsx') ||
      objectLower.endsWith('.ppt') ||
      objectLower.endsWith('.pptx');
    if (asPreview && isOfficeDocStored) {
      try {
        const tmpInputExt = path.extname(objectPath).toLowerCase();
        const pdfBuf = await convertOfficeBytesToPdf(buf, tmpInputExt);
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `inline; filename="${safeName.replace(/\.(docx?|doc)$/i, '.pdf')}"`);
        return res.send(pdfBuf);
      } catch (e) {
        const msg =
          'Word preview failed (Supabase). ' +
          'Install LibreOffice (soffice) on the backend server to convert .doc/.docx to PDF.';
        return res
          .status(200)
          .type('text/html')
          .send(`<html><body><pre>${escapeHtml(msg)}<br/><br/>Error: ${escapeHtml(
            e?.message ? String(e.message) : String(e),
          )}</pre></body></html>`);
      }
    }

    return res.send(buf);
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

function escapeHtml(s) {
  return String(s ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

async function convertOfficeFileToPdf(inputPath, inputExtLower) {
  const tmpDir = await fs.promises.mkdtemp(
    path.join(os.tmpdir(), 'hrms-rsp-doc-'),
  );
  try {
    // Copy into tmp dir so conversion output is predictable and isolated.
    const tmpInput = path.join(tmpDir, `input${inputExtLower}`);
    await fs.promises.copyFile(inputPath, tmpInput);

    await execSofficeToPdf(tmpDir, tmpInput);

    const files = await fs.promises.readdir(tmpDir);
    const pdfs = files.filter((f) => f.toLowerCase().endsWith('.pdf'));
    if (pdfs.length === 0) {
      throw new Error('LibreOffice conversion produced no PDF');
    }
    const pdfPath = path.join(tmpDir, pdfs[0]);
    return await fs.promises.readFile(pdfPath);
  } finally {
    try {
      await fs.promises.rm(tmpDir, { recursive: true, force: true });
    } catch (_) {
      /* ignore */
    }
  }
}

async function convertOfficeBytesToPdf(buf, inputExtLower) {
  const tmpDir = await fs.promises.mkdtemp(
    path.join(os.tmpdir(), 'hrms-rsp-doc-'),
  );
  try {
    const tmpInput = path.join(tmpDir, `input${inputExtLower}`);
    await fs.promises.writeFile(tmpInput, buf);
    await execSofficeToPdf(tmpDir, tmpInput);

    const files = await fs.promises.readdir(tmpDir);
    const pdfs = files.filter((f) => f.toLowerCase().endsWith('.pdf'));
    if (pdfs.length === 0) {
      throw new Error('LibreOffice conversion produced no PDF');
    }
    const pdfPath = path.join(tmpDir, pdfs[0]);
    return await fs.promises.readFile(pdfPath);
  } finally {
    try {
      await fs.promises.rm(tmpDir, { recursive: true, force: true });
    } catch (_) {
      /* ignore */
    }
  }
}

async function execSofficeToPdf(outDir, inputPath) {
  const candidates = ['soffice', 'soffice.exe'];
  let lastErr;
  for (const bin of candidates) {
    try {
      await execFile(bin, [
        '--headless',
        '--norestore',
        '--convert-to',
        'pdf',
        '--outdir',
        outDir,
        inputPath,
      ], { timeout: 120000 });
      return;
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr || new Error('soffice not available for conversion');
}

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
