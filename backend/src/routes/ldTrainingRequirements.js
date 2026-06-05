const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const jwt = require('jsonwebtoken');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { isLdTrainingRequirementPathAllowed } = require('../utils/ldTrainingRequirementPolicy');

const router = express.Router();
const protect = [authMiddleware];
const adminProtect = [authMiddleware, requireAdmin];

const LD_SUBDIR = 'ld-training-requirements';
const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');
const ldRoot = path.join(UPLOAD_DIR, LD_SUBDIR);
if (!fs.existsSync(ldRoot)) {
  fs.mkdirSync(ldRoot, { recursive: true });
}

/** @type {Record<string, { pathCol: string, nameCol: string }>} */
const DOC_KIND_COLUMNS = {
  invitation_letter: {
    pathCol: 'doc_invitation_letter_path',
    nameCol: 'doc_invitation_letter_name',
  },
  lap: { pathCol: 'doc_lap_path', nameCol: 'doc_lap_name' },
  training_certificate: {
    pathCol: 'doc_training_certificate_path',
    nameCol: 'doc_training_certificate_name',
  },
};

function parseDocKind(value) {
  if (value == null || typeof value !== 'string') return null;
  const k = value.trim();
  return Object.prototype.hasOwnProperty.call(DOC_KIND_COLUMNS, k) ? k : null;
}

const ROW_SELECT = `
  r.id,
  r.employee_id,
  r.training_title,
  r.doc_invitation_letter_path,
  r.doc_invitation_letter_name,
  r.doc_lap_path,
  r.doc_lap_name,
  r.doc_training_certificate_path,
  r.doc_training_certificate_name,
  r.pre_requirements_approved,
  r.post_requirements_approved,
  r.created_at,
  r.updated_at,
  u.full_name AS employee_name,
  u.email AS employee_email
`.replace(/\s+/g, ' ');

async function ensureTable() {
  await pool.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.ld_training_requirement_records (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      employee_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      training_title TEXT,
      doc_invitation_letter_path TEXT,
      doc_invitation_letter_name TEXT,
      doc_lap_path TEXT,
      doc_lap_name TEXT,
      doc_training_certificate_path TEXT,
      doc_training_certificate_name TEXT,
      pre_requirements_approved BOOLEAN NOT NULL DEFAULT FALSE,
      post_requirements_approved BOOLEAN NOT NULL DEFAULT FALSE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      CONSTRAINT uq_ld_training_requirement_employee UNIQUE (employee_id)
    );
  `);
}

function mapRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    employee_id: row.employee_id,
    employee_name: row.employee_name,
    employee_email: row.employee_email,
    training_title: row.training_title,
    doc_invitation_letter_path: row.doc_invitation_letter_path,
    doc_invitation_letter_name: row.doc_invitation_letter_name,
    doc_lap_path: row.doc_lap_path,
    doc_lap_name: row.doc_lap_name,
    doc_training_certificate_path: row.doc_training_certificate_path,
    doc_training_certificate_name: row.doc_training_certificate_name,
    pre_requirements_approved: row.pre_requirements_approved === true,
    post_requirements_approved: row.post_requirements_approved === true,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

async function getRecordById(recordId) {
  const { rows } = await pool.query(
    `
    SELECT ${ROW_SELECT}
    FROM public.ld_training_requirement_records r
    JOIN public.users u ON u.id = r.employee_id
    WHERE r.id = $1
    `,
    [recordId],
  );
  return rows[0] || null;
}

async function ensureEmployeeRecord(employeeId, trainingTitle) {
  await ensureTable();
  const existing = await pool.query(
    `SELECT id FROM public.ld_training_requirement_records WHERE employee_id = $1`,
    [employeeId],
  );
  if (existing.rows[0]) {
    if (trainingTitle && typeof trainingTitle === 'string' && trainingTitle.trim()) {
      await pool.query(
        `
        UPDATE public.ld_training_requirement_records
        SET training_title = $1, updated_at = now()
        WHERE employee_id = $2
        `,
        [trainingTitle.trim(), employeeId],
      );
    }
    return getRecordById(existing.rows[0].id);
  }
  const ins = await pool.query(
    `
    INSERT INTO public.ld_training_requirement_records (employee_id, training_title)
    VALUES ($1, $2)
    RETURNING id
    `,
    [employeeId, trainingTitle?.trim() || null],
  );
  return getRecordById(ins.rows[0].id);
}

const ldUpload = multer({
  storage: multer.diskStorage({
    destination: (req, _file, cb) => {
      const { recordId } = req.params;
      const dir = path.join(ldRoot, recordId);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      cb(null, dir);
    },
    filename: (req, file, cb) => {
      const base = path
        .basename(file.originalname || 'file')
        .replace(/[^\w.\- ()]/g, '_')
        .slice(0, 180);
      const kind = parseDocKind(req.query?.kind);
      cb(null, kind ? `${kind}_${Date.now()}_${base}` : `${Date.now()}_${base}`);
    },
  }),
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    cb(null, /\.pdf$/i.test(file.originalname || ''));
  },
});

// GET /api/ld/training-requirements — admin list
router.get('/', adminProtect, async (_req, res) => {
  try {
    await ensureTable();
    const { rows } = await pool.query(
      `
      SELECT ${ROW_SELECT}
      FROM public.ld_training_requirement_records r
      JOIN public.users u ON u.id = r.employee_id
      ORDER BY u.full_name ASC
      `,
    );
    return res.json(rows.map(mapRow));
  } catch (err) {
    console.error('[ldTrainingRequirements GET /]', err);
    return res.status(500).json({ error: 'Failed to list training requirements' });
  }
});

// GET /api/ld/training-requirements/mine — employee record (auto-create)
router.get('/mine', protect, async (req, res) => {
  try {
    const row = await ensureEmployeeRecord(req.user.id, null);
    return res.json({ record: mapRow(row) });
  } catch (err) {
    console.error('[ldTrainingRequirements GET /mine]', err);
    return res.status(500).json({ error: 'Failed to load your training requirements' });
  }
});

// PUT /api/ld/training-requirements/mine — employee update training title
router.put('/mine', protect, async (req, res) => {
  try {
    const { trainingTitle } = req.body || {};
    const row = await ensureEmployeeRecord(req.user.id, trainingTitle);
    return res.json({ ok: true, record: mapRow(row) });
  } catch (err) {
    console.error('[ldTrainingRequirements PUT /mine]', err);
    return res.status(500).json({ error: 'Failed to update training title' });
  }
});

// GET /api/ld/training-requirements/view-token?path=&fileName=
router.get('/view-token', protect, async (req, res) => {
  const objectPath = req.query.path;
  const fileName = (req.query.fileName || '').trim();
  if (!objectPath || String(objectPath).trim() === '') {
    return res.status(400).json({ error: 'path is required' });
  }
  if (!process.env.JWT_SECRET) {
    return res.status(503).json({ error: 'JWT_SECRET not configured' });
  }
  try {
    const allowed = await isLdTrainingRequirementPathAllowed(objectPath);
    if (!allowed) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const { rows } = await pool.query(
      `
      SELECT employee_id
      FROM public.ld_training_requirement_records r
      WHERE btrim($1::text) = btrim(COALESCE(r.doc_invitation_letter_path, ''))
         OR btrim($1::text) = btrim(COALESCE(r.doc_lap_path, ''))
         OR btrim($1::text) = btrim(COALESCE(r.doc_training_certificate_path, ''))
         OR btrim($1::text) LIKE r.id::text || '/%'
      LIMIT 1
      `,
      [String(objectPath).trim()],
    );
    const ownerId = rows[0]?.employee_id;
    const isAdmin = req.user?.role === 'admin';
    if (!isAdmin && ownerId !== req.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const token = jwt.sign(
      { typ: 'ld_training_req', path: String(objectPath).trim(), fn: fileName || undefined },
      process.env.JWT_SECRET,
      { expiresIn: '1h' },
    );
    return res.json({ token });
  } catch (err) {
    console.error('[ldTrainingRequirements view-token]', err);
    return res.status(500).json({ error: 'Failed to create view token' });
  }
});

// POST /api/ld/training-requirements/:recordId/attachment-file?kind=
router.post(
  '/:recordId/attachment-file',
  protect,
  ldUpload.single('file'),
  async (req, res) => {
    try {
      await ensureTable();
      const { recordId } = req.params;
      if (!req.file) {
        return res.status(400).json({ error: 'file is required (multipart PDF)' });
      }
      const row = await getRecordById(recordId);
      if (!row) {
        try { fs.unlinkSync(req.file.path); } catch (_) { /* ignore */ }
        return res.status(404).json({ error: 'Record not found' });
      }
      const isAdmin = req.user?.role === 'admin';
      if (!isAdmin && row.employee_id !== req.user.id) {
        try { fs.unlinkSync(req.file.path); } catch (_) { /* ignore */ }
        return res.status(403).json({ error: 'Forbidden' });
      }
      const docKind = parseDocKind(req.query?.kind);
      if (!docKind) {
        try { fs.unlinkSync(req.file.path); } catch (_) { /* ignore */ }
        return res.status(400).json({ error: 'kind query parameter is required' });
      }
      const relPath = `${recordId}/${req.file.filename}`;
      const origName = req.file.originalname || req.file.filename;
      const { pathCol, nameCol } = DOC_KIND_COLUMNS[docKind];
      await pool.query(
        `
        UPDATE public.ld_training_requirement_records
        SET "${pathCol}" = $1,
            "${nameCol}" = $2,
            pre_requirements_approved = CASE
              WHEN $3::text = 'invitation_letter' THEN FALSE
              ELSE pre_requirements_approved
            END,
            post_requirements_approved = CASE
              WHEN $3::text IN ('lap', 'training_certificate') THEN FALSE
              ELSE post_requirements_approved
            END,
            updated_at = now()
        WHERE id = $4
        `,
        [relPath, origName, docKind, recordId],
      );
      return res.json({ ok: true, path: relPath, fileName: origName });
    } catch (err) {
      if (req.file?.path) {
        try { fs.unlinkSync(req.file.path); } catch (_) { /* ignore */ }
      }
      console.error('[ldTrainingRequirements POST attachment-file]', err);
      return res.status(500).json({ error: 'Failed to store attachment' });
    }
  },
);

// PUT /api/ld/training-requirements/:recordId/pre-approval
router.put('/:recordId/pre-approval', adminProtect, async (req, res) => {
  try {
    await ensureTable();
    const { recordId } = req.params;
    const { approved } = req.body || {};
    if (typeof approved !== 'boolean') {
      return res.status(400).json({ error: 'approved is required (true or false)' });
    }
    const check = await pool.query(
      `SELECT doc_invitation_letter_path FROM public.ld_training_requirement_records WHERE id = $1`,
      [recordId],
    );
    if (!check.rows[0]) {
      return res.status(404).json({ error: 'Record not found' });
    }
    if (approved && !check.rows[0].doc_invitation_letter_path) {
      return res.status(400).json({
        error: 'Invitation letter must be uploaded before pre-training approval',
      });
    }
    const { rows } = await pool.query(
      `
      UPDATE public.ld_training_requirement_records
      SET pre_requirements_approved = $1, updated_at = now()
      WHERE id = $2
      RETURNING id
      `,
      [approved, recordId],
    );
    const row = await getRecordById(rows[0].id);
    return res.json({ ok: true, record: mapRow(row) });
  } catch (err) {
    console.error('[ldTrainingRequirements PUT pre-approval]', err);
    return res.status(500).json({ error: 'Failed to update pre-training approval' });
  }
});

// PUT /api/ld/training-requirements/:recordId/post-approval
router.put('/:recordId/post-approval', adminProtect, async (req, res) => {
  try {
    await ensureTable();
    const { recordId } = req.params;
    const { approved } = req.body || {};
    if (typeof approved !== 'boolean') {
      return res.status(400).json({ error: 'approved is required (true or false)' });
    }
    const check = await pool.query(
      `
      SELECT doc_lap_path, doc_training_certificate_path, pre_requirements_approved
      FROM public.ld_training_requirement_records
      WHERE id = $1
      `,
      [recordId],
    );
    if (!check.rows[0]) {
      return res.status(404).json({ error: 'Record not found' });
    }
    const row = check.rows[0];
    if (approved) {
      if (row.pre_requirements_approved !== true) {
        return res.status(400).json({
          error: 'Pre-training requirements must be approved first',
        });
      }
      const missing = [];
      if (!row.doc_lap_path) missing.push('Learning Application Plan (LAP)');
      if (!row.doc_training_certificate_path) missing.push('Training Certificate');
      if (missing.length > 0) {
        return res.status(400).json({
          error: `Missing: ${missing.join(', ')}`,
        });
      }
    }
    const upd = await pool.query(
      `
      UPDATE public.ld_training_requirement_records
      SET post_requirements_approved = $1, updated_at = now()
      WHERE id = $2
      RETURNING id
      `,
      [approved, recordId],
    );
    const full = await getRecordById(upd.rows[0].id);
    return res.json({ ok: true, record: mapRow(full) });
  } catch (err) {
    console.error('[ldTrainingRequirements PUT post-approval]', err);
    return res.status(500).json({ error: 'Failed to update post-training approval' });
  }
});

module.exports = router;
