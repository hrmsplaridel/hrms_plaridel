const express = require('express');
const path = require('path');
const fs = require('fs');
const os = require('os');
const jwt = require('jsonwebtoken');
const { execFile } = require('child_process');
const { pool } = require('../config/db');
const { isAttachmentPathAllowedInDb } = require('../utils/rspAttachmentPolicy');
const {
  isLdTrainingRequirementPathAllowed,
} = require('../utils/ldTrainingRequirementPolicy');
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

    res.setHeader('Cache-Control', 'private, no-store');
    res.sendFile(path.resolve(filePath));
  } catch (err) {
    console.error('[files avatar]', err);
    res.status(500).json({ error: 'Failed to serve avatar' });
  }
});

/**
 * GET /api/files/recruitment-attachment?token=...&download=1
 * Serves files from uploads/rsp-attachments. Token from GET /api/rsp/storage/view-token.
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

    return res.status(404).json({
      error: 'Attachment not found',
      details:
        'File is not under uploads/rsp-attachments/. Upload via the API or restore from backup.',
    });
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
 * GET /api/files/ld-training-requirement?token=...&download=1
 */
router.get('/ld-training-requirement', async (req, res) => {
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
    if (payload.typ !== 'ld_training_req' || !payload.path) {
      return res.status(403).json({ error: 'Invalid token' });
    }

    const objectPath = String(payload.path).trim();
    const allowed = await isLdTrainingRequirementPathAllowed(objectPath);
    if (!allowed) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const ldRoot = path.resolve(UPLOAD_DIR, 'ld-training-requirements');
    const localAbs = path.resolve(ldRoot, objectPath);
    if (!localAbs.startsWith(`${ldRoot}${path.sep}`)) {
      return res.status(403).json({ error: 'Invalid attachment path' });
    }
    if (!fs.existsSync(localAbs)) {
      return res.status(404).json({ error: 'File not found' });
    }

    const safeName = (payload.fn || path.basename(objectPath) || 'attachment')
      .replace(/[^\w.\- ()]/g, '_')
      .slice(0, 180);
    if (asDownload) {
      res.setHeader('Content-Disposition', `attachment; filename="${safeName}"`);
    } else {
      res.setHeader('Cache-Control', 'private, max-age=300');
      res.setHeader('Content-Disposition', `inline; filename="${safeName}"`);
      if (path.extname(localAbs).toLowerCase() === '.pdf') {
        res.setHeader('Content-Type', 'application/pdf');
      }
    }
    return res.sendFile(path.resolve(localAbs));
  } catch (e) {
    if (e.name === 'JsonWebTokenError' || e.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Invalid or expired link' });
    }
    console.error('[files ld-training-requirement]', e);
    return res.status(500).json({ error: 'Failed to serve attachment' });
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
    const token = typeof req.query.token === 'string' ? req.query.token.trim() : '';
    if (!token || !process.env.JWT_SECRET) {
      return res.status(401).json({ error: 'A valid attachment token is required' });
    }
    try {
      const payload = jwt.verify(token, process.env.JWT_SECRET);
      if (
        payload.typ !== 'training_attachment' ||
        String(payload.attachmentId) !== String(attachmentId)
      ) {
        return res.status(403).json({ error: 'Invalid attachment token' });
      }
    } catch (_) {
      return res.status(401).json({ error: 'Invalid or expired attachment token' });
    }
    const result = await pool.query(
      'SELECT file_path FROM training_report_attachments WHERE id = $1',
      [attachmentId]
    );
    const row = result.rows[0];
    if (!row?.file_path) {
      return res.status(404).json({ error: 'Attachment not found' });
    }

    const trainingRoot = path.resolve(UPLOAD_DIR, 'training-reports');
    const filePath = path.resolve(UPLOAD_DIR, row.file_path);
    if (!filePath.startsWith(`${trainingRoot}${path.sep}`)) {
      return res.status(403).json({ error: 'Invalid attachment path' });
    }
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
