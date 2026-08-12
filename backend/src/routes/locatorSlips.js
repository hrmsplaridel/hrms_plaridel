const express = require('express');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrHr } = require('../middleware/rbac');
const {
  findDepartmentHeadUserId,
  getDepartmentReviewSnapshotForDate,
  isDepartmentHead,
} = require('../services/departmentHeadService');
const locatorNotifications = require('../services/locatorNotifications');
const {
  recordLocatorAttachmentAccess,
  resolveLocatorAttachmentAccess,
} = require('../services/locatorAttachmentAccess');
const { broadcastAppEvent } = require('../websockets/appEvents');
const {
  canModifyLocatorAttachment,
  locatorAttachmentRequiredError,
  parseLocatorDateOnly,
  validateLocatorAttachmentForReview,
  validateLocatorRequiredFields,
  validateLocatorWorkingDayForEmployee,
} = require('../services/locatorFilingRules');
const {
  findLocatorRequestConflicts,
} = require('../services/locatorConflictPolicy');
const {
  createLocatorSubmissionService,
} = require('../services/locatorSubmissionService');
const {
  evaluateEmployeeLocatorDateWindow,
  normalizeCorrectionReason,
} = require('../services/locatorDatePolicy');
const {
  evaluateLocatorRevocation,
} = require('../services/locatorRevocationPolicy');
const {
  parseLocatorAdminFilters,
} = require('../services/locatorAdminFilters');
const {
  captureLocatorTypeSnapshot,
  resolveLocatorTypeMetadata,
} = require('../services/locatorTypeSnapshot');

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

function locatorConflictPayload(result) {
  return {
    error: result.message || 'Locator request conflicts with an existing record.',
    code: result.code || 'locator_conflict',
    conflicts: result.conflicts || {},
  };
}

function removeLocatorAttachmentFile(relativePath) {
  if (!locatorAttachmentFileExists(relativePath)) return;
  try {
    fs.unlinkSync(path.resolve(UPLOAD_DIR, relativePath));
  } catch (_) {}
}

function locatorReviewAttachmentError(row) {
  const requiresAttachment = resolveLocatorTypeMetadata(
    row
  ).requiresAttachment;
  return validateLocatorAttachmentForReview({
    locatorType: { requires_attachment: requiresAttachment },
    attachmentPath: row.attachment_path,
    attachmentFileExists: locatorAttachmentFileExists(row.attachment_path),
  });
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
        assigned_department_head_id UUID REFERENCES users(id) ON DELETE SET NULL,
        slip_date DATE NOT NULL,
        am_in BOOLEAN NOT NULL DEFAULT false,
        am_out BOOLEAN NOT NULL DEFAULT false,
        pm_in BOOLEAN NOT NULL DEFAULT false,
        pm_out BOOLEAN NOT NULL DEFAULT false,
        request_type TEXT NOT NULL DEFAULT 'locator',
        request_type_label_snapshot TEXT,
        request_type_short_label_snapshot TEXT,
        request_type_location_label_snapshot TEXT,
        request_type_location_hint_snapshot TEXT,
        request_type_dtr_slot_label_snapshot TEXT,
        request_type_dtr_print_label_snapshot TEXT,
        request_type_requires_attachment_snapshot BOOLEAN,
        request_type_coverage_mode_snapshot TEXT
          CONSTRAINT chk_locator_type_coverage_snapshot
          CHECK (
            request_type_coverage_mode_snapshot IS NULL
            OR request_type_coverage_mode_snapshot IN ('manual', 'wfh')
          ),
        request_type_snapshot_at TIMESTAMPTZ,
        office TEXT NOT NULL,
        reason TEXT NOT NULL,
        attachment_name TEXT,
        attachment_path TEXT,
        attachment_mime_type TEXT,
        attachment_uploaded_at TIMESTAMPTZ,
        status TEXT NOT NULL DEFAULT 'pending_department_head'
          CONSTRAINT locator_slips_status_check
          CHECK (status IN (
            'pending',
            'pending_department_head',
            'pending_hr',
            'returned_for_correction',
            'approved',
            'revoked',
            'rejected_by_department_head',
            'rejected_by_hr',
            'cancelled'
          )),
        dept_head_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
        dept_head_reviewed_at TIMESTAMPTZ,
        dept_head_remarks TEXT,
        hr_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
        hr_reviewed_at TIMESTAMPTZ,
        hr_remarks TEXT,
        is_retroactive_correction BOOLEAN NOT NULL DEFAULT false,
        retroactive_correction_reason TEXT,
        retroactive_corrected_by UUID REFERENCES users(id) ON DELETE SET NULL,
        retroactive_corrected_at TIMESTAMPTZ,
        revoked_by UUID REFERENCES users(id) ON DELETE SET NULL,
        revoked_at TIMESTAMPTZ,
        revocation_reason TEXT,
        month_end_reconciliation_required BOOLEAN NOT NULL DEFAULT false,
        month_end_reconciled_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        CONSTRAINT chk_locator_correction_audit CHECK (
          is_retroactive_correction = false
          OR (
            retroactive_correction_reason IS NOT NULL
            AND char_length(btrim(retroactive_correction_reason)) BETWEEN 10 AND 1000
            AND retroactive_corrected_by IS NOT NULL
            AND retroactive_corrected_at IS NOT NULL
          )
        ),
        CONSTRAINT chk_locator_revocation_audit CHECK (
          status <> 'revoked'
          OR (
            revoked_by IS NOT NULL
            AND revoked_at IS NOT NULL
            AND revocation_reason IS NOT NULL
            AND char_length(btrim(revocation_reason)) BETWEEN 10 AND 1000
          )
        )
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
        ADD COLUMN IF NOT EXISTS request_type_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_short_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_location_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_location_hint_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_dtr_slot_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_dtr_print_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_requires_attachment_snapshot BOOLEAN;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_coverage_mode_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_snapshot_at TIMESTAMPTZ;
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS chk_locator_type_coverage_snapshot;
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS locator_slips_request_type_coverage_mode_snapshot_check;
      ALTER TABLE locator_slips
        ADD CONSTRAINT chk_locator_type_coverage_snapshot CHECK (
          request_type_coverage_mode_snapshot IS NULL
          OR request_type_coverage_mode_snapshot IN ('manual', 'wfh')
        );
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
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS assigned_department_head_id UUID
          REFERENCES users(id) ON DELETE SET NULL;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS is_retroactive_correction BOOLEAN NOT NULL DEFAULT false;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS retroactive_correction_reason TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS retroactive_corrected_by UUID
          REFERENCES users(id) ON DELETE SET NULL;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS retroactive_corrected_at TIMESTAMPTZ;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS revoked_by UUID
          REFERENCES users(id) ON DELETE SET NULL;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS revocation_reason TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS month_end_reconciliation_required BOOLEAN NOT NULL DEFAULT false;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS month_end_reconciled_at TIMESTAMPTZ;
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS locator_slips_status_check;
      ALTER TABLE locator_slips
        ADD CONSTRAINT locator_slips_status_check CHECK (status IN (
          'pending', 'pending_department_head', 'pending_hr',
          'returned_for_correction', 'approved', 'revoked',
          'rejected_by_department_head', 'rejected_by_hr', 'cancelled'
        ));
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS chk_locator_revocation_audit;
      ALTER TABLE locator_slips
        ADD CONSTRAINT chk_locator_revocation_audit CHECK (
          status <> 'revoked'
          OR (
            revoked_by IS NOT NULL
            AND revoked_at IS NOT NULL
            AND revocation_reason IS NOT NULL
            AND char_length(btrim(revocation_reason)) BETWEEN 10 AND 1000
          )
        );
      CREATE INDEX IF NOT EXISTS idx_locator_request_types_active
        ON locator_request_types(is_active, sort_order, label);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_request_type
        ON locator_slips(request_type);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_assigned_department_head
        ON locator_slips(assigned_department_head_id, status, updated_at DESC);
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
    await pool.query(
      `UPDATE locator_slips AS slip
       SET request_type_label_snapshot = COALESCE(slip.request_type_label_snapshot, locator_type.label),
           request_type_short_label_snapshot = COALESCE(slip.request_type_short_label_snapshot, locator_type.short_label),
           request_type_location_label_snapshot = COALESCE(slip.request_type_location_label_snapshot, locator_type.location_label),
           request_type_location_hint_snapshot = COALESCE(slip.request_type_location_hint_snapshot, locator_type.location_hint),
           request_type_dtr_slot_label_snapshot = COALESCE(slip.request_type_dtr_slot_label_snapshot, locator_type.dtr_slot_label),
           request_type_dtr_print_label_snapshot = COALESCE(slip.request_type_dtr_print_label_snapshot, locator_type.dtr_print_label),
           request_type_requires_attachment_snapshot = COALESCE(slip.request_type_requires_attachment_snapshot, locator_type.requires_attachment),
           request_type_coverage_mode_snapshot = COALESCE(slip.request_type_coverage_mode_snapshot, locator_type.coverage_mode),
           request_type_snapshot_at = COALESCE(slip.request_type_snapshot_at, now())
       FROM locator_request_types AS locator_type
       WHERE locator_type.code = slip.request_type
         AND (
           slip.request_type_label_snapshot IS NULL
           OR slip.request_type_short_label_snapshot IS NULL
           OR slip.request_type_location_label_snapshot IS NULL
           OR slip.request_type_location_hint_snapshot IS NULL
           OR slip.request_type_dtr_slot_label_snapshot IS NULL
           OR slip.request_type_dtr_print_label_snapshot IS NULL
           OR slip.request_type_requires_attachment_snapshot IS NULL
           OR slip.request_type_coverage_mode_snapshot IS NULL
           OR slip.request_type_snapshot_at IS NULL
         )`
    );
  })
  .catch((err) =>
    console.error('[locator] failed to ensure locator_slips table', err)
  );

function mapLocatorRow(row) {
  const requestType = normalizeRequestType(row.request_type) || 'locator';
  const typeMetadata = resolveLocatorTypeMetadata(row);
  return {
    id: row.id,
    employee_id: row.employee_id,
    employee_name: row.employee_name || null,
    department_id: row.department_id || null,
    department_name: row.department_name || null,
    assigned_department_head_id: row.assigned_department_head_id || null,
    assigned_department_head_name:
      row.assigned_department_head_name || null,
    slip_date: toDateOnlyString(row.slip_date_text || row.slip_date),
    am_in: row.am_in === true,
    am_out: row.am_out === true,
    pm_in: row.pm_in === true,
    pm_out: row.pm_out === true,
    request_type: requestType,
    request_type_label: typeMetadata.label,
    request_type_short_label: typeMetadata.shortLabel,
    request_type_location_label: typeMetadata.locationLabel,
    request_type_location_hint: typeMetadata.locationHint,
    request_type_dtr_slot_label: typeMetadata.dtrSlotLabel,
    request_type_dtr_print_label: typeMetadata.dtrPrintLabel,
    request_type_requires_attachment: typeMetadata.requiresAttachment,
    request_type_coverage_mode: typeMetadata.coverageMode,
    request_type_snapshot_at: typeMetadata.capturedAt,
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
    is_retroactive_correction: row.is_retroactive_correction === true,
    retroactive_correction_reason:
      row.retroactive_correction_reason || null,
    retroactive_corrected_by: row.retroactive_corrected_by || null,
    retroactive_corrector_name: row.retroactive_corrector_name || null,
    retroactive_corrected_at: row.retroactive_corrected_at || null,
    revoked_by: row.revoked_by || null,
    revoked_by_name: row.revoked_by_name || null,
    revoked_at: row.revoked_at || null,
    revocation_reason: row.revocation_reason || null,
    month_end_reconciliation_required:
      row.month_end_reconciliation_required === true,
    month_end_reconciled_at: row.month_end_reconciled_at || null,
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
  };
}

async function fetchLocatorSlipDetails(db, id) {
  const result = await db.query(
    `SELECT ls.*,
            ls.slip_date::text AS slip_date_text,
            u.full_name AS employee_name,
            d.name AS department_name,
            assigned_dh.full_name AS assigned_department_head_name,
            dh.full_name AS dept_head_reviewer_name,
            hr.full_name AS hr_reviewer_name,
            corrector.full_name AS retroactive_corrector_name,
            revoker.full_name AS revoked_by_name,
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
     LEFT JOIN users assigned_dh ON assigned_dh.id = ls.assigned_department_head_id
     LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
     LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
     LEFT JOIN users corrector ON corrector.id = ls.retroactive_corrected_by
     LEFT JOIN users revoker ON revoker.id = ls.revoked_by
     LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
     WHERE ls.id = $1::uuid`,
    [id]
  );
  return result.rows[0] ? mapLocatorRow(result.rows[0]) : null;
}

const locatorSubmissionService = createLocatorSubmissionService({
  dbPool: pool,
  getReviewSnapshot: getDepartmentReviewSnapshotForDate,
  validateWorkingDay: validateLocatorWorkingDayForEmployee,
  getLocatorTypeByCode,
  findConflicts: findLocatorRequestConflicts,
  fetchSlipDetails: fetchLocatorSlipDetails,
  mapInsertedRow: mapLocatorRow,
  notifyAfterSubmit: locatorNotifications.notifyAfterSubmit,
  broadcastSubmitted: (row) => broadcastLocatorUpdated('submitted', row),
});

function isValidStatus(status) {
  return [
    'pending',
    'pending_department_head',
    'pending_hr',
    'returned_for_correction',
    'approved',
    'revoked',
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
    const current = await isDepartmentHead(client, userId);
    const assigned = await client.query(
      `SELECT ls.department_id, d.name AS department_name
       FROM locator_slips ls
       LEFT JOIN departments d ON d.id = ls.department_id
       WHERE ls.assigned_department_head_id = $1::uuid
         AND ls.status = 'pending_department_head'
       ORDER BY ls.updated_at DESC
       LIMIT 1`,
      [userId]
    );
    const assignedDepartmentId = assigned.rows[0]?.department_id || null;
    const assignedDepartmentName = assigned.rows[0]?.department_name || null;
    res.json({
      isDeptHead: current.isDeptHead || Boolean(assignedDepartmentId),
      departmentId: current.departmentId || assignedDepartmentId,
      departmentName: current.departmentName || assignedDepartmentName,
    });
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
              corrector.full_name AS retroactive_corrector_name,
              revoker.full_name AS revoked_by_name,
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
       LEFT JOIN users corrector ON corrector.id = ls.retroactive_corrected_by
       LEFT JOIN users revoker ON revoker.id = ls.revoked_by
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

  try {
    const mapped = await locatorSubmissionService.submit({
      employeeUserId: userId,
      slipDate,
      office,
      reason,
      requestType,
      amIn,
      amOut,
      pmIn,
      pmOut,
    });
    res.status(201).json(mapped);
  } catch (err) {
    if (err?.statusCode && err?.payload) {
      return res.status(err.statusCode).json(err.payload);
    }
    console.error('[locator POST /submit]', err);
    res.status(500).json({ error: 'Failed to submit locator slip' });
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

  try {
    const mapped = await locatorSubmissionService.submit({
      employeeUserId: userId,
      slipDate,
      office,
      reason,
      requestType,
      amIn,
      amOut,
      pmIn,
      pmOut,
      attachment: {
        name: req.file.originalname || 'attachment',
        path: relPath,
        mimeType: req.file.mimetype || null,
      },
    });
    res.status(201).json(mapped);
  } catch (err) {
    cleanup();
    if (err?.statusCode && err?.payload) {
      return res.status(err.statusCode).json(err.payload);
    }
    console.error('[locator POST /submit-with-attachment]', err);
    res.status(500).json({ error: 'Failed to submit locator slip with attachment' });
  }
});

// POST /api/locator-slips/admin/corrections - HR/Admin records a documented
// locator for a past date that cannot use normal employee filing.
router.post(
  '/admin/corrections',
  protect,
  requireAdminOrHr,
  uploadLocatorAttachmentMw,
  async (req, res) => {
    const reviewerId = req.user?.id;
    const employeeId = String(req.body?.employee_id || '').trim();
    const slipDate = String(req.body?.slip_date || '').trim();
    const office = String(req.body?.office || '').trim();
    const reason = String(req.body?.reason || '').trim();
    const requestType = normalizeRequestType(req.body?.request_type);
    const amIn = boolField(req.body?.am_in);
    const amOut = boolField(req.body?.am_out);
    const pmIn = boolField(req.body?.pm_in);
    const pmOut = boolField(req.body?.pm_out);
    const correctionReason = normalizeCorrectionReason(
      req.body?.retroactive_correction_reason
    );
    const relPath = req.file
      ? `${LOCATOR_ATTACHMENT_SUBDIR}/${req.file.filename}`
      : null;
    const cleanup = () => {
      if (relPath) removeLocatorAttachmentFile(relPath);
    };

    if (!reviewerId) {
      cleanup();
      return res.status(401).json({ error: 'Not authenticated' });
    }
    const fields = validateLocatorRequiredFields({
      slipDate,
      requestType,
      office,
      reason,
      slots: { amIn, amOut, pmIn, pmOut },
    });
    if (!employeeId || !fields.valid) {
      cleanup();
      return res.status(400).json({
        error: !employeeId
          ? 'employee_id is required'
          : fields.error,
      });
    }
    if (!correctionReason) {
      cleanup();
      return res.status(400).json({
        error: 'A correction reason between 10 and 1000 characters is required.',
        code: 'locator_correction_reason_required',
      });
    }
    const employeeDateWindow = evaluateEmployeeLocatorDateWindow({ slipDate });
    if (employeeDateWindow.ok) {
      cleanup();
      return res.status(409).json({
        error:
          'Today and future locator dates must use the normal employee filing and approval workflow.',
        code: 'locator_correction_not_needed',
      });
    }
    if (employeeDateWindow.code !== 'locator_past_date_not_allowed') {
      cleanup();
      return res.status(400).json({
        error: employeeDateWindow.error,
        code: employeeDateWindow.code,
      });
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const employee = await client.query(
        `SELECT id, full_name FROM users WHERE id = $1::uuid LIMIT 1`,
        [employeeId]
      );
      if (!employee.rows[0]) {
        await client.query('ROLLBACK');
        cleanup();
        return res.status(404).json({ error: 'Employee not found' });
      }
      const workingDay = await validateLocatorWorkingDayForEmployee(
        client,
        employeeId,
        parseLocatorDateOnly(slipDate)
      );
      if (!workingDay.ok) {
        await client.query('ROLLBACK');
        cleanup();
        return res.status(400).json({ error: workingDay.error });
      }
      const locatorType = await getLocatorTypeByCode(client, requestType, {
        activeOnly: true,
      });
      if (!locatorType) {
        await client.query('ROLLBACK');
        cleanup();
        return res.status(400).json({ error: 'Invalid request_type' });
      }
      const typeSnapshot = captureLocatorTypeSnapshot(locatorType);
      const attachmentError = locatorAttachmentRequiredError(
        locatorType,
        Boolean(relPath)
      );
      if (attachmentError) {
        await client.query('ROLLBACK');
        cleanup();
        return res.status(400).json({ error: attachmentError });
      }
      const conflictCheck = await findLocatorRequestConflicts(client, {
        employeeId,
        slipDate,
        slots: { amIn, amOut, pmIn, pmOut },
        phase: 'approval',
      });
      if (!conflictCheck.ok) {
        await client.query('ROLLBACK');
        cleanup();
        return res.status(409).json(locatorConflictPayload(conflictCheck));
      }
      const snapshot = await getDepartmentReviewSnapshotForDate(
        client,
        employeeId,
        slipDate
      );
      const inserted = await client.query(
        `INSERT INTO locator_slips (
           employee_id, department_id, assigned_department_head_id,
           slip_date, am_in, am_out, pm_in, pm_out, request_type, office, reason,
           request_type_label_snapshot, request_type_short_label_snapshot,
           request_type_location_label_snapshot, request_type_location_hint_snapshot,
           request_type_dtr_slot_label_snapshot, request_type_dtr_print_label_snapshot,
           request_type_requires_attachment_snapshot,
           request_type_coverage_mode_snapshot, request_type_snapshot_at,
           attachment_name, attachment_path, attachment_mime_type,
           attachment_uploaded_at, status, hr_reviewer_id, hr_reviewed_at,
           hr_remarks, is_retroactive_correction,
           retroactive_correction_reason, retroactive_corrected_by,
           retroactive_corrected_at, created_at, updated_at
         ) VALUES (
           $1::uuid, $2::uuid, $3::uuid,
           $4::date, $5::boolean, $6::boolean, $7::boolean, $8::boolean,
           $9::text, $10::text, $11::text,
           $17::text, $18::text, $19::text, $20::text,
           $21::text, $22::text, $23::boolean, $24::text, now(),
           $12::text, $13::text, $14::text,
           CASE WHEN $13::text IS NULL THEN NULL ELSE now() END,
           'approved', $15::uuid, now(), $16::text, true,
           $16::text, $15::uuid, now(), now(), now()
         ) RETURNING id`,
        [
          employeeId,
          snapshot?.departmentId || null,
          snapshot?.departmentHeadUserId || null,
          slipDate,
          amIn,
          amOut,
          pmIn,
          pmOut,
          requestType,
          office,
          reason,
          relPath ? req.file.originalname || 'attachment' : null,
          relPath,
          relPath ? req.file.mimetype || null : null,
          reviewerId,
          correctionReason,
          typeSnapshot.label,
          typeSnapshot.shortLabel,
          typeSnapshot.locationLabel,
          typeSnapshot.locationHint,
          typeSnapshot.dtrSlotLabel,
          typeSnapshot.dtrPrintLabel,
          typeSnapshot.requiresAttachment,
          typeSnapshot.coverageMode,
        ]
      );
      await client.query('COMMIT');

      const mapped = await fetchLocatorSlipDetails(pool, inserted.rows[0].id);
      notifySafe(() =>
        locatorNotifications.notifyEmployee(pool, {
          employeeUserId: employeeId,
          slipId: inserted.rows[0].id,
          type: 'locator_retroactive_correction_recorded',
          title: 'Locator correction recorded',
          body: `HR recorded a locator correction for ${slipDate}.`,
          metadata: { correction_reason: correctionReason },
        })
      );
      broadcastLocatorUpdated('retroactive_correction_recorded', mapped);
      return res.status(201).json(mapped);
    } catch (err) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {}
      cleanup();
      console.error('[locator POST /admin/corrections]', err);
      return res.status(500).json({ error: 'Failed to record locator correction' });
    } finally {
      client.release();
    }
  }
);

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
    if (![
      'pending',
      'pending_department_head',
      'pending_hr',
      'returned_for_correction',
    ].includes(status)) {
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
              corrector.full_name AS retroactive_corrector_name,
              revoker.full_name AS revoked_by_name,
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
       LEFT JOIN users corrector ON corrector.id = ls.retroactive_corrected_by
       LEFT JOIN users revoker ON revoker.id = ls.revoked_by
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

// PATCH /api/locator-slips/:id/resubmit
router.patch('/:id/resubmit', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              lrt.requires_attachment AS request_type_requires_attachment
       FROM locator_slips ls
       JOIN users u ON u.id = ls.employee_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid
         AND ls.employee_id = $2::uuid
       FOR UPDATE OF ls`,
      [id, userId]
    );
    const row = current.rows[0];
    if (!row) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    if (row.status !== 'returned_for_correction') {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: `Cannot resubmit locator slip with status '${row.status}'`,
      });
    }
    const attachmentError = locatorReviewAttachmentError(row);
    if (attachmentError) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: attachmentError });
    }
    const resubmitWindow = evaluateEmployeeLocatorDateWindow({
      slipDate: row.slip_date_text,
    });
    if (!resubmitWindow.ok) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: resubmitWindow.error,
        code: resubmitWindow.code,
      });
    }
    const workingDayCheck = await validateLocatorWorkingDayForEmployee(
      client,
      userId,
      parseLocatorDateOnly(row.slip_date_text)
    );
    if (!workingDayCheck.ok) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: workingDayCheck.error });
    }
    const conflictCheck = await findLocatorRequestConflicts(client, {
      employeeId: userId,
      slipDate: row.slip_date_text,
      slots: row,
      excludeSlipId: id,
      phase: 'submission',
    });
    if (!conflictCheck.ok) {
      await client.query('ROLLBACK');
      return res.status(409).json(locatorConflictPayload(conflictCheck));
    }

    const reviewSnapshot = await getDepartmentReviewSnapshotForDate(
      client,
      userId,
      row.slip_date_text
    );
    const departmentHeadUserId =
      reviewSnapshot?.departmentHeadUserId || null;
    const submitStatus = departmentHeadUserId
      ? 'pending_department_head'
      : 'pending_hr';

    await client.query(
      `UPDATE locator_slips
       SET status = $2::text,
           department_id = $3::uuid,
           assigned_department_head_id = $4::uuid,
           updated_at = now()
       WHERE id = $1::uuid`,
      [
        id,
        submitStatus,
        reviewSnapshot?.departmentId || null,
        departmentHeadUserId,
      ]
    );
    await client.query('COMMIT');

    notifySafe(() =>
      locatorNotifications.notifyAfterSubmit(pool, {
        slipId: id,
        status: submitStatus,
        employeeUserId: userId,
        employeeName: row.employee_name,
        slipDate: row.slip_date_text,
        amIn: row.am_in,
        amOut: row.am_out,
        pmIn: row.pm_in,
        pmOut: row.pm_out,
        requestType: row.request_type,
        departmentHeadUserId,
      })
    );

    const mapped = await fetchLocatorSlipDetails(pool, id);
    broadcastLocatorUpdated('resubmitted', mapped || row, { status: submitStatus });
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/resubmit]', err);
    res.status(500).json({ error: 'Failed to resubmit locator slip' });
  } finally {
    client.release();
  }
});

// POST /api/locator-slips/:id/attachment - upload/replace attachment.
router.post('/:id/attachment', protect, uploadLocatorAttachmentMw, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  if (!req.file) return res.status(400).json({ error: 'Attachment is required.' });
  const relPath = `${LOCATOR_ATTACHMENT_SUBDIR}/${req.file.filename}`;
  const cleanupNewFile = () => removeLocatorAttachmentFile(relPath);
  try {
    const current = await pool.query(
      `SELECT id, status, employee_id, attachment_path
       FROM locator_slips
       WHERE id = $1::uuid AND employee_id = $2::uuid`,
      [req.params.id, userId]
    );
    const row = current.rows[0];
    if (!row) {
      cleanupNewFile();
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    if (!canModifyLocatorAttachment(row.status)) {
      cleanupNewFile();
      return res.status(409).json({
        error: 'Attachments are locked after submission. They can only be changed after the request is returned for correction.',
      });
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
    if (row.attachment_path && row.attachment_path !== relPath) {
      removeLocatorAttachmentFile(row.attachment_path);
    }
    broadcastLocatorUpdated('attachment_replaced', row, { slipId: req.params.id });
    res.json({ attachment_name: req.file.originalname || 'attachment', attachment_path: relPath });
  } catch (err) {
    cleanupNewFile();
    console.error('[locator POST /:id/attachment]', err);
    res.status(500).json({ error: 'Failed to upload attachment' });
  }
});

// DELETE /api/locator-slips/:id/attachment
router.delete('/:id/attachment', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const current = await pool.query(
      `SELECT id, status, employee_id, attachment_path
       FROM locator_slips
       WHERE id = $1::uuid AND employee_id = $2::uuid`,
      [req.params.id, userId]
    );
    const row = current.rows[0];
    if (!row) return res.status(404).json({ error: 'Locator slip not found' });
    if (!canModifyLocatorAttachment(row.status)) {
      return res.status(409).json({
        error: 'Attachments are locked after submission. They can only be changed after the request is returned for correction.',
      });
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
    removeLocatorAttachmentFile(row.attachment_path);
    broadcastLocatorUpdated('attachment_removed', row, { slipId: req.params.id });
    res.json({ ok: true });
  } catch (err) {
    console.error('[locator DELETE /:id/attachment]', err);
    res.status(500).json({ error: 'Failed to remove attachment' });
  }
});

// GET /api/locator-slips/:id/attachment
router.get('/:id/attachment', protect, async (req, res) => {
  const userId = req.user?.id;
  const role = req.user?.role;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const current = await pool.query(
      `SELECT id,
              employee_id,
              department_id,
              assigned_department_head_id,
              status,
              dept_head_reviewer_id,
              attachment_name,
              attachment_path,
              attachment_mime_type
       FROM locator_slips
       WHERE id = $1::uuid`,
      [req.params.id]
    );
    const row = current.rows[0];
    if (!row) return res.status(404).json({ error: 'Locator slip not found' });

    const normalizedRole = String(role || '').trim().toLowerCase();
    const isOwner = String(row.employee_id) === String(userId);
    const isHrOrAdmin = normalizedRole === 'hr' || normalizedRole === 'admin';
    let assignedDepartmentHeadId =
      row.assigned_department_head_id || null;
    if (
      !assignedDepartmentHeadId &&
      !isOwner &&
      !isHrOrAdmin &&
      row.status === 'pending_department_head' &&
      row.department_id
    ) {
      assignedDepartmentHeadId = await findDepartmentHeadUserId(pool, row.department_id);
    }
    const access = resolveLocatorAttachmentAccess({
      role,
      userId,
      ownerUserId: row.employee_id,
      requestStatus: row.status,
      assignedDepartmentHeadId,
      reviewingDepartmentHeadId: row.dept_head_reviewer_id,
    });
    const auditBase = {
      locatorSlipId: row.id,
      attachmentName: row.attachment_name || null,
      accessedBy: userId,
      actorRole: role || null,
      accessReason: access.reason,
      ipAddress: req.ip || req.socket?.remoteAddress || null,
      userAgent: req.get('user-agent') || null,
    };
    if (!access.allowed) {
      await recordLocatorAttachmentAccess(pool, {
        ...auditBase,
        accessOutcome: 'denied',
      });
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    if (!row.attachment_path) {
      await recordLocatorAttachmentAccess(pool, {
        ...auditBase,
        accessOutcome: 'missing_attachment',
      });
      return res.status(404).json({ error: 'No attachment for this request' });
    }
    if (!locatorAttachmentFileExists(row.attachment_path)) {
      await recordLocatorAttachmentAccess(pool, {
        ...auditBase,
        accessOutcome: 'missing_file',
      });
      return res.status(404).json({ error: 'Attachment file not found' });
    }
    await recordLocatorAttachmentAccess(pool, {
      ...auditBase,
      accessOutcome: 'allowed',
    });
    const filePath = path.resolve(UPLOAD_DIR, row.attachment_path);
    const filename = (row.attachment_name || 'attachment').replace(/[^\w.\- ()]/g, '_').slice(0, 180);
    if (row.attachment_mime_type) res.setHeader('Content-Type', row.attachment_mime_type);
    res.setHeader('Content-Disposition', `inline; filename="${filename}"`);
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
    const status = (req.query?.status || '').toString().trim() || null;
    if (status && !isValidStatus(status)) {
      return res.status(400).json({ error: 'Invalid status filter' });
    }
    const rows = await client.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              assigned_dh.full_name AS assigned_department_head_name,
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
       LEFT JOIN users assigned_dh ON assigned_dh.id = ls.assigned_department_head_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE (
           (
             ls.status = 'pending_department_head'
             AND (
               ls.assigned_department_head_id = $1::uuid
               OR (
                 ls.assigned_department_head_id IS NULL
                 AND ls.department_id = $2::uuid
               )
             )
           )
           OR ls.dept_head_reviewer_id = $1::uuid
         )
         AND ($3::text IS NULL OR ls.status = $3::text)
       ORDER BY ls.updated_at DESC, ls.created_at DESC
       LIMIT 500`,
      [userId, deptInfo.departmentId, status]
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
    const current = await client.query(
      `SELECT ls.id,
              ls.status,
              ls.employee_id,
              ls.slip_date::text AS slip_date,
              ls.request_type,
              ls.am_in,
              ls.am_out,
              ls.pm_in,
              ls.pm_out,
              ls.attachment_path,
              ls.request_type_requires_attachment_snapshot,
              lrt.requires_attachment AS request_type_requires_attachment
       FROM locator_slips ls
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid
         AND (
           ls.assigned_department_head_id = $2::uuid
           OR (
             ls.assigned_department_head_id IS NULL
             AND ls.department_id = $3::uuid
           )
         )
       FOR UPDATE OF ls`,
      [id, reviewerId, deptInfo.departmentId]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found or not assigned to you' });
    }
    if (current.rows[0].status !== 'pending_department_head') {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot approve locator slip with status '${current.rows[0].status}'`,
      });
    }
    const attachmentError = locatorReviewAttachmentError(current.rows[0]);
    if (attachmentError) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: attachmentError });
    }
    const conflictCheck = await findLocatorRequestConflicts(client, {
      employeeId: current.rows[0].employee_id,
      slipDate: current.rows[0].slip_date,
      slots: current.rows[0],
      excludeSlipId: id,
      phase: 'approval',
      checkLeave: false,
      checkAttendance: false,
    });
    if (!conflictCheck.ok) {
      await client.query('ROLLBACK');
      return res.status(409).json(locatorConflictPayload(conflictCheck));
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
    const mapped = await fetchLocatorSlipDetails(pool, id);
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
    const current = await client.query(
      `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
         AND (
           assigned_department_head_id = $2::uuid
           OR (
             assigned_department_head_id IS NULL
             AND department_id = $3::uuid
           )
         )
       FOR UPDATE`,
      [id, reviewerId, deptInfo.departmentId]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found or not assigned to you' });
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

// PATCH /api/locator-slips/:id/department-head-return
router.patch('/:id/department-head-return', protect, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim();
  if (!remarks) {
    return res.status(400).json({ error: 'Correction remarks are required.' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const deptInfo = await isDepartmentHead(client, reviewerId);
    const current = await client.query(
      `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
         AND (
           assigned_department_head_id = $2::uuid
           OR (
             assigned_department_head_id IS NULL
             AND department_id = $3::uuid
           )
         )
       FOR UPDATE`,
      [id, reviewerId, deptInfo.departmentId]
    );
    const row = current.rows[0];
    if (!row) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found or not assigned to you' });
    }
    if (row.status !== 'pending_department_head') {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: `Cannot return locator slip with status '${row.status}'`,
      });
    }

    await client.query(
      `UPDATE locator_slips
       SET status = 'returned_for_correction',
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
        employeeUserId: row.employee_id,
        slipId: id,
        type: 'locator_returned_department_head',
        title: 'Locator request returned for correction',
        body: `Your department head returned this locator request. ${remarks}`,
        metadata: { reviewer_remarks: remarks, returned_by: 'department_head' },
      })
    );
    const mapped = await fetchLocatorSlipDetails(pool, id);
    broadcastLocatorUpdated('department_head_returned', mapped || row);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/department-head-return]', err);
    res.status(500).json({ error: 'Failed to return locator slip for correction' });
  } finally {
    client.release();
  }
});

// GET /api/locator-slips/admin
router.get('/admin', protect, requireAdminOrHr, async (req, res) => {
  try {
    const parsedFilters = parseLocatorAdminFilters(req.query);
    if (!parsedFilters.ok) {
      return res.status(400).json({ error: parsedFilters.error });
    }
    const {
      page,
      pageSize,
      statuses,
      departmentId,
      employeeId,
      from,
      to,
      search,
    } = parsedFilters.filters;
    const requestTypeRaw = (req.query?.request_type || '').toString().trim();
    const requestType = requestTypeRaw ? normalizeRequestType(requestTypeRaw) : null;
    if (requestTypeRaw && !requestType) {
      return res.status(400).json({ error: 'Invalid request_type filter' });
    }

    const filterParams = [
      statuses,
      requestType,
      departmentId,
      employeeId,
      from,
      to,
      search,
    ];
    const filterSql = `
      FROM locator_slips ls
      LEFT JOIN users u ON u.id = ls.employee_id
      LEFT JOIN departments d ON d.id = ls.department_id
      LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
      LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
      LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
      LEFT JOIN users corrector ON corrector.id = ls.retroactive_corrected_by
      LEFT JOIN users revoker ON revoker.id = ls.revoked_by
      WHERE ($1::text[] IS NULL OR ls.status = ANY($1::text[]))
        AND ($2::text IS NULL OR ls.request_type = $2::text)
        AND ($3::uuid IS NULL OR ls.department_id = $3::uuid)
        AND ($4::uuid IS NULL OR ls.employee_id = $4::uuid)
        AND ($5::date IS NULL OR ls.slip_date >= $5::date)
        AND ($6::date IS NULL OR ls.slip_date <= $6::date)
        AND (
          $7::text IS NULL
          OR u.full_name ILIKE '%' || $7::text || '%'
          OR d.name ILIKE '%' || $7::text || '%'
          OR ls.office ILIKE '%' || $7::text || '%'
          OR ls.reason ILIKE '%' || $7::text || '%'
          OR COALESCE(ls.request_type_label_snapshot, lrt.label, '')
             ILIKE '%' || $7::text || '%'
        )`;
    const countResult = await pool.query(
      `SELECT COUNT(*)::integer AS total ${filterSql}`,
      filterParams
    );
    const total = Number(countResult.rows[0]?.total || 0);
    const pageCount = Math.max(1, Math.ceil(total / pageSize));
    const effectivePage = Math.min(page, pageCount);
    const offset = (effectivePage - 1) * pageSize;

    const [rows, departments, employees] = await Promise.all([
      pool.query(
      `SELECT ls.*,
              ls.slip_date::text AS slip_date_text,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name,
              corrector.full_name AS retroactive_corrector_name,
              revoker.full_name AS revoked_by_name,
              lrt.label AS request_type_label,
              lrt.short_label AS request_type_short_label,
              lrt.location_label AS request_type_location_label,
              lrt.location_hint AS request_type_location_hint,
              lrt.dtr_slot_label AS request_type_dtr_slot_label,
              lrt.dtr_print_label AS request_type_dtr_print_label,
              lrt.requires_attachment AS request_type_requires_attachment,
              lrt.coverage_mode AS request_type_coverage_mode
       ${filterSql}
       ORDER BY ls.updated_at DESC, ls.created_at DESC, ls.id DESC
       LIMIT $8::integer OFFSET $9::integer`,
        [...filterParams, pageSize, offset]
      ),
      pool.query(
        `SELECT DISTINCT d.id, d.name
         FROM locator_slips ls
         JOIN departments d ON d.id = ls.department_id
         WHERE d.name IS NOT NULL AND btrim(d.name) <> ''
         ORDER BY d.name`
      ),
      pool.query(
        `SELECT u.id,
                u.full_name AS name,
                COALESCE(
                  array_agg(DISTINCT ls.department_id::text)
                    FILTER (WHERE ls.department_id IS NOT NULL),
                  ARRAY[]::text[]
                ) AS department_ids
         FROM locator_slips ls
         JOIN users u ON u.id = ls.employee_id
         WHERE u.full_name IS NOT NULL AND btrim(u.full_name) <> ''
         GROUP BY u.id, u.full_name
         ORDER BY u.full_name`
      ),
    ]);
    res.json({
      items: rows.rows.map(mapLocatorRow),
      pagination: {
        page: effectivePage,
        page_size: pageSize,
        total,
        page_count: pageCount,
      },
      filter_options: {
        departments: departments.rows.map((row) => ({
          id: row.id,
          name: row.name,
        })),
        employees: employees.rows.map((row) => ({
          id: row.id,
          name: row.name,
          department_ids: row.department_ids || [],
        })),
      },
    });
  } catch (err) {
    console.error('[locator GET /admin]', err);
    res.status(500).json({ error: 'Failed to fetch locator slips (admin)' });
  }
});

// PATCH /api/locator-slips/:id/return-for-correction
router.patch('/:id/return-for-correction', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (
    req.body?.reviewer_remarks ||
    req.body?.reason ||
    req.body?.hr_remarks ||
    ''
  ).toString().trim();
  if (!remarks) {
    return res.status(400).json({ error: 'Correction remarks are required.' });
  }

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
    const row = current.rows[0];
    if (!row) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    if (!['pending_hr', 'pending'].includes(row.status)) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: `Cannot return locator slip with status '${row.status}'`,
      });
    }

    await client.query(
      `UPDATE locator_slips
       SET status = 'returned_for_correction',
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
        employeeUserId: row.employee_id,
        slipId: id,
        type: 'locator_returned_hr',
        title: 'Locator request returned for correction',
        body: `HR returned this locator request. ${remarks}`,
        metadata: { reviewer_remarks: remarks, returned_by: 'hr' },
      })
    );
    const mapped = await fetchLocatorSlipDetails(pool, id);
    broadcastLocatorUpdated('hr_returned', mapped || row);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/return-for-correction]', err);
    res.status(500).json({ error: 'Failed to return locator slip for correction' });
  } finally {
    client.release();
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
      `SELECT ls.id,
              ls.status,
              ls.employee_id,
              ls.slip_date::text AS slip_date,
              ls.am_in,
              ls.am_out,
              ls.pm_in,
              ls.pm_out,
              ls.attachment_path,
              ls.request_type_requires_attachment_snapshot,
              lrt.requires_attachment AS request_type_requires_attachment
       FROM locator_slips ls
       LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
       WHERE ls.id = $1::uuid
       FOR UPDATE OF ls`,
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
    const attachmentError = locatorReviewAttachmentError(current.rows[0]);
    if (attachmentError) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: attachmentError });
    }
    const conflictCheck = await findLocatorRequestConflicts(client, {
      employeeId: current.rows[0].employee_id,
      slipDate: current.rows[0].slip_date,
      slots: current.rows[0],
      excludeSlipId: id,
      phase: 'approval',
    });
    if (!conflictCheck.ok) {
      await client.query('ROLLBACK');
      return res.status(409).json(locatorConflictPayload(conflictCheck));
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

// PATCH /api/locator-slips/:id/revoke
// HR/Admin may undo an accidental final approval within three days. The
// revoked status immediately removes locator coverage without deleting punches.
router.patch('/:id/revoke', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const reason = (
    req.body?.revocation_reason ||
    req.body?.reviewer_remarks ||
    req.body?.reason ||
    ''
  ).toString().trim();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT id, status, employee_id, slip_date::text AS slip_date,
              hr_reviewed_at
       FROM locator_slips
       WHERE id = $1::uuid
       FOR UPDATE`,
      [id]
    );
    const row = current.rows[0];
    if (!row) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found' });
    }

    const policy = evaluateLocatorRevocation({
      status: row.status,
      approvedAt: row.hr_reviewed_at,
      reason,
    });
    if (!policy.ok) {
      await client.query('ROLLBACK');
      return res.status(policy.statusCode).json({
        error: policy.error,
        code: policy.code,
        ...(policy.deadline
          ? { revoke_deadline: policy.deadline.toISOString() }
          : {}),
      });
    }

    const postingTable = await client.query(
      `SELECT to_regclass('public.leave_attendance_deductions') AS table_name`
    );
    let reconciliationRequired = false;
    if (postingTable.rows[0]?.table_name) {
      const posting = await client.query(
        `SELECT 1
         FROM leave_attendance_deductions
         WHERE user_id = $1::uuid
           AND service_month = date_trunc('month', $2::date)::date
         LIMIT 1`,
        [row.employee_id, row.slip_date]
      );
      reconciliationRequired = posting.rowCount > 0;
    }

    await client.query(
      `UPDATE locator_slips
       SET status = 'revoked',
           revoked_by = $2::uuid,
           revoked_at = now(),
           revocation_reason = $3::text,
           month_end_reconciliation_required = $4::boolean,
           month_end_reconciled_at = NULL,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, reviewerId, policy.revocationReason, reconciliationRequired]
    );
    await client.query('COMMIT');

    const mapped = await fetchLocatorSlipDetails(pool, id);
    notifySafe(() =>
      locatorNotifications.notifyEmployee(pool, {
        employeeUserId: row.employee_id,
        slipId: id,
        type: 'locator_approval_revoked',
        title: 'Locator approval revoked',
        body: `HR revoked this locator approval. ${policy.revocationReason}`,
        metadata: {
          revocation_reason: policy.revocationReason,
          reconciliation_required: reconciliationRequired,
        },
      })
    );
    broadcastLocatorUpdated('revoked', mapped || row, {
      previousStatus: 'approved',
      dateFrom: row.slip_date,
      dateTo: row.slip_date,
      reconciliationRequired,
    });
    return res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/revoke]', err);
    return res.status(500).json({ error: 'Failed to revoke locator approval' });
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
