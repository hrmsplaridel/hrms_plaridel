/**
 * Admin-uploaded print backgrounds for RSP / L&D forms.
 * JWT + admin. One active file per (module, form_key).
 */
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
const TEMPLATE_SUBDIR = 'form-templates';
const templateDir = path.join(UPLOAD_DIR, TEMPLATE_SUBDIR);

const ALLOWED_FORMS = {
  rsp: [
    'bi',
    'applicants_profile',
    'selection_lineup',
    'computation_of_points',
    'work_experience',
    'turn_around_time',
    'ojt_work_immersion',
  ],
  ld: [
    'training_need_analysis',
    'action_brainstorming',
    'idp',
    'learning_application_plan',
  ],
};

const ALLOWED_SIZES = new Set([
  'a4',
  'letter',
  'letter_landscape',
  'long_13',
  'long_14',
  'long_landscape',
]);

if (!fs.existsSync(templateDir)) {
  fs.mkdirSync(templateDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, templateDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    const safeExt = ['.pdf', '.png', '.jpg', '.jpeg'].includes(ext) ? ext : '.dat';
    cb(null, `${uuidv4()}${safeExt}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ok = /\.(pdf|png|jpe?g)$/i.test(file.originalname || '');
    cb(null, ok);
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
    return false;
  } catch (_) {
    return false;
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

function unlinkQuiet(absPath) {
  fs.unlink(absPath, () => {});
}

function isSafeTemplatePath(relPath) {
  if (!relPath || relPath.includes('..') || path.isAbsolute(relPath)) return false;
  const normalized = relPath.replace(/\\/g, '/');
  return normalized.startsWith(`${TEMPLATE_SUBDIR}/`);
}

let tablesReady = false;

async function ensureTable() {
  if (tablesReady) return;
  await pool.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.form_print_templates (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      module TEXT NOT NULL CHECK (module IN ('rsp', 'ld')),
      form_key TEXT NOT NULL,
      paper_size TEXT NOT NULL,
      file_path TEXT NOT NULL,
      original_filename TEXT,
      mime_type TEXT,
      uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (module, form_key)
    );
  `);
  tablesReady = true;
}

function rowToJson(row) {
  if (!row) return null;
  return {
    id: row.id,
    module: row.module,
    formKey: row.form_key,
    paperSize: row.paper_size,
    originalFilename: row.original_filename,
    mimeType: row.mime_type,
    updatedAt: row.updated_at,
  };
}

function uploadMw(req, res, next) {
  upload.single('file')(req, res, (err) => {
    if (err) {
      return res.status(400).json({ error: err.message || 'Upload failed' });
    }
    next();
  });
}

router.use(authMiddleware, requireAdmin);

router.get('/', async (req, res) => {
  try {
    await ensureTable();
    const module = String(req.query.module || '').trim().toLowerCase();
    const params = [];
    let where = '';
    if (module === 'rsp' || module === 'ld') {
      params.push(module);
      where = 'WHERE module = $1';
    }
    const result = await pool.query(
      `SELECT id, module, form_key, paper_size, original_filename, mime_type, updated_at
       FROM public.form_print_templates ${where}
       ORDER BY module, form_key`,
      params,
    );
    res.json({ templates: result.rows.map(rowToJson) });
  } catch (err) {
    console.error('[form-print-templates list]', err);
    res.status(500).json({ error: 'Failed to list form backgrounds' });
  }
});

router.get('/:module/:formKey', async (req, res) => {
  try {
    await ensureTable();
    const module = String(req.params.module || '').trim().toLowerCase();
    const formKey = String(req.params.formKey || '').trim();
    if (!ALLOWED_FORMS[module]?.includes(formKey)) {
      return res.status(400).json({ error: 'Unknown form' });
    }
    const result = await pool.query(
      `SELECT id, module, form_key, paper_size, original_filename, mime_type, updated_at
       FROM public.form_print_templates WHERE module = $1 AND form_key = $2`,
      [module, formKey],
    );
    if (!result.rows[0]) {
      return res.status(404).json({ error: 'No background saved for this form' });
    }
    res.json(rowToJson(result.rows[0]));
  } catch (err) {
    console.error('[form-print-templates get]', err);
    res.status(500).json({ error: 'Failed to load form background' });
  }
});

router.get('/:module/:formKey/file', async (req, res) => {
  try {
    await ensureTable();
    const module = String(req.params.module || '').trim().toLowerCase();
    const formKey = String(req.params.formKey || '').trim();
    if (!ALLOWED_FORMS[module]?.includes(formKey)) {
      return res.status(400).json({ error: 'Unknown form' });
    }
    const result = await pool.query(
      `SELECT file_path, original_filename, mime_type
       FROM public.form_print_templates WHERE module = $1 AND form_key = $2`,
      [module, formKey],
    );
    const row = result.rows[0];
    if (!row?.file_path || !isSafeTemplatePath(row.file_path)) {
      return res.status(404).json({ error: 'Background file not found' });
    }
    const abs = path.resolve(UPLOAD_DIR, row.file_path);
    const root = path.resolve(templateDir);
    const relToRoot = path.relative(root, abs);
    if (
      relToRoot.startsWith('..') ||
      path.isAbsolute(relToRoot) ||
      !fs.existsSync(abs)
    ) {
      return res.status(404).json({ error: 'Background file not found' });
    }
    const name = String(row.original_filename || path.basename(abs))
      .replace(/[^\w.\- ()]/g, '_')
      .slice(0, 180);
    res.setHeader('Cache-Control', 'private, max-age=60');
    res.setHeader('Content-Disposition', `inline; filename="${name}"`);
    if (row.mime_type) res.setHeader('Content-Type', row.mime_type);
    res.sendFile(abs);
  } catch (err) {
    console.error('[form-print-templates file]', err);
    res.status(500).json({ error: 'Failed to serve form background' });
  }
});

router.post('/', uploadMw, async (req, res) => {
  const file = req.file;
  try {
    await ensureTable();
    if (!file) {
      return res.status(400).json({
        error: 'No file uploaded. Allowed: PDF, PNG, JPG (max 10MB).',
      });
    }
    const module = String(req.body?.module || '').trim().toLowerCase();
    const formKey = String(req.body?.form_key || '').trim();
    const paperSize = String(req.body?.paper_size || '').trim();
    if (!ALLOWED_FORMS[module]?.includes(formKey)) {
      unlinkQuiet(file.path);
      return res.status(400).json({ error: 'Select a valid RSP or L&D form' });
    }
    if (!ALLOWED_SIZES.has(paperSize)) {
      unlinkQuiet(file.path);
      return res.status(400).json({ error: 'Select a valid paper size' });
    }
    const ext = path.extname(file.filename || '').toLowerCase();
    if (!fileSignatureMatches(file.path, ext)) {
      unlinkQuiet(file.path);
      return res.status(400).json({ error: 'File type does not match its contents' });
    }

    const relPath = `${TEMPLATE_SUBDIR}/${file.filename}`.replace(/\\/g, '/');
    const mime =
      ext === '.pdf'
        ? 'application/pdf'
        : ext === '.png'
          ? 'image/png'
          : 'image/jpeg';

    const existing = await pool.query(
      `SELECT file_path FROM public.form_print_templates WHERE module = $1 AND form_key = $2`,
      [module, formKey],
    );
    const oldPath = existing.rows[0]?.file_path;

    const saved = await pool.query(
      `INSERT INTO public.form_print_templates
        (module, form_key, paper_size, file_path, original_filename, mime_type, uploaded_by, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, now())
       ON CONFLICT (module, form_key) DO UPDATE SET
         paper_size = EXCLUDED.paper_size,
         file_path = EXCLUDED.file_path,
         original_filename = EXCLUDED.original_filename,
         mime_type = EXCLUDED.mime_type,
         uploaded_by = EXCLUDED.uploaded_by,
         updated_at = now()
       RETURNING id, module, form_key, paper_size, original_filename, mime_type, updated_at`,
      [
        module,
        formKey,
        paperSize,
        relPath,
        file.originalname || file.filename,
        mime,
        req.user?.id || null,
      ],
    );

    if (oldPath && oldPath !== relPath && isSafeTemplatePath(oldPath)) {
      unlinkQuiet(path.resolve(UPLOAD_DIR, oldPath));
    }

    res.status(201).json(rowToJson(saved.rows[0]));
  } catch (err) {
    if (file?.path) unlinkQuiet(file.path);
    console.error('[form-print-templates save]', err);
    res.status(500).json({ error: 'Failed to save form background' });
  }
});

router.delete('/:module/:formKey', async (req, res) => {
  try {
    await ensureTable();
    const module = String(req.params.module || '').trim().toLowerCase();
    const formKey = String(req.params.formKey || '').trim();
    if (!ALLOWED_FORMS[module]?.includes(formKey)) {
      return res.status(400).json({ error: 'Unknown form' });
    }
    const result = await pool.query(
      `DELETE FROM public.form_print_templates
       WHERE module = $1 AND form_key = $2
       RETURNING file_path`,
      [module, formKey],
    );
    const oldPath = result.rows[0]?.file_path;
    if (oldPath && isSafeTemplatePath(oldPath)) {
      unlinkQuiet(path.resolve(UPLOAD_DIR, oldPath));
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('[form-print-templates delete]', err);
    res.status(500).json({ error: 'Failed to remove form background' });
  }
});

module.exports = router;
