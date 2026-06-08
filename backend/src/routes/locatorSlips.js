const express = require('express');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrHr } = require('../middleware/rbac');
const {
  getDepartmentHeadForEmployee,
  getEmployeeDepartment,
  isDepartmentHead,
} = require('../services/departmentHeadService');
const locatorNotifications = require('../services/locatorNotifications');
const { broadcastAppEvent } = require('../websockets/appEvents');

const router = express.Router();
const protect = [authMiddleware];
const DEFAULT_LOCATOR_TYPES = [
  {
    code: 'locator',
    label: 'Locator / Official Business',
    short_label: 'Locator',
    location_label: 'Office / Destination',
    location_hint: 'Enter office or destination',
    dtr_slot_label: 'On Field',
    dtr_print_label: 'ON FIELD',
    requires_attachment: false,
    coverage_mode: 'manual',
    sort_order: 10,
  },
  {
    code: 'pass_slip',
    label: 'Pass Slip',
    short_label: 'Pass Slip',
    location_label: 'Destination / Location',
    location_hint: 'Enter destination or location',
    dtr_slot_label: 'Pass Slip',
    dtr_print_label: 'PASS SLIP',
    requires_attachment: false,
    coverage_mode: 'manual',
    sort_order: 20,
  },
  {
    code: 'work_from_home',
    label: 'Work From Home',
    short_label: 'WFH',
    location_label: 'Work Location',
    location_hint: 'Enter work location',
    dtr_slot_label: 'WFH',
    dtr_print_label: 'WFH',
    requires_attachment: false,
    coverage_mode: 'wfh',
    sort_order: 30,
  },
];
const DEFAULT_LOCATOR_TYPE_CODES = new Set(DEFAULT_LOCATOR_TYPES.map((t) => t.code));
const LOCATOR_ATTACHMENT_SUBDIR = 'locator-attachments';
const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '..', '..', 'uploads');
const locatorAttachmentDir = path.join(UPLOAD_DIR, LOCATOR_ATTACHMENT_SUBDIR);
if (!fs.existsSync(locatorAttachmentDir)) {
  fs.mkdirSync(locatorAttachmentDir, { recursive: true });
}
const ALLOWED_LOCATOR_ATTACHMENT_EXT = /\.(pdf|jpg|jpeg|png)$/i;
const MAX_LOCATOR_ATTACHMENT_SIZE = 10 * 1024 * 1024;
const DEFAULT_WORKING_DAYS = [1, 2, 3, 4, 5];
const WEEKDAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

function notifySafe(fn) {
  Promise.resolve()
    .then(() => fn())
    .catch((e) => console.error('[locator notification]', e));
}

function broadcastLocatorUpdated(action, row = {}, extra = {}) {
  try {
    const slipId = row.id || extra.slipId || null;
    broadcastAppEvent('locator_updated', {
      action,
      slipId,
      locatorSlipId: slipId,
      userId: row.employee_id || row.userId || extra.userId || null,
      status: row.status || extra.status || null,
      updatedAt: new Date().toISOString(),
      ...extra,
    });
  } catch (e) {
    console.error('[locator websocket]', e);
  }
}

function normalizeRequestType(value) {
  const type = (value || 'locator').toString().trim().toLowerCase();
  return /^[a-z0-9_][a-z0-9_-]{1,63}$/.test(type) ? type : null;
}

function boolField(value, fallback = false) {
  if (value === true || value === 'true' || value === 1 || value === '1') return true;
  if (value === false || value === 'false' || value === 0 || value === '0') return false;
  return fallback;
}

function textField(value, fallback = '') {
  const text = (value ?? '').toString().trim();
  return text || fallback;
}

function intField(value, fallback = 0) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeCoverageMode(value) {
  const mode = (value || 'manual').toString().trim().toLowerCase();
  return mode === 'wfh' ? 'wfh' : 'manual';
}

function locatorTypePayloadFromBody(body, existing = null) {
  const rawCode = existing?.code || body.code;
  const code = normalizeRequestType(rawCode);
  if (!code) throw new Error('Valid code is required.');
  const label = textField(body.label, existing?.label || '');
  if (!label) throw new Error('Label is required.');
  return {
    code,
    label,
    short_label: textField(body.short_label ?? body.shortLabel, existing?.short_label || label),
    location_label: textField(
      body.location_label ?? body.locationLabel,
      existing?.location_label || 'Office / Destination'
    ),
    location_hint: textField(
      body.location_hint ?? body.locationHint,
      existing?.location_hint || 'Enter office or destination'
    ),
    dtr_slot_label: textField(body.dtr_slot_label ?? body.dtrSlotLabel, existing?.dtr_slot_label || label),
    dtr_print_label: textField(
      body.dtr_print_label ?? body.dtrPrintLabel,
      existing?.dtr_print_label || label.toUpperCase()
    ),
    requires_attachment: boolField(
      body.requires_attachment ?? body.requiresAttachment,
      existing?.requires_attachment === true
    ),
    coverage_mode: normalizeCoverageMode(body.coverage_mode ?? body.coverageMode ?? existing?.coverage_mode),
    is_active: boolField(body.is_active ?? body.isActive, existing?.is_active !== false),
    sort_order: intField(body.sort_order ?? body.sortOrder, existing?.sort_order || 0),
  };
}

function mapLocatorTypeRow(row) {
  return {
    id: row.id,
    code: row.code,
    label: row.label,
    short_label: row.short_label,
    location_label: row.location_label,
    location_hint: row.location_hint,
    dtr_slot_label: row.dtr_slot_label,
    dtr_print_label: row.dtr_print_label,
    requires_attachment: row.requires_attachment === true,
    coverage_mode: row.coverage_mode || 'manual',
    is_active: row.is_active !== false,
    sort_order: Number(row.sort_order || 0),
    is_system: row.is_system === true,
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
  };
}

async function getLocatorTypeByCode(client, code, { activeOnly = false } = {}) {
  const result = await client.query(
    `SELECT *
     FROM locator_request_types
     WHERE code = $1::text
       AND ($2::boolean = false OR is_active = true)
     LIMIT 1`,
    [code, activeOnly]
  );
  return result.rows[0] || null;
}

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
  limits: { fileSize: MAX_LOCATOR_ATTACHMENT_SIZE },
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
    const message = err.code === 'LIMIT_FILE_SIZE'
      ? 'Attachment must be 10MB or smaller.'
      : err.message || 'Invalid attachment.';
    return res.status(400).json({ error: message });
  });
}

function canModifyAttachment(status) {
  return [
    'pending',
    'pending_department_head',
    'pending_hr',
    'rejected_by_department_head',
    'rejected_by_hr',
  ].includes(status);
}

function parseDateOnly(value) {
  const raw = (value || '').toString().trim();
  const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  const utcDay = parsed.getUTCDay();
  return {
    dateStr: raw,
    isoWeekday: utcDay === 0 ? 7 : utcDay,
  };
}

function toDateOnlyString(value) {
  if (!value) return null;
  if (typeof value === 'string') {
    const raw = value.trim();
    if (!raw) return null;
    const match = raw.match(/^(\d{4}-\d{2}-\d{2})/);
    return match ? match[1] : null;
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    const y = value.getFullYear().toString().padStart(4, '0');
    const m = String(value.getMonth() + 1).padStart(2, '0');
    const d = String(value.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return null;
}

function normalizeWorkingDays(value) {
  if (!Array.isArray(value)) return DEFAULT_WORKING_DAYS;
  const days = value
    .map((day) => Number(day))
    .filter((day) => Number.isInteger(day) && day >= 1 && day <= 7);
  const unique = [...new Set(days)].sort((a, b) => a - b);
  return unique.length > 0 ? unique : DEFAULT_WORKING_DAYS;
}

async function validateLocatorSlipWorkingDay(client, employeeId, dateInfo) {
  const result = await client.query(
    `SELECT a.id,
            a.shift_id,
            s.name AS shift_name,
            s.working_days
     FROM assignments a
     LEFT JOIN shifts s ON s.id = a.shift_id
     WHERE a.employee_id = $1::uuid
       AND (a.is_active IS NULL OR a.is_active = true)
       AND a.effective_from <= $2::date
       AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
     ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
     LIMIT 1`,
    [employeeId, dateInfo.dateStr]
  );
  const assignment = result.rows[0];
  if (!assignment || !assignment.shift_id || !assignment.shift_name) {
    return {
      ok: false,
      error: 'You cannot file a locator request for this date because you have no active shift assignment.',
    };
  }

  const workingDays = normalizeWorkingDays(assignment.working_days);
  if (!workingDays.includes(dateInfo.isoWeekday)) {
    const weekdayName = WEEKDAY_NAMES[dateInfo.isoWeekday - 1] || 'that day';
    return {
      ok: false,
      error: `You cannot file a locator request for ${weekdayName} because it is not included in your assigned shift working days.`,
    };
  }

  return { ok: true };
}

pool
  .query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`)
  .then(() =>
    pool.query(`
      CREATE TABLE IF NOT EXISTS locator_request_types (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        code TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL,
        short_label TEXT NOT NULL,
        location_label TEXT NOT NULL DEFAULT 'Office / Destination',
        location_hint TEXT NOT NULL DEFAULT 'Enter office or destination',
        dtr_slot_label TEXT NOT NULL DEFAULT 'On Field',
        dtr_print_label TEXT NOT NULL DEFAULT 'ON FIELD',
        requires_attachment BOOLEAN NOT NULL DEFAULT false,
        coverage_mode TEXT NOT NULL DEFAULT 'manual'
          CONSTRAINT locator_request_types_coverage_mode_check
          CHECK (coverage_mode IN ('manual', 'wfh')),
        is_active BOOLEAN NOT NULL DEFAULT true,
        is_system BOOLEAN NOT NULL DEFAULT false,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );

      CREATE TABLE IF NOT EXISTS locator_slips (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
        slip_date DATE NOT NULL,
        am_in BOOLEAN NOT NULL DEFAULT false,
        am_out BOOLEAN NOT NULL DEFAULT false,
        pm_in BOOLEAN NOT NULL DEFAULT false,
        pm_out BOOLEAN NOT NULL DEFAULT false,
        request_type TEXT NOT NULL DEFAULT 'locator',
        office TEXT NOT NULL,
        reason TEXT NOT NULL,
        attachment_name TEXT,
        attachment_path TEXT,
        attachment_mime_type TEXT,
        attachment_uploaded_at TIMESTAMPTZ,
        status TEXT NOT NULL DEFAULT 'pending_department_head',
        dept_head_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
        dept_head_reviewed_at TIMESTAMPTZ,
        dept_head_remarks TEXT,
        hr_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
        hr_reviewed_at TIMESTAMPTZ,
        hr_remarks TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );

      CREATE INDEX IF NOT EXISTS idx_locator_slips_employee
        ON locator_slips(employee_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_status
        ON locator_slips(status, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_department
        ON locator_slips(department_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_date
        ON locator_slips(slip_date DESC);

      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type TEXT NOT NULL DEFAULT 'locator';
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS locator_slips_request_type_check;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS attachment_name TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS attachment_path TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS attachment_mime_type TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS attachment_uploaded_at TIMESTAMPTZ;
      CREATE INDEX IF NOT EXISTS idx_locator_request_types_active
        ON locator_request_types(is_active, sort_order, label);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_request_type
        ON locator_slips(request_type);
    `)
  )
  .then(async () => {
    for (const type of DEFAULT_LOCATOR_TYPES) {
      await pool.query(
        `INSERT INTO locator_request_types (
           code, label, short_label, location_label, location_hint,
           dtr_slot_label, dtr_print_label, requires_attachment,
           coverage_mode, is_active, is_system, sort_order
         ) VALUES (
           $1::text, $2::text, $3::text, $4::text, $5::text,
           $6::text, $7::text, $8::boolean, $9::text, true, true, $10::integer
         )
         ON CONFLICT (code) DO UPDATE SET
           is_system = true,
           updated_at = now()`,
        [
          type.code,
          type.label,
          type.short_label,
          type.location_label,
          type.location_hint,
          type.dtr_slot_label,
          type.dtr_print_label,
          type.requires_attachment,
          type.coverage_mode,
          type.sort_order,
        ]
      );
    }
  })
  .catch((err) =>
    console.error('[locator] failed to ensure locator_slips table', err)
  );

function mapLocatorRow(row) {
  const requestType = normalizeRequestType(row.request_type) || 'locator';
  return {
    id: row.id,
    employee_id: row.employee_id,
    employee_name: row.employee_name || null,
    department_id: row.department_id || null,
    department_name: row.department_name || null,
    slip_date: toDateOnlyString(row.slip_date_text || row.slip_date),
    am_in: row.am_in === true,
    am_out: row.am_out === true,
    pm_in: row.pm_in === true,
    pm_out: row.pm_out === true,
    request_type: requestType,
    request_type_label: row.request_type_label || null,
    request_type_short_label: row.request_type_short_label || null,
    request_type_location_label: row.request_type_location_label || null,
    request_type_location_hint: row.request_type_location_hint || null,
    request_type_dtr_slot_label: row.request_type_dtr_slot_label || null,
    request_type_dtr_print_label: row.request_type_dtr_print_label || null,
    request_type_requires_attachment: row.request_type_requires_attachment === true,
    request_type_coverage_mode: row.request_type_coverage_mode || null,
    office: row.office || '',
    reason: row.reason || '',
    attachment_name: row.attachment_name || null,
    attachment_path: row.attachment_path || null,
    attachment_mime_type: row.attachment_mime_type || null,
    attachment_uploaded_at: row.attachment_uploaded_at || null,
    status: row.status,
    dept_head_reviewer_id: row.dept_head_reviewer_id || null,
    dept_head_reviewer_name: row.dept_head_reviewer_name || null,
    dept_head_reviewed_at: row.dept_head_reviewed_at || null,
    dept_head_remarks: row.dept_head_remarks || null,
    hr_reviewer_id: row.hr_reviewer_id || null,
    hr_reviewer_name: row.hr_reviewer_name || null,
    hr_reviewed_at: row.hr_reviewed_at || null,
    hr_remarks: row.hr_remarks || null,
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
  };
}

function isValidStatus(status) {
  return [
    'pending',
    'pending_department_head',
    'pending_hr',
    'approved',
    'rejected_by_department_head',
    'rejected_by_hr',
    'cancelled',
  ].includes(status);
}

// GET /api/locator-slips/department-head/check
router.get('/department-head/check', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const client = await pool.connect();
  try {
    const result = await isDepartmentHead(client, userId);
    res.json(result);
  } catch (err) {
    console.error('[locator GET /department-head/check]', err);
    res.status(500).json({ error: 'Failed to check department head status' });
  } finally {
    client.release();
  }
});

// GET /api/locator-slips/types — active types for forms, or all for admin management.
router.get('/types', protect, async (req, res) => {
  try {
    const includeInactive =
      req.query?.include_inactive === 'true' ||
      req.query?.includeInactive === 'true' ||
      req.query?.all === 'true';
    const rows = await pool.query(
      `SELECT *
       FROM locator_request_types
       WHERE ($1::boolean = true OR is_active = true)
       ORDER BY sort_order ASC, label ASC`,
      [includeInactive]
    );
    res.json(rows.rows.map(mapLocatorTypeRow));
  } catch (err) {
    console.error('[locator GET /types]', err);
    res.status(500).json({ error: 'Failed to fetch locator request types' });
  }
});

// POST /api/locator-slips/types — admin/HR creates a configurable locator type.
router.post('/types', protect, requireAdminOrHr, async (req, res) => {
  try {
    const payload = locatorTypePayloadFromBody(req.body || {});
    const inserted = await pool.query(
      `INSERT INTO locator_request_types (
         code, label, short_label, location_label, location_hint,
         dtr_slot_label, dtr_print_label, requires_attachment,
         coverage_mode, is_active, is_system, sort_order
       ) VALUES (
         $1::text, $2::text, $3::text, $4::text, $5::text,
         $6::text, $7::text, $8::boolean, $9::text, $10::boolean, false, $11::integer
       )
       RETURNING *`,
      [
        payload.code,
        payload.label,
        payload.short_label,
        payload.location_label,
        payload.location_hint,
        payload.dtr_slot_label,
        payload.dtr_print_label,
        payload.requires_attachment,
        payload.coverage_mode,
        payload.is_active,
        payload.sort_order,
      ]
    );
    res.status(201).json(mapLocatorTypeRow(inserted.rows[0]));
  } catch (err) {
    const message = err.code === '23505' ? 'A locator type with that code already exists.' : err.message;
    res.status(400).json({ error: message || 'Failed to create locator type' });
  }
});

// PUT /api/locator-slips/types/:id — admin/HR updates labels and rules.
router.put('/types/:id', protect, requireAdminOrHr, async (req, res) => {
  try {
    const existingQ = await pool.query(
      'SELECT * FROM locator_request_types WHERE id = $1::uuid',
      [req.params.id]
    );
    const existing = existingQ.rows[0];
    if (!existing) return res.status(404).json({ error: 'Locator type not found' });
    const payload = locatorTypePayloadFromBody(req.body || {}, existing);
    const updated = await pool.query(
      `UPDATE locator_request_types
       SET label = $1,
           short_label = $2,
           location_label = $3,
           location_hint = $4,
           dtr_slot_label = $5,
           dtr_print_label = $6,
           requires_attachment = $7,
           coverage_mode = $8,
           is_active = $9,
           sort_order = $10,
           updated_at = now()
       WHERE id = $11::uuid
       RETURNING *`,
      [
        payload.label,
        payload.short_label,
        payload.location_label,
        payload.location_hint,
        payload.dtr_slot_label,
        payload.dtr_print_label,
        payload.requires_attachment,
        payload.coverage_mode,
        payload.is_active,
        payload.sort_order,
        req.params.id,
      ]
    );
    res.json(mapLocatorTypeRow(updated.rows[0]));
  } catch (err) {
    res.status(400).json({ error: err.message || 'Failed to update locator type' });
  }
});

// DELETE /api/locator-slips/types/:id — delete unused custom type, otherwise deactivate it.
router.delete('/types/:id', protect, requireAdminOrHr, async (req, res) => {
  try {
    const existingQ = await pool.query(
      'SELECT * FROM locator_request_types WHERE id = $1::uuid',
      [req.params.id]
    );
    const existing = existingQ.rows[0];
    if (!existing) return res.status(404).json({ error: 'Locator type not found' });
    const usedQ = await pool.query(
      'SELECT 1 FROM locator_slips WHERE request_type = $1::text LIMIT 1',
      [existing.code]
    );
    if (usedQ.rows.length > 0 || existing.is_system === true) {
      const updated = await pool.query(
        `UPDATE locator_request_types
         SET is_active = false, updated_at = now()
         WHERE id = $1::uuid
         RETURNING *`,
        [req.params.id]
      );
      return res.json({ deleted: false, item: mapLocatorTypeRow(updated.rows[0]) });
    }
    await pool.query('DELETE FROM locator_request_types WHERE id = $1::uuid', [req.params.id]);
    res.json({ deleted: true });
  } catch (err) {
    res.status(400).json({ error: err.message || 'Failed to delete locator type' });
  }
});

// GET /api/locator-slips/my
router.get('/my', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const status = (req.query?.status || '').toString().trim() || null;
    if (status && !isValidStatus(status)) {
      return res.status(400).json({ error: 'Invalid status filter' });
    }
    const rows = await pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.employee_id = $1::uuid
         AND ($2::text IS NULL OR ls.status = $2::text)
       ORDER BY ls.updated_at DESC, ls.created_at DESC
       LIMIT 500`,
      [userId, status]
    );
    res.json(rows.rows.map(mapLocatorRow));
  } catch (err) {
    console.error('[locator GET /my]', err);
    res.status(500).json({ error: 'Failed to fetch locator slips' });
  }
});

// POST /api/locator-slips/submit
router.post('/submit', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });

  const slipDate = (req.body?.slip_date || '').toString().trim();
  const office = (req.body?.office || '').toString().trim();
  const reason = (req.body?.reason || '').toString().trim();
  const requestType = normalizeRequestType(req.body?.request_type);
  const amIn = req.body?.am_in === true;
  const amOut = req.body?.am_out === true;
  const pmIn = req.body?.pm_in === true;
  const pmOut = req.body?.pm_out === true;

  if (!slipDate) return res.status(400).json({ error: 'slip_date is required' });
  const slipDateInfo = parseDateOnly(slipDate);
  if (!slipDateInfo) return res.status(400).json({ error: 'Invalid slip_date' });
  if (!requestType) return res.status(400).json({ error: 'Invalid request_type' });
  if (!office) return res.status(400).json({ error: 'office is required' });
  if (!reason) return res.status(400).json({ error: 'reason is required' });
  if (!amIn && !amOut && !pmIn && !pmOut) {
    return res.status(400).json({ error: 'At least one AM/PM IN/OUT marker is required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const deptInfo = await getDepartmentHeadForEmployee(client, userId);
    const ownDept = await getEmployeeDepartment(client, userId);
    const submitStatus = deptInfo ? 'pending_department_head' : 'pending_hr';
    const departmentId = deptInfo?.departmentId || ownDept?.departmentId || null;
    const workingDayCheck = await validateLocatorSlipWorkingDay(client, userId, slipDateInfo);
    if (!workingDayCheck.ok) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: workingDayCheck.error });
    }
    const locatorType = await getLocatorTypeByCode(client, requestType, { activeOnly: true });
    if (!locatorType) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Invalid request_type' });
    }
    if (locatorType.requires_attachment === true) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Attachment is required for this locator type.' });
    }

    const inserted = await client.query(
      `INSERT INTO locator_slips (
        employee_id, department_id, slip_date, am_in, am_out, pm_in, pm_out,
        request_type, office, reason, status, created_at, updated_at
      ) VALUES (
        $1::uuid, $2::uuid, $3::date, $4::boolean, $5::boolean, $6::boolean, $7::boolean,
        $8::text, $9::text, $10::text, $11::text, now(), now()
      )
      RETURNING *`,
      [
        userId,
        departmentId,
        slipDate,
        amIn,
        amOut,
        pmIn,
        pmOut,
        requestType,
        office,
        reason,
        submitStatus,
      ]
    );
    await client.query('COMMIT');

    const out = await pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
      [inserted.rows[0].id]
    );

    const nameQ = await pool.query('SELECT full_name FROM users WHERE id = $1::uuid', [userId]);
    const employeeName = nameQ.rows[0]?.full_name || 'Employee';
    notifySafe(() =>
      locatorNotifications.notifyAfterSubmit(pool, {
        slipId: inserted.rows[0].id,
        status: submitStatus,
        employeeUserId: userId,
        employeeName,
        slipDate,
        amIn,
        amOut,
        pmIn,
        pmOut,
        requestType,
        departmentHeadUserId: deptInfo?.departmentHeadUserId || null,
      })
    );

    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('submitted', mapped);
    res.status(201).json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator POST /submit]', err);
    res.status(500).json({ error: 'Failed to submit locator slip' });
  } finally {
    client.release();
  }
});

// POST /api/locator-slips/submit-with-attachment
router.post('/submit-with-attachment', protect, uploadLocatorAttachmentMw, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  if (!req.file) return res.status(400).json({ error: 'Attachment is required.' });

  const slipDate = (req.body?.slip_date || '').toString().trim();
  const office = (req.body?.office || '').toString().trim();
  const reason = (req.body?.reason || '').toString().trim();
  const requestType = normalizeRequestType(req.body?.request_type);
  const amIn = boolField(req.body?.am_in);
  const amOut = boolField(req.body?.am_out);
  const pmIn = boolField(req.body?.pm_in);
  const pmOut = boolField(req.body?.pm_out);
  const relPath = `${LOCATOR_ATTACHMENT_SUBDIR}/${req.file.filename}`;

  const cleanup = () => {
    try {
      fs.unlinkSync(path.join(UPLOAD_DIR, relPath));
    } catch (_) {}
  };

  if (!slipDate) {
    cleanup();
    return res.status(400).json({ error: 'slip_date is required' });
  }
  const slipDateInfo = parseDateOnly(slipDate);
  if (!slipDateInfo) {
    cleanup();
    return res.status(400).json({ error: 'Invalid slip_date' });
  }
  if (!requestType) {
    cleanup();
    return res.status(400).json({ error: 'Invalid request_type' });
  }
  if (!office) {
    cleanup();
    return res.status(400).json({ error: 'office is required' });
  }
  if (!reason) {
    cleanup();
    return res.status(400).json({ error: 'reason is required' });
  }
  if (!amIn && !amOut && !pmIn && !pmOut) {
    cleanup();
    return res.status(400).json({ error: 'At least one segment must be selected' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const deptInfo = await getDepartmentHeadForEmployee(client, userId);
    const ownDept = await getEmployeeDepartment(client, userId);
    const departmentId = deptInfo?.departmentId || ownDept?.departmentId || null;
    const workingDayCheck = await validateLocatorSlipWorkingDay(client, userId, slipDateInfo);
    if (!workingDayCheck.ok) {
      await client.query('ROLLBACK');
      cleanup();
      return res.status(400).json({ error: workingDayCheck.error });
    }
    const locatorType = await getLocatorTypeByCode(client, requestType, { activeOnly: true });
    if (!locatorType) {
      await client.query('ROLLBACK');
      cleanup();
      return res.status(400).json({ error: 'Invalid request_type' });
    }

    const inserted = await client.query(
      `INSERT INTO locator_slips (
        employee_id, department_id, slip_date, am_in, am_out, pm_in, pm_out,
        request_type, office, reason, attachment_name, attachment_path,
        attachment_mime_type, attachment_uploaded_at, status, created_at, updated_at
      ) VALUES (
        $1::uuid, $2::uuid, $3::date, $4::boolean, $5::boolean, $6::boolean, $7::boolean,
        $8::text, $9::text, $10::text, $11::text, $12::text, $13::text, now(), $14::text, now(), now()
      )
      RETURNING *`,
      [
        userId,
        departmentId,
        slipDate,
        amIn,
        amOut,
        pmIn,
        pmOut,
        requestType,
        office,
        reason,
        req.file.originalname || 'attachment',
        relPath,
        req.file.mimetype || null,
        deptInfo ? 'pending_department_head' : 'pending_hr',
      ]
    );

    await client.query('COMMIT');
    const out = await pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
      [inserted.rows[0].id]
    );

    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('submitted', mapped);
    res.status(201).json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    cleanup();
    console.error('[locator POST /submit-with-attachment]', err);
    res.status(500).json({ error: 'Failed to submit locator slip with attachment' });
  } finally {
    client.release();
  }
});

// PATCH /api/locator-slips/:id/cancel
router.patch('/:id/cancel', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT id, status
       FROM locator_slips
       WHERE id = $1::uuid AND employee_id = $2::uuid
       FOR UPDATE`,
      [id, userId]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    const status = current.rows[0].status;
    if (!['pending', 'pending_department_head', 'pending_hr'].includes(status)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: `Cannot cancel locator slip with status '${status}'` });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'cancelled', updated_at = now()
       WHERE id = $1::uuid`,
      [id]
    );
    await client.query('COMMIT');
    const out = await pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('cancelled', mapped, { previousStatus: status });
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/cancel]', err);
    res.status(500).json({ error: 'Failed to cancel locator slip' });
  } finally {
    client.release();
  }
});

// POST /api/locator-slips/:id/attachment - upload/replace attachment.
router.post('/:id/attachment', protect, uploadLocatorAttachmentMw, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  if (!req.file) return res.status(400).json({ error: 'Attachment is required.' });
  const isPrivileged = req.user?.role === 'admin' || req.user?.role === 'hr';
  try {
    const current = await pool.query(
      `SELECT id, status, employee_id, attachment_path
       FROM locator_slips
       WHERE id = $1::uuid AND ($2::boolean = true OR employee_id = $3::uuid)`,
      [req.params.id, isPrivileged, userId]
    );
    const row = current.rows[0];
    if (!row) return res.status(404).json({ error: 'Locator slip not found' });
    if (!canModifyAttachment(row.status)) {
      return res.status(400).json({ error: 'Attachment cannot be changed for this request status.' });
    }
    const relPath = `${LOCATOR_ATTACHMENT_SUBDIR}/${req.file.filename}`;
    if (row.attachment_path) {
      try {
        fs.unlinkSync(path.join(UPLOAD_DIR, row.attachment_path));
      } catch (_) {}
    }
    await pool.query(
      `UPDATE locator_slips
       SET attachment_name = $1,
           attachment_path = $2,
           attachment_mime_type = $3,
           attachment_uploaded_at = now(),
           updated_at = now()
       WHERE id = $4::uuid`,
      [req.file.originalname || 'attachment', relPath, req.file.mimetype || null, req.params.id]
    );
    res.json({ attachment_name: req.file.originalname || 'attachment', attachment_path: relPath });
  } catch (err) {
    try {
      fs.unlinkSync(path.join(locatorAttachmentDir, req.file.filename));
    } catch (_) {}
    console.error('[locator POST /:id/attachment]', err);
    res.status(500).json({ error: 'Failed to upload attachment' });
  }
});

// DELETE /api/locator-slips/:id/attachment
router.delete('/:id/attachment', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const isPrivileged = req.user?.role === 'admin' || req.user?.role === 'hr';
  try {
    const current = await pool.query(
      `SELECT id, status, employee_id, attachment_path
       FROM locator_slips
       WHERE id = $1::uuid AND ($2::boolean = true OR employee_id = $3::uuid)`,
      [req.params.id, isPrivileged, userId]
    );
    const row = current.rows[0];
    if (!row) return res.status(404).json({ error: 'Locator slip not found' });
    if (!canModifyAttachment(row.status)) {
      return res.status(400).json({ error: 'Attachment cannot be changed for this request status.' });
    }
    if (row.attachment_path) {
      try {
        fs.unlinkSync(path.join(UPLOAD_DIR, row.attachment_path));
      } catch (_) {}
    }
    await pool.query(
      `UPDATE locator_slips
       SET attachment_name = NULL,
           attachment_path = NULL,
           attachment_mime_type = NULL,
           attachment_uploaded_at = NULL,
           updated_at = now()
       WHERE id = $1::uuid`,
      [req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    console.error('[locator DELETE /:id/attachment]', err);
    res.status(500).json({ error: 'Failed to remove attachment' });
  }
});

// GET /api/locator-slips/:id/attachment
router.get('/:id/attachment', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const isPrivileged = req.user?.role === 'admin' || req.user?.role === 'hr';
  try {
    const current = await pool.query(
      `SELECT employee_id, attachment_name, attachment_path, attachment_mime_type
       FROM locator_slips
       WHERE id = $1::uuid AND ($2::boolean = true OR employee_id = $3::uuid)`,
      [req.params.id, isPrivileged, userId]
    );
    const row = current.rows[0];
    if (!row) return res.status(404).json({ error: 'Locator slip not found' });
    if (!row.attachment_path) return res.status(404).json({ error: 'No attachment for this request' });
    const filePath = path.join(UPLOAD_DIR, row.attachment_path);
    if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'Attachment file not found' });
    const filename = (row.attachment_name || 'attachment').replace(/[^\w.\- ()]/g, '_').slice(0, 180);
    if (row.attachment_mime_type) res.setHeader('Content-Type', row.attachment_mime_type);
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.sendFile(filePath);
  } catch (err) {
    console.error('[locator GET /:id/attachment]', err);
    res.status(500).json({ error: 'Failed to fetch attachment' });
  }
});

// GET /api/locator-slips/department-head
router.get('/department-head', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const client = await pool.connect();
  try {
    const deptInfo = await isDepartmentHead(client, userId);
    if (!deptInfo.isDeptHead || !deptInfo.departmentId) {
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const status = (req.query?.status || '').toString().trim() || null;
    if (status && !isValidStatus(status)) {
      return res.status(400).json({ error: 'Invalid status filter' });
    }
    const rows = await client.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.department_id = $1::uuid
         AND (
           ls.status = 'pending_department_head'
           OR ls.dept_head_reviewer_id = $2::uuid
         )
         AND ($3::text IS NULL OR ls.status = $3::text)
       ORDER BY ls.updated_at DESC, ls.created_at DESC
       LIMIT 500`,
      [deptInfo.departmentId, userId, status]
    );
    res.json(rows.rows.map(mapLocatorRow));
  } catch (err) {
    console.error('[locator GET /department-head]', err);
    res.status(500).json({ error: 'Failed to fetch department-head locator slips' });
  } finally {
    client.release();
  }
});

// PATCH /api/locator-slips/:id/department-head-approve
router.patch('/:id/department-head-approve', protect, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || '').toString().trim() || null;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const deptInfo = await isDepartmentHead(client, reviewerId);
    if (!deptInfo.isDeptHead || !deptInfo.departmentId) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const current = await client.query(
      `SELECT id, status, employee_id, slip_date::text AS slip_date, request_type
       FROM locator_slips
       WHERE id = $1::uuid
         AND department_id = $2::uuid
       FOR UPDATE`,
      [id, deptInfo.departmentId]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found or not in your department' });
    }
    if (current.rows[0].status !== 'pending_department_head') {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot approve locator slip with status '${current.rows[0].status}'`,
      });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'pending_hr',
           dept_head_reviewer_id = $2::uuid,
           dept_head_reviewed_at = now(),
           dept_head_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, reviewerId, remarks]
    );
    await client.query('COMMIT');

    notifySafe(() =>
      locatorNotifications.notifyDepartmentHeadApprovedForEmployee(pool, {
        slipId: id,
        employeeUserId: current.rows[0].employee_id,
        slipDate: current.rows[0].slip_date,
        requestType: current.rows[0].request_type,
        metadata: { reviewer_remarks: remarks },
      })
    );
    const out = await pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    notifySafe(() =>
      locatorNotifications.notifyDepartmentHeadApprovedForHr(pool, {
        slipId: id,
        employeeName: mapped.employee_name,
        slipDate: mapped.slip_date,
        requestType: mapped.request_type,
      })
    );
    broadcastLocatorUpdated('department_head_approved', mapped);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/department-head-approve]', err);
    res.status(500).json({ error: 'Failed to approve locator slip (department head)' });
  } finally {
    client.release();
  }
});

// PATCH /api/locator-slips/:id/department-head-reject
router.patch('/:id/department-head-reject', protect, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const deptInfo = await isDepartmentHead(client, reviewerId);
    if (!deptInfo.isDeptHead || !deptInfo.departmentId) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const current = await client.query(
      `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
         AND department_id = $2::uuid
       FOR UPDATE`,
      [id, deptInfo.departmentId]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found or not in your department' });
    }
    if (current.rows[0].status !== 'pending_department_head') {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot reject locator slip with status '${current.rows[0].status}'`,
      });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'rejected_by_department_head',
           dept_head_reviewer_id = $2::uuid,
           dept_head_reviewed_at = now(),
           dept_head_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, reviewerId, remarks]
    );
    await client.query('COMMIT');
    notifySafe(() =>
      locatorNotifications.notifyEmployee(pool, {
        employeeUserId: current.rows[0].employee_id,
        slipId: id,
        type: 'locator_rejected_department_head',
        title: 'Locator request not approved by department head',
        body: remarks
          ? `Your locator request was not approved. ${remarks}`
          : 'Your locator request was not approved by your department head.',
        metadata: { reviewer_remarks: remarks },
      })
    );
    const out = await pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('department_head_rejected', mapped);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/department-head-reject]', err);
    res.status(500).json({ error: 'Failed to reject locator slip (department head)' });
  } finally {
    client.release();
  }
});

// GET /api/locator-slips/admin
router.get('/admin', protect, requireAdminOrHr, async (req, res) => {
  try {
    const status = (req.query?.status || '').toString().trim() || null;
    const requestTypeRaw = (req.query?.request_type || '').toString().trim();
    const requestType = requestTypeRaw ? normalizeRequestType(requestTypeRaw) : null;
    if (status && !isValidStatus(status)) {
      return res.status(400).json({ error: 'Invalid status filter' });
    }
    if (requestTypeRaw && !requestType) {
      return res.status(400).json({ error: 'Invalid request_type filter' });
    }
    const rows = await pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ($1::text IS NULL OR ls.status = $1::text)
         AND ($2::text IS NULL OR ls.request_type = $2::text)
       ORDER BY ls.updated_at DESC, ls.created_at DESC
       LIMIT 500`,
      [status, requestType]
    );
    res.json(rows.rows.map(mapLocatorRow));
  } catch (err) {
    console.error('[locator GET /admin]', err);
    res.status(500).json({ error: 'Failed to fetch locator slips (admin)' });
  }
});

// PATCH /api/locator-slips/:id/approve
router.patch('/:id/approve', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.hr_remarks || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
       FOR UPDATE`,
      [id]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    if (!['pending_hr', 'pending'].includes(current.rows[0].status)) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot approve locator slip with status '${current.rows[0].status}'`,
      });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'approved',
           hr_reviewer_id = $2::uuid,
           hr_reviewed_at = now(),
           hr_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, reviewerId, remarks]
    );
    await client.query('COMMIT');

    notifySafe(() =>
      locatorNotifications.notifyEmployee(pool, {
        employeeUserId: current.rows[0].employee_id,
        slipId: id,
        type: 'locator_approved_hr',
        title: 'Locator request approved',
        body: remarks
          ? `Your locator request was approved. ${remarks}`
          : 'Your locator request was approved by HR.',
        metadata: { reviewer_remarks: remarks },
      })
    );

    const out = await pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('approved', mapped);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/approve]', err);
    res.status(500).json({ error: 'Failed to approve locator slip' });
  } finally {
    client.release();
  }
});

// PATCH /api/locator-slips/:id/reject
router.patch('/:id/reject', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || req.body?.hr_remarks || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
       FOR UPDATE`,
      [id]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    if (!['pending_hr', 'pending'].includes(current.rows[0].status)) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot reject locator slip with status '${current.rows[0].status}'`,
      });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'rejected_by_hr',
           hr_reviewer_id = $2::uuid,
           hr_reviewed_at = now(),
           hr_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, reviewerId, remarks]
    );
    await client.query('COMMIT');

    notifySafe(() =>
      locatorNotifications.notifyEmployee(pool, {
        employeeUserId: current.rows[0].employee_id,
        slipId: id,
        type: 'locator_rejected_hr',
        title: 'Locator request not approved',
        body: remarks
          ? `HR did not approve this locator request. ${remarks}`
          : 'HR did not approve this locator request.',
        metadata: { reviewer_remarks: remarks },
      })
    );

    const out = await pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('rejected', mapped);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/reject]', err);
    res.status(500).json({ error: 'Failed to reject locator slip' });
  } finally {
    client.release();
  }
});

module.exports = router;
