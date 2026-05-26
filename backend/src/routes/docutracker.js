const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  transitionDocument,
  addDocumentRemark,
  createDocument: createDocumentEngine,
  getEffectivePermissionExplanation,
  listDocuments,
  canUserPerformDocumentAction,
  isDraftOrWipDocument,
} = require('../services/docutrackerWorkflowService');
const {
  ACTIVE_WORKFLOW_STATUSES_FOR_OVERDUE,
} = require('../services/docutrackerStatusSemantics');

const { coalesceDocumentTitle } = require('../utils/docutrackerDisplayTitle');
const { sameEntityId } = require('../utils/sameEntityId');

const router = express.Router();
const protect = [authMiddleware];

const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');
const DOCUTRACKER_ATTACHMENT_SUBDIR = 'docutracker-attachments';
const DOCUTRACKER_ATTACHMENT_DIR = path.join(UPLOAD_DIR, DOCUTRACKER_ATTACHMENT_SUBDIR);
if (!fs.existsSync(DOCUTRACKER_ATTACHMENT_DIR)) {
  fs.mkdirSync(DOCUTRACKER_ATTACHMENT_DIR, { recursive: true });
}

const ALLOWED_DOCUTRACKER_ATTACHMENT_EXT = /\.(pdf|jpg|jpeg|png)$/i;
const MAX_DOCUTRACKER_ATTACHMENT_SIZE = 10 * 1024 * 1024; // 10MB

const docutrackerAttachmentStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, DOCUTRACKER_ATTACHMENT_DIR),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.pdf';
    const safeExt = ALLOWED_DOCUTRACKER_ATTACHMENT_EXT.test(ext) ? ext : '.pdf';
    cb(null, `dt_${uuidv4()}${safeExt}`);
  },
});

const uploadDocutrackerAttachment = multer({
  storage: docutrackerAttachmentStorage,
  limits: { fileSize: MAX_DOCUTRACKER_ATTACHMENT_SIZE },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    const ok = ['.pdf', '.jpg', '.jpeg', '.png'].includes(ext);
    if (!ok) cb(new Error('Allowed file types: PDF, JPG, JPEG, PNG'), false);
    else cb(null, true);
  },
});

function uploadDocutrackerAttachmentMw(req, res, next) {
  uploadDocutrackerAttachment.single('file')(req, res, (err) => {
    if (err) {
      if (err.message === 'Allowed file types: PDF, JPG, JPEG, PNG') {
        return res.status(400).json({ error: err.message });
      }
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ error: 'File too large. Max 10MB.' });
      }
      return next(err);
    }
    next();
  });
}

async function loadDocumentRowForAccess(documentId) {
  const r = await pool.query('SELECT * FROM docutracker_documents WHERE id = $1', [documentId]);
  return r.rows[0] || null;
}

async function canModifyDocumentAttachment(client, docRow, user) {
  if (!docRow || !user?.id) return false;
  if (user.role === 'admin') return true;
  if (isDraftOrWipDocument(docRow) && sameEntityId(docRow.created_by, user.id)) return true;
  return canUserPerformDocumentAction(client, { user, document: docRow, action: 'edit' });
}

async function canDownloadDocumentFile(client, docRow, user) {
  if (!docRow || !user?.id) return false;
  if (user.role === 'admin') return true;
  if (await canUserPerformDocumentAction(client, { user, document: docRow, action: 'download' })) {
    return true;
  }
  return canUserPerformDocumentAction(client, { user, document: docRow, action: 'view' });
}

// Role/user permission rows cover baseline access and draft-start capability.
// Runtime workflow actions (approve/forward/reject/return) are enforced by
// current holder / step-assignee logic.
const GENERAL_PERMISSION_ACTIONS = new Set([
  'view',
  'create',
  'create_draft',
  'download',
  'submit',
]);

function normalizeGeneralPermissionAction(action) {
  const a = String(action || '').trim().toLowerCase();
  if (!a) return a;
  if (a === 'create' || a === 'createdraft') return 'create_draft';
  return a;
}

function generalPermissionActionVariants(action) {
  const normalized = normalizeGeneralPermissionAction(action);
  if (!normalized) return [];
  if (normalized === 'create_draft') return ['create_draft', 'create'];
  return [normalized];
}

/** Fields that must not be changed via PUT by non-admins (use transitions or admin tools). */
const DOCUTRACKER_PUT_WORKFLOW_FIELDS = [
  'document_type',
  'current_holder_id',
  'current_step',
  'status',
  'sent_time',
  'deadline_time',
  'reviewed_time',
  'escalation_level',
  'needs_admin_intervention',
];

function putBodyTouchesWorkflowFields(body) {
  if (!body || typeof body !== 'object') return false;
  return DOCUTRACKER_PUT_WORKFLOW_FIELDS.some((k) => body[k] !== undefined);
}

/** Legacy DBs may have unused NOT NULL flow_id on docutracker_routing_configs. */
async function routingConfigCacheFlowIdColumn(client) {
  const r = await client.query(
    `SELECT data_type
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'docutracker_routing_configs'
       AND column_name = 'flow_id'`
  );
  return r.rows[0]?.data_type ?? null;
}

function flowIdValueForRoutingConfig(documentType, dataType) {
  if (dataType === 'uuid') return uuidv4();
  return String(documentType || '').trim() || 'default';
}

/**
 * Upsert latest routing config cache row (schema-tolerant: optional flow_id column).
 */
async function upsertLatestRoutingConfigCache(
  client,
  { documentType, stepsJson, reviewDeadlineHours }
) {
  const flowIdType = await routingConfigCacheFlowIdColumn(client);
  const cacheHit = await client.query(
    `SELECT id FROM docutracker_routing_configs WHERE document_type = $1 LIMIT 1`,
    [documentType]
  );
  if (cacheHit.rows.length > 0) {
    await client.query(
      `UPDATE docutracker_routing_configs
       SET steps = $2::jsonb,
           review_deadline_hours = COALESCE($3, review_deadline_hours),
           updated_at = now()
       WHERE document_type = $1`,
      [documentType, stepsJson, reviewDeadlineHours ?? null]
    );
    return;
  }

  if (flowIdType) {
    const flowId = flowIdValueForRoutingConfig(documentType, flowIdType);
    await client.query(
      `INSERT INTO docutracker_routing_configs
       (document_type, steps, review_deadline_hours, flow_id)
       VALUES ($1, $2::jsonb, COALESCE($3, 1), $4)`,
      [documentType, stepsJson, reviewDeadlineHours ?? null, flowId]
    );
    return;
  }

  await client.query(
    `INSERT INTO docutracker_routing_configs
     (document_type, steps, review_deadline_hours)
     VALUES ($1, $2::jsonb, COALESCE($3, 1))`,
    [documentType, stepsJson, reviewDeadlineHours ?? null]
  );
}

/**
 * Utility: map DB row to document response DTO.
 */
function mapDocumentRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    document_number: row.document_number,
    document_type: row.document_type,
    title: coalesceDocumentTitle(row),
    description: row.description,
    source_module: row.source_module,
    source_table: row.source_table,
    source_record_id: row.source_record_id,
    source_title: row.source_title,
    file_path: row.file_path,
    file_name: row.file_name,
    created_by: row.created_by,
    creator_name: row.creator_name,
    current_holder_id: row.current_holder_id,
    current_step: row.current_step,
    status: row.status,
    sent_time: row.sent_time,
    deadline_time: row.deadline_time,
    reviewed_time: row.reviewed_time,
    workflow_version: row.workflow_version,
    escalation_level: row.escalation_level,
    needs_admin_intervention: row.needs_admin_intervention,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

/** Map Flutter/camelCase status names to DB-friendly values (legacy + snake). */
function normalizeDocStatus(s) {
  if (s == null || s === '') return s;
  const x = String(s).trim();
  const map = {
    inReview: 'in_review',
    inreview: 'in_review',
    in_review: 'in_review',
  };
  return map[x] || x;
}

async function assertDocumentReadable(req, documentId) {
  const isAdmin = req.user.role === 'admin';
  if (isAdmin) return true;

  const r = await pool.query(`SELECT * FROM docutracker_documents WHERE id = $1`, [documentId]);
  const docRow = r.rows[0];
  if (!docRow) return false;

  return canUserPerformDocumentAction(pool, { user: req.user, document: docRow, action: 'view' });
}

/**
 * GET /api/docutracker/documents
 * Query params:
 * - type (document_type, optional)
 * - status (optional)
 * - holderId (current_holder_id, optional)
 * - createdBy (optional)
 * - q (search in title/description, optional)
 * - sourceModule (optional)
 * - sourceTable (optional)
 * - limit (default 50)
 * - offset (default 0)
 */
router.get('/documents', protect, async (req, res) => {
  try {
    const {
      type,
      status,
      holderId,
      createdBy,
      q,
      sourceModule,
      sourceTable,
      limit = 50,
      offset = 0,
    } = req.query;

    const limitVal = Number.isNaN(Number(limit)) ? 50 : Math.min(Number(limit), 200);
    const offsetVal = Number.isNaN(Number(offset)) ? 0 : Math.max(Number(offset), 0);

    const { documents } = await listDocuments(pool, req.user, {
      type: type && type !== 'All' ? String(type) : undefined,
      status: status && status !== 'All' ? String(status) : undefined,
      holderId: holderId ? String(holderId) : undefined,
      createdBy: createdBy ? String(createdBy) : undefined,
      q: q ? String(q) : undefined,
      sourceModule: sourceModule ? String(sourceModule) : undefined,
      sourceTable: sourceTable ? String(sourceTable) : undefined,
      limit: limitVal,
      offset: offsetVal,
    });

    res.json(documents.map((row) => mapDocumentRow(row)));
  } catch (err) {
    console.error('[docutracker GET /documents]', err);
    res.status(500).json({ error: 'Failed to fetch documents' });
  }
});

/**
 * POST /api/docutracker/documents
 * Body:
 * {
 *   document_type,
 *   title,
 *   description?,
 *   file_path?,
 *   file_name?,
 *   current_holder_id?,
 *   deadline_time?,
 *   // Optional link to existing module form:
 *   source_module?,      // 'ld' | 'rsp' | 'dtr' | etc.
 *   source_table?,       // e.g. 'bi_form_entries'
 *   source_record_id?,   // UUID of the form row
 *   source_title?        // label from that form (for display)
 * }
 * Uses req.user.id as created_by.
 */
router.post('/documents', protect, async (req, res) => {
  try {
    const b = req.body || {};
    const created = await createDocumentEngine(pool, req.user, {
      document_type: b.document_type,
      title: b.title,
      description: b.description,
      file_path: b.file_path,
      file_name: b.file_name,
      current_holder_id: b.current_holder_id,
      deadline_time: b.deadline_time,
      source_module: b.source_module,
      source_table: b.source_table,
      source_record_id: b.source_record_id,
      source_title: b.source_title,
      document_number: b.document_number,
      status: b.status != null ? normalizeDocStatus(b.status) : undefined,
    });
    res.status(201).json(created);
  } catch (err) {
    console.error('[docutracker POST /documents]', err);
    const mapped = mapWorkflowServiceError(err);
    res.status(mapped.status).json({ error: mapped.error });
  }
});

/**
 * GET /api/docutracker/next-document-number
 */
router.get('/next-document-number', protect, async (_req, res) => {
  try {
    const year = new Date().getFullYear();
    const prefix = `DOC-${year}-`;
    const result = await pool.query(
      `SELECT document_number FROM docutracker_documents
       WHERE document_number LIKE $1
       ORDER BY document_number DESC
       LIMIT 1`,
      [`${prefix}%`]
    );
    if (result.rows.length > 0) {
      const last = String(result.rows[0].document_number || '');
      const numStr = last.replace(prefix, '');
      const num = parseInt(numStr, 10) || 0;
      return res.json({ document_number: `${prefix}${String(num + 1).padStart(4, '0')}` });
    }
    return res.json({ document_number: `${prefix}0001` });
  } catch (err) {
    console.error('[docutracker GET /next-document-number]', err);
    res.status(500).json({ error: 'Failed to allocate number' });
  }
});

/**
 * GET /api/docutracker/documents-overdue (admin — escalation worker)
 */
router.get('/documents-overdue', protect, requireAdmin, async (_req, res) => {
  try {
    const result = await pool.query(
      `SELECT d.*, creator.full_name AS creator_name
       FROM docutracker_documents d
       LEFT JOIN users creator ON creator.id = d.created_by
       WHERE d.deadline_time IS NOT NULL
         AND d.deadline_time < now()
         AND d.status = ANY($1::text[])
       ORDER BY d.deadline_time ASC`,
      [ACTIVE_WORKFLOW_STATUSES_FOR_OVERDUE]
    );
    res.json(result.rows.map(mapDocumentRow));
  } catch (err) {
    console.error('[docutracker GET /documents-overdue]', err);
    res.status(500).json({ error: 'Failed to list overdue documents' });
  }
});

/**
 * GET /api/docutracker/notifications
 */
router.get('/notifications', protect, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 100);
    const result = await pool.query(
      `SELECT * FROM docutracker_notifications
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT $2`,
      [req.user.id, limit]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('[docutracker GET /notifications]', err);
    res.status(500).json({ error: 'Failed to list notifications' });
  }
});

/**
 * POST /api/docutracker/notifications/mark-all-read
 * Marks every notification read for the authenticated user.
 */
router.post('/notifications/mark-all-read', protect, async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE docutracker_notifications
       SET read = true
       WHERE user_id = $1 AND read = false`,
      [req.user.id]
    );
    res.json({ updated: result.rowCount });
  } catch (err) {
    console.error('[docutracker POST /notifications/mark-all-read]', err);
    res.status(500).json({ error: 'Failed to mark notifications read' });
  }
});

/**
 * POST /api/docutracker/notifications
 * Admin-only: prevents forging notifications for arbitrary users.
 */
router.post('/notifications', protect, requireAdmin, async (req, res) => {
  try {
    const { document_id, user_id, type, title, body, read } = req.body || {};
    if (!document_id || !user_id || !type) {
      return res.status(400).json({ error: 'document_id, user_id, and type are required' });
    }
    const result = await pool.query(
      `INSERT INTO docutracker_notifications
       (document_id, user_id, type, title, body, read)
       VALUES ($1, $2, $3, $4, $5, COALESCE($6, false))
       RETURNING *`,
      [document_id, user_id, type, title || null, body || null, read]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[docutracker POST /notifications]', err);
    res.status(500).json({ error: 'Failed to create notification' });
  }
});

/**
 * PATCH /api/docutracker/notifications/:id/read
 * Marks a single notification read for the authenticated user.
 */
router.patch('/notifications/:id/read', protect, async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `UPDATE docutracker_notifications
       SET read = true
       WHERE id = $1 AND user_id = $2
       RETURNING *`,
      [id, req.user.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Notification not found' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('[docutracker PATCH /notifications/:id/read]', err);
    res.status(500).json({ error: 'Failed to update notification' });
  }
});

/**
 * GET /api/docutracker/escalation-configs
 */
router.get('/escalation-configs', protect, async (req, res) => {
  try {
    const { document_type, department_id } = req.query;
    const params = [];
    const where = [];
    let i = 1;
    if (document_type) {
      where.push(`document_type = $${i++}`);
      params.push(document_type);
    }
    if (department_id) {
      where.push(`(department_id = $${i}::uuid OR department_id IS NULL)`);
      params.push(department_id);
      i += 1;
    }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const result = await pool.query(
      `SELECT * FROM docutracker_escalation_configs ${whereSql} ORDER BY document_type, department_id NULLS LAST LIMIT 100`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    console.error('[docutracker GET /escalation-configs]', err);
    res.status(500).json({ error: 'Failed to fetch escalation configs' });
  }
});

/**
 * POST /api/docutracker/escalation-configs
 * Admin-only. Body: document_type, escalation_target_role, escalation_delay_minutes?,
 * max_escalation_level?, notify_original_sender?, department_id?
 */
router.post('/escalation-configs', protect, requireAdmin, async (req, res) => {
  try {
    const b = req.body || {};
    const documentType = String(b.document_type || '').trim();
    if (!documentType) {
      return res.status(400).json({ error: 'document_type is required' });
    }
    const targetRole = String(b.escalation_target_role || b.escalationTargetRole || '').trim();
    if (!targetRole) {
      return res.status(400).json({ error: 'escalation_target_role is required' });
    }
    const delayMinutes = Number(b.escalation_delay_minutes ?? b.escalationDelayMinutes ?? 60);
    const maxLevel = Number(b.max_escalation_level ?? b.maxEscalationLevel ?? 3);
    if (!Number.isFinite(delayMinutes) || delayMinutes < 1) {
      return res.status(400).json({ error: 'escalation_delay_minutes must be at least 1' });
    }
    if (!Number.isFinite(maxLevel) || maxLevel < 1) {
      return res.status(400).json({ error: 'max_escalation_level must be at least 1' });
    }
    const departmentId = b.department_id ?? b.departmentId ?? null;
    const notifyOriginal =
      b.notify_original_sender !== false && b.notifyOriginalSender !== false;

    const result = await pool.query(
      `INSERT INTO docutracker_escalation_configs
       (document_type, department_id, escalation_target_role, escalation_delay_minutes,
        max_escalation_level, notify_original_sender)
       VALUES ($1, $2::uuid, $3, $4, $5, $6)
       RETURNING *`,
      [
        documentType,
        departmentId || null,
        targetRole,
        Math.round(delayMinutes),
        Math.round(maxLevel),
        notifyOriginal,
      ]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[docutracker POST /escalation-configs]', err);
    res.status(500).json({ error: 'Failed to create escalation config' });
  }
});

/**
 * PATCH /api/docutracker/escalation-configs/:id
 * Admin-only.
 */
router.patch('/escalation-configs/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const b = req.body || {};
    const fields = [];
    const params = [];
    let i = 1;

    const setField = (col, val) => {
      fields.push(`${col} = $${i++}`);
      params.push(val);
    };

    if (b.document_type != null || b.documentType != null) {
      setField('document_type', String(b.document_type ?? b.documentType).trim());
    }
    if (b.department_id !== undefined || b.departmentId !== undefined) {
      const dept = b.department_id ?? b.departmentId;
      setField('department_id', dept || null);
    }
    if (b.escalation_target_role != null || b.escalationTargetRole != null) {
      setField(
        'escalation_target_role',
        String(b.escalation_target_role ?? b.escalationTargetRole).trim()
      );
    }
    if (b.escalation_delay_minutes != null || b.escalationDelayMinutes != null) {
      const n = Number(b.escalation_delay_minutes ?? b.escalationDelayMinutes);
      if (!Number.isFinite(n) || n < 1) {
        return res.status(400).json({ error: 'escalation_delay_minutes must be at least 1' });
      }
      setField('escalation_delay_minutes', Math.round(n));
    }
    if (b.max_escalation_level != null || b.maxEscalationLevel != null) {
      const n = Number(b.max_escalation_level ?? b.maxEscalationLevel);
      if (!Number.isFinite(n) || n < 1) {
        return res.status(400).json({ error: 'max_escalation_level must be at least 1' });
      }
      setField('max_escalation_level', Math.round(n));
    }
    if (b.notify_original_sender !== undefined || b.notifyOriginalSender !== undefined) {
      setField(
        'notify_original_sender',
        b.notify_original_sender !== false && b.notifyOriginalSender !== false
      );
    }

    if (fields.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    params.push(id);
    const result = await pool.query(
      `UPDATE docutracker_escalation_configs
       SET ${fields.join(', ')}, updated_at = now()
       WHERE id = $${i}::uuid
       RETURNING *`,
      params
    );
    if (!result.rows.length) {
      return res.status(404).json({ error: 'Escalation config not found' });
    }
    return res.json(result.rows[0]);
  } catch (err) {
    console.error('[docutracker PATCH /escalation-configs/:id]', err);
    res.status(500).json({ error: 'Failed to update escalation config' });
  }
});

/**
 * GET /api/docutracker/permission-records (raw rows for DocuTracker setup UI)
 */
router.get('/permission-records', protect, requireAdmin, async (req, res) => {
  try {
    const { role_id, user_id, document_type } = req.query;
    const params = [];
    const where = [];
    let i = 1;
    if (role_id) {
      where.push(`role_id = $${i++}`);
      params.push(role_id);
    }
    if (user_id) {
      where.push(`user_id = $${i++}::uuid`);
      params.push(user_id);
    }
    if (document_type != null && document_type !== '') {
      where.push(`document_type = $${i++}`);
      params.push(document_type);
    }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const result = await pool.query(
      `SELECT * FROM docutracker_permissions ${whereSql} ORDER BY document_type, action`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    console.error('[docutracker GET /permission-records]', err);
    res.status(500).json({ error: 'Failed to list permission records' });
  }
});

/**
 * GET /api/docutracker/documents/:id/history
 */
router.get('/documents/:id/history', protect, async (req, res) => {
  const { id } = req.params;
  try {
    if (!(await assertDocumentReadable(req, id))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const result = await pool.query(
      `SELECT h.*,
              COALESCE(NULLIF(h.actor_name, ''), u.full_name) AS actor_name
       FROM docutracker_document_history h
       LEFT JOIN users u ON u.id = h.actor_id
       WHERE document_id = $1
       ORDER BY h.created_at DESC`,
      [id]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('[docutracker GET /documents/:id/history]', err);
    res.status(500).json({ error: 'Failed to fetch history' });
  }
});

/**
 * POST /api/docutracker/documents/:id/history
 */
router.post('/documents/:id/history', protect, async (req, res) => {
  const { id } = req.params;
  try {
    if (!(await assertDocumentReadable(req, id))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const b = req.body || {};
    const result = await pool.query(
      `INSERT INTO docutracker_document_history
       (document_id, action, actor_id, actor_name, from_step, to_step, from_status, to_status, remarks,
        is_overdue_log, is_escalation_log, escalation_level)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
       RETURNING *`,
      [
        id,
        b.action || null,
        req.user.id,
        b.actor_name || req.user.full_name || req.user.name || null,
        b.from_step ?? null,
        b.to_step ?? null,
        b.from_status != null ? normalizeDocStatus(b.from_status) : null,
        b.to_status != null ? normalizeDocStatus(b.to_status) : null,
        b.remarks || null,
        !!b.is_overdue_log,
        !!b.is_escalation_log,
        b.escalation_level ?? null,
      ]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[docutracker POST /documents/:id/history]', err);
    res.status(500).json({ error: 'Failed to add history' });
  }
});

/**
 * PUT /api/docutracker/documents/:id — full update (Flutter client)
 */
router.put('/documents/:id', protect, async (req, res) => {
  const { id } = req.params;
  const b = req.body || {};
  try {
    if (!(await assertDocumentReadable(req, id))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    if (req.user?.role !== 'admin' && putBodyTouchesWorkflowFields(b)) {
      return res.status(403).json({
        error: 'Only administrators can change workflow fields on a document; use the transition API for routing.',
      });
    }
    const result = await pool.query(
      `UPDATE docutracker_documents SET
        document_number = COALESCE($1, document_number),
        document_type = COALESCE($2, document_type),
        title = COALESCE($3, title),
        description = $4,
        file_path = $5,
        file_name = $6,
        current_holder_id = $7,
        current_step = COALESCE($8, current_step),
        status = COALESCE($9, status),
        sent_time = $10,
        deadline_time = $11,
        reviewed_time = $12,
        escalation_level = COALESCE($13, escalation_level),
        needs_admin_intervention = COALESCE($14, needs_admin_intervention),
        updated_at = now()
       WHERE id = $15
       RETURNING *`,
      [
        b.document_number ?? null,
        b.document_type ?? null,
        b.title ?? null,
        b.description !== undefined ? b.description : null,
        b.file_path !== undefined ? b.file_path : null,
        b.file_name !== undefined ? b.file_name : null,
        b.current_holder_id !== undefined ? b.current_holder_id : null,
        b.current_step ?? null,
        b.status != null ? normalizeDocStatus(b.status) : null,
        b.sent_time ?? null,
        b.deadline_time ?? null,
        b.reviewed_time ?? null,
        b.escalation_level ?? null,
        b.needs_admin_intervention !== undefined ? !!b.needs_admin_intervention : null,
        id,
      ]
    );
    if (!result.rows[0]) {
      return res.status(404).json({ error: 'Document not found' });
    }
    res.json(mapDocumentRow(result.rows[0]));
  } catch (err) {
    console.error('[docutracker PUT /documents/:id]', err);
    res.status(500).json({ error: 'Failed to update document' });
  }
});

/**
 * GET /api/docutracker/documents/:id
 * Returns document + routing records + history.
 */
router.get('/documents/:id', protect, async (req, res) => {
  const { id } = req.params;
  try {
    if (!(await assertDocumentReadable(req, id))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const docResult = await pool.query(
      `SELECT d.*, creator.full_name AS creator_name
       FROM docutracker_documents d
       LEFT JOIN users creator ON creator.id = d.created_by
       WHERE d.id = $1`,
      [id]
    );
    const docRow = docResult.rows[0];
    if (!docRow) {
      return res.status(404).json({ error: 'Document not found' });
    }

    const [routingResult, historyResult] = await Promise.all([
      pool.query(
        `SELECT rr.*,
                COALESCE(
                  ARRAY_AGG(a.user_id) FILTER (WHERE a.user_id IS NOT NULL),
                  '{}'::uuid[]
                ) AS assignee_ids,
                COALESCE(
                  ARRAY_AGG(u.full_name) FILTER (WHERE u.full_name IS NOT NULL),
                  '{}'::text[]
                ) AS assignee_names
         FROM docutracker_routing_records rr
         LEFT JOIN docutracker_routing_record_assignees a
           ON a.routing_record_id = rr.id
         LEFT JOIN users u
           ON u.id = a.user_id
         WHERE rr.document_id = $1
         GROUP BY rr.id
         ORDER BY rr.step_order ASC`,
        [id]
      ),
      pool.query(
        `SELECT h.*,
                COALESCE(NULLIF(h.actor_name, ''), u.full_name) AS actor_name
         FROM docutracker_document_history h
         LEFT JOIN users u ON u.id = h.actor_id
         WHERE document_id = $1
         ORDER BY h.created_at ASC`,
        [id]
      ),
    ]);

    res.json({
      document: mapDocumentRow(docRow),
      routing: routingResult.rows,
      history: historyResult.rows,
    });
  } catch (err) {
    console.error('[docutracker GET /documents/:id]', err);
    res.status(500).json({ error: 'Failed to fetch document' });
  }
});

/**
 * GET /api/docutracker/permission-explain
 *
 * Query:
 * - document_type (required)
 * - action (required)
 * - document_id (optional) -> enables workflow checks + relationship checks
 *
 * Returns an explanation of the effective decision for the CURRENT user.
 */
router.get('/permission-explain', protect, async (req, res) => {
  try {
    const document_type = String(req.query.document_type || '').trim();
    const action = String(req.query.action || '').trim();
    const document_id = String(req.query.document_id || '').trim();
    if (!document_type || !action) {
      return res.status(400).json({ error: 'document_type and action are required' });
    }

    let document = null;
    if (document_id) {
      if (!(await assertDocumentReadable(req, document_id))) {
        return res.status(403).json({ error: 'Forbidden' });
      }
      const docRes = await pool.query(`SELECT * FROM docutracker_documents WHERE id = $1`, [document_id]);
      document = docRes.rows?.[0] || null;
      if (!document) return res.status(404).json({ error: 'Document not found' });
    }

    const exp = await getEffectivePermissionExplanation(pool, {
      user: req.user,
      action,
      documentType: document_type,
      document,
    });
    return res.json(exp);
  } catch (err) {
    console.error('[docutracker GET /permission-explain]', err);
    return res.status(500).json({ error: 'Failed to explain permission' });
  }
});

/**
 * PATCH /api/docutracker/documents/:id
 * Allows updating status, current_holder_id, current_step and optional remarks.
 * Body: { status?, current_holder_id?, current_step?, remarks?, needs_admin_intervention? }
 * Admin-only (same fields are workflow-sensitive).
 */
router.patch('/documents/:id', protect, requireAdmin, async (req, res) => {
  const { id } = req.params;
  const {
    status,
    current_holder_id,
    current_step,
    remarks,
    needs_admin_intervention,
  } = req.body || {};

  if (
    status === undefined &&
    current_holder_id === undefined &&
    current_step === undefined &&
    needs_admin_intervention === undefined
  ) {
    return res.status(400).json({ error: 'No fields to update' });
  }

  try {
    // fetch current values for history
    const existingResult = await pool.query(
      'SELECT status, current_step FROM docutracker_documents WHERE id = $1',
      [id]
    );
    const existing = existingResult.rows[0];
    if (!existing) {
      return res.status(404).json({ error: 'Document not found' });
    }

    const updates = [];
    const values = [];
    let i = 1;

    if (status !== undefined) {
      updates.push(`status = $${i++}`);
      values.push(normalizeDocStatus(status));
    }
    if (current_holder_id !== undefined) {
      updates.push(`current_holder_id = $${i++}`);
      values.push(current_holder_id || null);
    }
    if (current_step !== undefined) {
      updates.push(`current_step = $${i++}`);
      values.push(current_step);
    }
    if (needs_admin_intervention !== undefined) {
      updates.push(`needs_admin_intervention = $${i++}`);
      values.push(!!needs_admin_intervention);
    }

    if (!updates.length) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }

    updates.push('updated_at = now()');

    values.push(id);

    const updateResult = await pool.query(
      `UPDATE docutracker_documents
       SET ${updates.join(', ')}
       WHERE id = $${i}
       RETURNING *`,
      values
    );

    const updated = updateResult.rows[0];

    await pool.query(
      `INSERT INTO docutracker_document_history
       (document_id, action, actor_id, from_step, to_step, from_status, to_status, remarks)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        id,
        'update',
        req.user.id,
        existing.current_step,
        updated.current_step,
        existing.status,
        updated.status,
        remarks || null,
      ]
    );

    res.json(mapDocumentRow(updated));
  } catch (err) {
    console.error('[docutracker PATCH /documents/:id]', err);
    res.status(500).json({ error: 'Failed to update document' });
  }
});

/**
 * GET /api/docutracker/routing-configs
 * Optional query: document_type
 */
router.get('/routing-configs', protect, async (req, res) => {
  try {
    const { document_type } = req.query;
    const params = [];
    let where = '';
    if (document_type) {
      where = 'WHERE v.document_type = $1';
      params.push(document_type);
    }

    // Return the latest (highest) version per document_type.
    const result = await pool.query(
      `SELECT v.document_type,
              v.steps,
              v.review_deadline_hours,
              v.version
       FROM docutracker_routing_config_versions v
       JOIN (
         SELECT document_type, MAX(version) AS version
         FROM docutracker_routing_config_versions
         GROUP BY document_type
       ) latest
         ON latest.document_type = v.document_type
        AND latest.version = v.version
       ${where}
       ORDER BY v.document_type`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    console.error('[docutracker GET /routing-configs]', err);
    res.status(500).json({ error: 'Failed to fetch routing configs' });
  }
});

/**
 * POST /api/docutracker/routing-configs
 * Admin-only.
 * Body: { document_type, steps, review_deadline_hours? }
 */
router.post('/routing-configs', protect, requireAdmin, async (req, res) => {
  try {
    const { document_type, steps, review_deadline_hours } = req.body || {};
    if (!document_type || !Array.isArray(steps)) {
      return res.status(400).json({ error: 'document_type and steps[] are required' });
    }

    // Validate step structure before saving (basic guards).
    const normalizedSteps = steps
      .map((s) => ({
        step_order: Number(s.step_order ?? s.stepOrder ?? 0),
        assignee_type: String(s.assignee_type ?? s.assigneeType ?? '').trim().toLowerCase(),
        role_id: s.role_id ?? s.roleId ?? null,
        department_id: s.department_id ?? s.departmentId ?? null,
        user_ids: Array.isArray(s.user_ids) ? s.user_ids : Array.isArray(s.userIds) ? s.userIds : null,
        label: s.label ?? null,
        enabled: s.enabled !== false,
        deadline_hours:
          s.deadline_hours != null
            ? Number(s.deadline_hours)
            : s.deadlineHours != null
              ? Number(s.deadlineHours)
              : null,
      }))
      .filter((s) => Number.isFinite(s.step_order) && s.step_order > 0)
      .sort((a, b) => a.step_order - b.step_order);

    if (normalizedSteps.length === 0) {
      return res.status(400).json({ error: 'Workflow must have at least 1 step.' });
    }
    if (normalizedSteps[0].step_order !== 1) {
      return res.status(400).json({ error: 'Workflow must start at step 1.' });
    }
    for (let i = 1; i < normalizedSteps.length; i += 1) {
      if (normalizedSteps[i].step_order !== normalizedSteps[i - 1].step_order + 1) {
        return res.status(400).json({ error: 'Step numbers must be contiguous (no gaps).' });
      }
    }
    // Validate enabled + assignee config for enabled steps.
    if (!normalizedSteps.some((s) => s.enabled)) {
      return res.status(400).json({ error: 'At least one step must be enabled.' });
    }
    for (const s of normalizedSteps) {
      if (!s.enabled) continue;
      if (!['user', 'role', 'department', 'office'].includes(s.assignee_type)) {
        return res.status(400).json({ error: `Invalid assignee_type for step ${s.step_order}.` });
      }
      // Selected-person workflow enforcement: enabled steps must be explicit user assignments.
      if (s.assignee_type !== 'user') {
        return res.status(400).json({
          error: `Step ${s.step_order} must route to specific user(s) (assignee_type='user') for workflow actions.`,
        });
      }
      if (s.deadline_hours != null && (!Number.isFinite(s.deadline_hours) || s.deadline_hours <= 0)) {
        return res.status(400).json({ error: `Invalid deadline_hours for step ${s.step_order}.` });
      }
      if (s.assignee_type === 'user') {
        const ids = Array.isArray(s.user_ids) ? s.user_ids.filter(Boolean) : [];
        if (ids.length === 0) {
          return res.status(400).json({ error: `User step ${s.step_order} must include user_ids.` });
        }
      }
      if (s.assignee_type === 'role' && !s.role_id) {
        return res.status(400).json({ error: `Role step ${s.step_order} must include role_id.` });
      }
      if (s.assignee_type === 'department' && !s.department_id) {
        return res.status(400).json({ error: `Department step ${s.step_order} must include department_id.` });
      }
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // If a "user" step provides a department_id, enforce that the PRIMARY user
      // currently belongs to that department (active assignment).
      // Backup users are admin-curated selections and bypass the department constraint.
      for (const s of normalizedSteps) {
        if (!s.enabled) continue;
        const ids = Array.isArray(s.user_ids) ? s.user_ids.filter(Boolean) : [];
        if (!ids.length) continue;

        // Inactive users cannot be assigned (check ALL users: primary + backups).
        const activeRes = await client.query(
          `SELECT id::text AS id
           FROM users
           WHERE id = ANY($1::uuid[])
             AND (is_active IS NULL OR is_active = true)`,
          [ids]
        );
        const active = new Set((activeRes.rows || []).map((r) => r.id));
        const inactive = ids.filter((id) => !active.has(String(id)));
        if (inactive.length) {
          return res.status(400).json({
            error: `Step ${s.step_order} contains inactive users.`,
            inactive_user_ids: inactive,
          });
        }

        // Department membership: only validate the PRIMARY user (first in list).
        if (s.assignee_type !== 'user') continue;
        const deptId = s.department_id;
        if (!deptId) continue;
        const primaryId = ids[0]; // Only the primary user is department-scoped.
        const r = await client.query(
          `SELECT u.id::text AS id
           FROM users u
           JOIN assignments a
             ON a.employee_id = u.id
           WHERE a.department_id = $1::uuid
             AND u.id = $2::uuid
             AND (a.is_active IS NULL OR a.is_active = true)
             AND a.effective_from <= CURRENT_DATE
             AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
             AND (u.is_active IS NULL OR u.is_active = true)`,
          [deptId, primaryId]
        );
        if (r.rowCount === 0) {
          return res.status(400).json({
            error: `The primary user for step ${s.step_order} is not assigned to the selected department.`,
            invalid_user_ids: [primaryId],
            department_id: deptId,
          });
        }
      }

      const nextVersionRes = await client.query(
        `SELECT COALESCE(MAX(version), 0)::int + 1 AS next_version
         FROM docutracker_routing_config_versions
         WHERE document_type = $1`,
        [document_type]
      );
      const nextVersion = nextVersionRes.rows?.[0]?.next_version ?? 1;
      const prevVersion = nextVersion > 1 ? nextVersion - 1 : null;

      /** Preserve per-user allowed_actions from the previous workflow version. */
      const preservedActionsByStepUser = new Map();
      if (prevVersion != null) {
        const prevAssigneesRes = await client.query(
          `SELECT ws.step_order,
                  wsa.user_id::text AS user_id,
                  wsa.allowed_actions
           FROM docutracker_workflow_step_assignees wsa
           JOIN docutracker_workflow_steps ws ON ws.id = wsa.step_id
           WHERE ws.document_type = $1
             AND ws.workflow_version = $2`,
          [document_type, prevVersion]
        );
        for (const row of prevAssigneesRes.rows || []) {
          const key = `${row.step_order}:${row.user_id}`;
          if (Array.isArray(row.allowed_actions) && row.allowed_actions.length) {
            preservedActionsByStepUser.set(key, row.allowed_actions);
          }
        }
      }

      const vRes = await client.query(
        `INSERT INTO docutracker_routing_config_versions
         (document_type, version, steps, review_deadline_hours, created_by)
         VALUES ($1, $2, $3::jsonb, COALESCE($4, 1), $5)
         RETURNING document_type, steps, review_deadline_hours, version`,
        [
          document_type,
          nextVersion,
          JSON.stringify(normalizedSteps),
          review_deadline_hours ?? null,
          req.user?.id ?? null,
        ]
      );

      await upsertLatestRoutingConfigCache(client, {
        documentType: document_type,
        stepsJson: JSON.stringify(normalizedSteps),
        reviewDeadlineHours: review_deadline_hours ?? null,
      });

      // Write normalized workflow steps + assignees for this new version.
      // This makes step-level "selected persons per department" the durable source of truth.
      // Safe to rerun: we clear previous rows for (document_type, version) then reinsert.
      await client.query(
        `DELETE FROM docutracker_workflow_steps
         WHERE document_type = $1
           AND workflow_version = $2`,
        [document_type, nextVersion]
      );

      const stepIdByOrder = new Map();
      for (const s of normalizedSteps) {
        const ins = await client.query(
          `INSERT INTO docutracker_workflow_steps
           (document_type, workflow_version, step_order, department_id, label, enabled)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING id`,
          [
            document_type,
            nextVersion,
            s.step_order,
            s.department_id || null, // null is fine; no ::uuid cast needed for null
            s.label || null,
            s.enabled !== false,
          ]
        );
        stepIdByOrder.set(s.step_order, ins.rows?.[0]?.id);
      }

      for (const s of normalizedSteps) {
        if (s.assignee_type !== 'user') continue;
        const stepId = stepIdByOrder.get(s.step_order);
        if (!stepId) continue;
        const ids = Array.isArray(s.user_ids) ? s.user_ids.map(String).map((x) => x.trim()).filter(Boolean) : [];
        if (!ids.length) continue;

        for (let i = 0; i < ids.length; i += 1) {
          const uid = ids[i];
          const isPrimary = i === 0;
          const backupRank = isPrimary ? null : i; // 1..N for backups
          const preserveKey = `${s.step_order}:${uid}`;
          const preserved = preservedActionsByStepUser.get(preserveKey);
          const allowedActions =
            Array.isArray(preserved) && preserved.length
              ? preserved
              : ['approve', 'forward', 'reject', 'return'];
          await client.query(
            `INSERT INTO docutracker_workflow_step_assignees
             (step_id, user_id, is_primary, backup_rank, is_enabled, allowed_actions)
             VALUES ($1, $2::uuid, $3, $4, true, $5::text[])`,
            [stepId, uid, isPrimary, backupRank, allowedActions]
          );
        }
      }

      await client.query('COMMIT');
      res.status(201).json(vRes.rows[0]);
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('[docutracker POST /routing-configs] error:', err?.message || err);
    console.error('[docutracker POST /routing-configs] stack:', err?.stack);
    res.status(500).json({ error: err?.message || 'Failed to save routing config' });
  }
});

/**
 * GET /api/docutracker/workflow-steps
 * Admin-only.
 *
 * Query:
 * - document_type (required)
 * - workflow_version (required)
 *
 * Returns steps + assignees from normalized tables.
 */
router.get('/workflow-steps', protect, requireAdmin, async (req, res) => {
  try {
    const document_type = String(req.query.document_type || '').trim();
    const workflow_version = Number(req.query.workflow_version);
    if (!document_type || !Number.isFinite(workflow_version) || workflow_version < 1) {
      return res.status(400).json({ error: 'document_type and workflow_version are required' });
    }

    const r = await pool.query(
      `SELECT
         s.id AS step_id,
         s.document_type,
         s.workflow_version,
         s.step_order,
         s.department_id,
         s.label,
         s.enabled,
         COALESCE(
           jsonb_agg(
             jsonb_build_object(
               'id', a.id,
               'user_id', a.user_id,
               'full_name', u.full_name,
               'department_name', cur.current_department_name,
               'is_primary', a.is_primary,
               'backup_rank', a.backup_rank,
               'is_enabled', a.is_enabled,
               'allowed_actions', a.allowed_actions
             )
             ORDER BY a.is_primary DESC, a.backup_rank ASC NULLS LAST, u.full_name NULLS LAST
           ) FILTER (WHERE a.id IS NOT NULL),
           '[]'::jsonb
         ) AS assignees
       FROM docutracker_workflow_steps s
       LEFT JOIN docutracker_workflow_step_assignees a
         ON a.step_id = s.id
       LEFT JOIN users u
         ON u.id = a.user_id
       LEFT JOIN LATERAL (
         SELECT d.name AS current_department_name
         FROM assignments asn
         LEFT JOIN departments d ON d.id = asn.department_id
         WHERE asn.employee_id = u.id
           AND (asn.is_active IS NULL OR asn.is_active = true)
           AND asn.effective_from <= CURRENT_DATE
           AND (asn.effective_to IS NULL OR asn.effective_to >= CURRENT_DATE)
         ORDER BY asn.effective_from DESC
         LIMIT 1
       ) cur ON true
       WHERE s.document_type = $1
         AND s.workflow_version = $2
       GROUP BY s.id
       ORDER BY s.step_order ASC`,
      [document_type, workflow_version]
    );

    return res.json(r.rows);
  } catch (err) {
    console.error('[docutracker GET /workflow-steps]', err);
    return res.status(500).json({ error: 'Failed to fetch workflow steps' });
  }
});

/**
 * PUT /api/docutracker/workflow-steps/:stepId/assignees
 * Admin-only.
 *
 * Body:
 * {
 *   assignees: [
 *     {
 *       user_id: uuid,
 *       is_primary: boolean,
 *       backup_rank: int|null,
 *       is_enabled: boolean,
 *       allowed_actions: string[]
 *     }
 *   ]
 * }
 *
 * Replaces the assignee set for the step.
 */
router.put('/workflow-steps/:stepId/assignees', protect, requireAdmin, async (req, res) => {
  const stepId = String(req.params.stepId || '').trim();
  try {
    if (!stepId) return res.status(400).json({ error: 'stepId is required' });
    const body = req.body || {};
    const input = Array.isArray(body.assignees) ? body.assignees : null;
    if (!input) return res.status(400).json({ error: 'assignees[] is required' });

    const allowedActionSet = new Set(['approve', 'forward', 'reject', 'return']);
    const normalized = input
      .map((a) => ({
        user_id: a.user_id ?? a.userId ?? null,
        is_primary: a.is_primary === true || a.isPrimary === true,
        backup_rank:
          a.backup_rank != null
            ? Number(a.backup_rank)
            : a.backupRank != null
              ? Number(a.backupRank)
              : null,
        is_enabled: a.is_enabled !== false && a.isEnabled !== false,
        allowed_actions: Array.isArray(a.allowed_actions)
          ? a.allowed_actions
          : Array.isArray(a.allowedActions)
            ? a.allowedActions
            : [],
      }))
      .filter((a) => typeof a.user_id === 'string' && a.user_id.trim().length > 0);

    // Basic validation: at most one primary; ranks unique; actions whitelisted.
    if (normalized.length === 0) {
      return res.status(400).json({ error: 'Each step must have at least one assigned user.' });
    }
    const primaries = normalized.filter((a) => a.is_primary);
    if (primaries.length !== 1) {
      return res.status(400).json({ error: 'Each step must have exactly one primary assignee.' });
    }
    const seenRanks = new Set();
    const seenUsers = new Set();
    for (const a of normalized) {
      const uid = String(a.user_id).trim();
      if (seenUsers.has(uid)) {
        return res.status(400).json({ error: 'Duplicate user_id in assignees.' });
      }
      seenUsers.add(uid);
      if (a.is_primary && a.backup_rank != null) {
        return res.status(400).json({ error: 'Primary assignee must not have backup_rank.' });
      }
      if (!a.is_primary) {
        if (!Number.isFinite(a.backup_rank) || a.backup_rank <= 0) {
          return res.status(400).json({ error: 'Backup assignees require backup_rank >= 1.' });
        }
        if (seenRanks.has(a.backup_rank)) {
          return res.status(400).json({ error: 'Duplicate backup_rank in assignees.' });
        }
        seenRanks.add(a.backup_rank);
      }
      const deduped = Array.from(new Set(a.allowed_actions.map((x) => String(x).trim()).filter(Boolean)));
      for (const act of deduped) {
        if (!allowedActionSet.has(act)) {
          return res.status(400).json({ error: `Invalid allowed action '${act}'.` });
        }
      }
      a.allowed_actions = deduped;
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const stepExists = await client.query(
        `SELECT id, department_id
         FROM docutracker_workflow_steps
         WHERE id = $1::uuid
         LIMIT 1`,
        [stepId]
      );
      if (!stepExists.rowCount) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Workflow step not found' });
      }
      const deptId = stepExists.rows[0]?.department_id || null;

      // Ensure assigned users are active.
      const ids = normalized.map((a) => String(a.user_id).trim());
      const activeRes = await client.query(
        `SELECT id::text AS id
         FROM users
         WHERE id = ANY($1::uuid[])
           AND (is_active IS NULL OR is_active = true)`,
        [ids]
      );
      const active = new Set((activeRes.rows || []).map((r) => r.id));
      const inactive = ids.filter((id) => !active.has(String(id)));
      if (inactive.length) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          error: 'Inactive users cannot be assigned.',
          inactive_user_ids: inactive,
        });
      }

      // If the step is department-scoped, ensure every assigned user currently belongs to that department.
      if (deptId) {
        const deptRes = await client.query(
          `SELECT u.id::text AS id
           FROM users u
           JOIN assignments a
             ON a.employee_id = u.id
           WHERE a.department_id = $1::uuid
             AND u.id = ANY($2::uuid[])
             AND (a.is_active IS NULL OR a.is_active = true)
             AND a.effective_from <= CURRENT_DATE
             AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
             AND (u.is_active IS NULL OR u.is_active = true)`,
          [deptId, ids]
        );
        const allowed = new Set((deptRes.rows || []).map((x) => x.id));
        const invalid = ids.filter((id) => !allowed.has(String(id)));
        if (invalid.length) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: 'Assigned users must belong to the step department.',
            invalid_user_ids: invalid,
            department_id: deptId,
          });
        }
      }

      await client.query(
        `DELETE FROM docutracker_workflow_step_assignees WHERE step_id = $1::uuid`,
        [stepId]
      );

      for (const a of normalized) {
        await client.query(
          `INSERT INTO docutracker_workflow_step_assignees
             (step_id, user_id, is_primary, backup_rank, is_enabled, allowed_actions)
           VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6::text[])`,
          [stepId, a.user_id, a.is_primary, a.backup_rank, a.is_enabled, a.allowed_actions]
        );
      }

      await client.query('COMMIT');
      return res.json({ ok: true, step_id: stepId, updated: normalized.length });
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('[docutracker PUT /workflow-steps/:stepId/assignees]', err);
    return res.status(500).json({ error: 'Failed to update step assignees' });
  }
});

/**
 * GET /api/docutracker/permissions
 * Admin-only.
 *
 * Query:
 * - document_type (required)
 * - action (optional, default: 'view')
 * - search (optional, matches employee name or email)
 *
 * Returns a list of employees, each with a boolean "granted" for the given
 * document_type + action, so the frontend can render checkboxes.
 */
router.get('/permissions', protect, requireAdmin, async (req, res) => {
  try {
    const { document_type, action = 'view', search } = req.query;
    const normalizedAction = normalizeGeneralPermissionAction(action);
    const actionVariants = generalPermissionActionVariants(normalizedAction);
    if (!document_type) {
      return res.status(400).json({ error: 'document_type is required' });
    }
    if (!GENERAL_PERMISSION_ACTIONS.has(String(normalizedAction))) {
      return res.status(400).json({
        error: `Invalid action '${action}'. Role-based permissions only support: ${Array.from(
          GENERAL_PERMISSION_ACTIONS
        ).join(', ')}`,
      });
    }

    const params = [document_type, actionVariants, normalizedAction];
    const where = [];
    let i = 4;

    // only active employees by default
    where.push('(u.is_active IS NULL OR u.is_active = true)');

    if (search) {
      where.push(`(u.full_name ILIKE $${i} OR u.email ILIKE $${i})`);
      params.push(`%${search}%`);
      i += 1;
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const result = await pool.query(
      `SELECT
         u.id AS user_id,
         u.full_name,
         u.email,
         u.role,
         COALESCE(u.is_active, true) AS is_active,
         p.id AS permission_id,
        p.action AS permission_action,
         COALESCE(p.granted, false) AS granted
       FROM users u
       LEFT JOIN LATERAL (
         SELECT pp.id, pp.action, pp.granted
         FROM docutracker_permissions pp
         WHERE pp.user_id = u.id
           AND pp.document_type = $1
           AND pp.action = ANY($2::text[])
         ORDER BY
           CASE WHEN pp.action = $3 THEN 0 ELSE 1 END,
           pp.updated_at DESC NULLS LAST,
           pp.created_at DESC NULLS LAST
         LIMIT 1
       ) p ON true
       ${whereSql}
       ORDER BY u.full_name`,
      params
    );

    res.json(
      result.rows.map((r) => ({
        user_id: r.user_id,
        full_name: r.full_name ?? 'Unknown',
        email: r.email,
        role: r.role ?? 'employee',
        is_active: r.is_active,
        permission_id: r.permission_id,
        permission_action: r.permission_action,
        granted: r.granted,
      }))
    );
  } catch (err) {
    console.error('[docutracker GET /permissions]', err);
    res.status(500).json({ error: 'Failed to fetch permissions' });
  }
});

/**
 * POST /api/docutracker/permissions
 * Admin-only.
 *
 * Body:
 * {
 *   user_id,
 *   document_type,
 *   action,        // e.g. 'view', 'approve', 'edit'
 *   granted        // boolean
 * }
 *
 * This is designed for checkbox-style toggling in the UI.
 */
router.post('/permissions', protect, requireAdmin, async (req, res) => {
  try {
    const { user_id, role_id, document_type, action, granted } = req.body || {};

    if ((!user_id && !role_id) || !document_type || !action) {
      return res.status(400).json({
        error: 'document_type and action are required, plus user_id or role_id',
      });
    }
    const normalizedAction = normalizeGeneralPermissionAction(action);
    const actionVariants = generalPermissionActionVariants(normalizedAction);
    if (!GENERAL_PERMISSION_ACTIONS.has(String(normalizedAction))) {
      return res.status(400).json({
        error: `Invalid action '${action}'. Role-based permissions only support: ${Array.from(
          GENERAL_PERMISSION_ACTIONS
        ).join(', ')}`,
      });
    }

    const grantedBool = !!granted;

    const existing = await pool.query(
      user_id
        ? `SELECT id FROM docutracker_permissions
           WHERE user_id = $1 AND document_type = $2 AND action = ANY($3::text[])`
        : `SELECT id FROM docutracker_permissions
           WHERE role_id = $1 AND user_id IS NULL AND document_type = $2 AND action = ANY($3::text[])`,
      user_id ? [user_id, document_type, actionVariants] : [role_id, document_type, actionVariants]
    );

    let row;
    if (existing.rowCount > 0) {
      const permId = existing.rows[0].id;
      const update = await pool.query(
        `UPDATE docutracker_permissions
         SET granted = $1,
             action = $3,
             updated_at = now()
         WHERE id = $2
         RETURNING *`,
        [grantedBool, permId, normalizedAction]
      );
      row = update.rows[0];
    } else {
      const insert = await pool.query(
        `INSERT INTO docutracker_permissions
           (user_id, role_id, document_type, action, granted)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [user_id || null, role_id || null, document_type, normalizedAction, grantedBool]
      );
      row = insert.rows[0];
    }

    res.status(201).json({
      id: row.id,
      user_id: row.user_id,
      role_id: row.role_id,
      document_type: row.document_type,
      action: row.action,
      granted: row.granted,
    });
  } catch (err) {
    console.error('[docutracker POST /permissions]', err);
    res.status(500).json({ error: 'Failed to update permission' });
  }
});

/**
 * DELETE /api/docutracker/permissions
 * Admin-only.
 *
 * Body:
 * {
 *   user_id?: uuid,
 *   role_id?: text,
 *   document_type: text,   // '*' or specific
 *   action?: text          // optional: delete only one action
 * }
 *
 * Deletes explicit permission rows so the system falls back to defaults.
 */
router.delete('/permissions', protect, requireAdmin, async (req, res) => {
  try {
    const { user_id, role_id, document_type, action } = req.body || {};
    if ((!user_id && !role_id) || !document_type) {
      return res.status(400).json({
        error: 'document_type is required, plus user_id or role_id',
      });
    }
    if (user_id && role_id) {
      return res.status(400).json({
        error: 'Provide only one scope: user_id OR role_id',
      });
    }

    const params = [];
    const where = [];
    let i = 1;

    if (user_id) {
      where.push(`user_id = $${i++}::uuid`);
      params.push(user_id);
    } else {
      where.push(`role_id = $${i++}`);
      params.push(role_id);
      where.push(`user_id IS NULL`);
    }

    where.push(`document_type = $${i++}`);
    params.push(document_type);

    if (action) {
      const normalizedAction = normalizeGeneralPermissionAction(action);
      if (!GENERAL_PERMISSION_ACTIONS.has(String(normalizedAction))) {
        return res.status(400).json({
          error: `Invalid action '${action}'. Role-based permissions only support: ${Array.from(
            GENERAL_PERMISSION_ACTIONS
          ).join(', ')}`,
        });
      }
      where.push(`action = $${i++}`);
      params.push(normalizedAction);
    }

    const sql = `DELETE FROM docutracker_permissions WHERE ${where.join(' AND ')}`;
    const result = await pool.query(sql, params);
    res.json({ deleted: result.rowCount || 0 });
  } catch (err) {
    console.error('[docutracker DELETE /permissions]', err);
    res.status(500).json({ error: 'Failed to reset permissions' });
  }
});

function mapWorkflowServiceError(err) {
  const code = err?.code;
  if (code === 'FORBIDDEN') return { status: 403, error: err.message || 'Forbidden' };
  if (code === 'NOT_FOUND') return { status: 404, error: err.message || 'Not found' };
  if (code === 'VALIDATION') {
    return { status: 400, error: err.message || 'Request could not be completed.' };
  }
  return { status: 500, error: err?.message || 'Internal server error' };
}

/**
 * POST /api/docutracker/documents/:id/transition
 *
 * Body:
 * {
 *   action: 'submit' | 'forward' | 'approve' | 'reject' | 'return',
 *   remarks?: string,
 *   target_holder_id?: uuid,
 *   idempotency_key?: string
 * }
 *
 * Runs the workflow transition transactionally:
 * - updates docutracker_documents
 * - creates/updates docutracker_routing_records
 * - inserts docutracker_document_history
 * - inserts docutracker_notifications (with event_key + dedupe)
 * - stores docutracker_transition_requests when idempotency_key is supplied
 */
router.post('/documents/:id/transition', protect, async (req, res) => {
  const { id } = req.params;
  const b = req.body || {};
  try {
    const action = String(b.action || '').trim();
    if (!action) return res.status(400).json({ error: 'action is required' });

    const updated = await transitionDocument(pool, req.user, id, action, {
      remarks: b.remarks,
      target_holder_id: b.target_holder_id,
      current_holder_id: b.current_holder_id,
      idempotency_key: b.idempotency_key,
    });
    return res.json(updated);
  } catch (err) {
    console.error('[docutracker POST /documents/:id/transition]', err);
    const mapped = mapWorkflowServiceError(err);
    return res.status(mapped.status).json({ error: mapped.error });
  }
});

/**
 * POST /api/docutracker/documents/:id/remark
 *
 * Body:
 * { remarks: string }
 *
 * Inserts an audit trail "remark" entry in a DB transaction.
 */
router.post('/documents/:id/remark', protect, async (req, res) => {
  const { id } = req.params;
  const b = req.body || {};
  try {
    const ok = await addDocumentRemark(pool, req.user, id, { remarks: b.remarks });
    return res.status(201).json({ ok: !!ok });
  } catch (err) {
    console.error('[docutracker POST /documents/:id/remark]', err);
    const mapped = mapWorkflowServiceError(err);
    return res.status(mapped.status).json({ error: mapped.error });
  }
});

/**
 * POST /api/docutracker/documents/:id/attachment
 * multipart/form-data: file (PDF, JPG, JPEG, PNG; max 10MB)
 */
router.post('/documents/:id/attachment', protect, uploadDocutrackerAttachmentMw, async (req, res) => {
  const { id } = req.params;
  try {
    if (!req.file) {
      return res.status(400).json({
        error: 'No file uploaded. Allowed: PDF, JPG, JPEG, PNG (max 10MB).',
      });
    }
    const docRow = await loadDocumentRowForAccess(id);
    if (!docRow) return res.status(404).json({ error: 'Document not found' });
    if (!(await assertDocumentReadable(req, id))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    if (!(await canModifyDocumentAttachment(pool, docRow, req.user))) {
      return res.status(403).json({ error: 'You do not have permission to attach a file.' });
    }

    const relPath = `${DOCUTRACKER_ATTACHMENT_SUBDIR}/${req.file.filename}`;
    if (docRow.file_path) {
      const oldPath = path.join(UPLOAD_DIR, docRow.file_path);
      if (fs.existsSync(oldPath)) fs.unlinkSync(oldPath);
    }

    const updated = await pool.query(
      `UPDATE docutracker_documents
       SET file_path = $1, file_name = $2, updated_at = NOW()
       WHERE id = $3
       RETURNING *`,
      [relPath, req.file.originalname || req.file.filename, id]
    );

    return res.json(mapDocumentRow(updated.rows[0]));
  } catch (err) {
    console.error('[docutracker POST /documents/:id/attachment]', err);
    res.status(500).json({ error: 'Failed to upload attachment' });
  }
});

/**
 * DELETE /api/docutracker/documents/:id/attachment
 */
router.delete('/documents/:id/attachment', protect, async (req, res) => {
  const { id } = req.params;
  try {
    const docRow = await loadDocumentRowForAccess(id);
    if (!docRow) return res.status(404).json({ error: 'Document not found' });
    if (!(await assertDocumentReadable(req, id))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    if (!(await canModifyDocumentAttachment(pool, docRow, req.user))) {
      return res.status(403).json({ error: 'You do not have permission to remove the file.' });
    }
    if (docRow.file_path) {
      const filePath = path.join(UPLOAD_DIR, docRow.file_path);
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    }
    const updated = await pool.query(
      `UPDATE docutracker_documents
       SET file_path = NULL, file_name = NULL, updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [id]
    );
    return res.json(mapDocumentRow(updated.rows[0]));
  } catch (err) {
    console.error('[docutracker DELETE /documents/:id/attachment]', err);
    res.status(500).json({ error: 'Failed to remove attachment' });
  }
});

/**
 * GET /api/docutracker/documents/:id/attachment
 * Download / inline view (requires view or download permission).
 */
router.get('/documents/:id/attachment', protect, async (req, res) => {
  const { id } = req.params;
  try {
    const docRow = await loadDocumentRowForAccess(id);
    if (!docRow) return res.status(404).json({ error: 'Document not found' });
    if (!(await canDownloadDocumentFile(pool, docRow, req.user))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    if (!docRow.file_path) {
      return res.status(404).json({ error: 'No attachment for this document' });
    }
    const filePath = path.join(UPLOAD_DIR, docRow.file_path);
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'Attachment file not found' });
    }
    const filename = (docRow.file_name || 'attachment').replace(/[^\w.\- ()]/g, '_').slice(0, 180);
    const asDownload = req.query.download === '1' || req.query.download === 'true';
    res.setHeader(
      'Content-Disposition',
      `${asDownload ? 'attachment' : 'inline'}; filename="${filename}"`
    );
    const ext = path.extname(filename).toLowerCase();
    const mime =
      ext === '.pdf'
        ? 'application/pdf'
        : ext === '.png'
          ? 'image/png'
          : ext === '.jpg' || ext === '.jpeg'
            ? 'image/jpeg'
            : 'application/octet-stream';
    res.setHeader('Content-Type', mime);
    return res.sendFile(path.resolve(filePath));
  } catch (err) {
    console.error('[docutracker GET /documents/:id/attachment]', err);
    res.status(500).json({ error: 'Failed to fetch attachment' });
  }
});

module.exports = router;

