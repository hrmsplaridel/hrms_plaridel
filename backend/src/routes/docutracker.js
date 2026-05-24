const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

/**
 * Utility: map DB row to document response DTO.
 */
function mapDocumentRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    document_number: row.document_number,
    document_type: row.document_type,
    title: row.title,
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
  const r = await pool.query(
    `SELECT created_by, current_holder_id FROM docutracker_documents WHERE id = $1`,
    [documentId]
  );
  const row = r.rows[0];
  if (!row) return false;
  const uid = req.user.id;
  return row.created_by === uid || row.current_holder_id === uid;
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

    const where = [];
    const params = [];
    let i = 1;

    if (type && type !== 'All') {
      where.push(`d.document_type = $${i++}`);
      params.push(type);
    }
    if (status && status !== 'All') {
      where.push(`d.status = $${i++}`);
      params.push(normalizeDocStatus(status));
    }
    if (holderId) {
      where.push(`d.current_holder_id = $${i++}`);
      params.push(holderId);
    }
    if (createdBy) {
      where.push(`d.created_by = $${i++}`);
      params.push(createdBy);
    }
    if (sourceModule) {
      where.push(`d.source_module = $${i++}`);
      params.push(sourceModule);
    }
    if (sourceTable) {
      where.push(`d.source_table = $${i++}`);
      params.push(sourceTable);
    }
    if (q) {
      where.push(`(d.title ILIKE $${i} OR d.description ILIKE $${i})`);
      params.push(`%${q}%`);
      i += 1;
    }

    const isAdmin = req.user.role === 'admin';
    if (!isAdmin) {
      where.push(`(d.created_by = $${i} OR d.current_holder_id = $${i})`);
      params.push(req.user.id);
      i += 1;
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const limitVal = Number.isNaN(Number(limit)) ? 50 : Math.min(Number(limit), 200);
    const offsetVal = Number.isNaN(Number(offset)) ? 0 : Math.max(Number(offset), 0);

    params.push(limitVal, offsetVal);

    const result = await pool.query(
      `SELECT d.*, creator.full_name AS creator_name
       FROM docutracker_documents d
       LEFT JOIN users creator ON creator.id = d.created_by
       ${whereSql}
       ORDER BY d.created_at DESC
       LIMIT $${i} OFFSET $${i + 1}`,
      params
    );

    res.json(result.rows.map(mapDocumentRow));
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
    const {
      document_type,
      title,
      description,
      file_path,
      file_name,
      current_holder_id,
      deadline_time,
      source_module,
      source_table,
      source_record_id,
      source_title,
      document_number,
      current_step,
      status,
      sent_time,
      reviewed_time,
      escalation_level,
      needs_admin_intervention,
    } = b;

    if (!document_type || !title) {
      return res.status(400).json({ error: 'document_type and title are required' });
    }

    const result = await pool.query(
      `INSERT INTO docutracker_documents
       (document_type, title, description,
        source_module, source_table, source_record_id, source_title,
        file_path, file_name,
        created_by, current_holder_id, deadline_time,
        document_number, current_step, status, sent_time, reviewed_time,
        escalation_level, needs_admin_intervention)
       VALUES ($1, $2, $3,
               $4, $5, $6, $7,
               $8, $9,
               $10, $11, $12,
               $13, $14, COALESCE($15, 'pending'), $16, $17,
               COALESCE($18, 0), COALESCE($19, false))
       RETURNING *`,
      [
        document_type,
        title,
        description || null,
        source_module || null,
        source_table || null,
        source_record_id || null,
        source_title || null,
        file_path || null,
        file_name || null,
        req.user.id,
        current_holder_id || null,
        deadline_time || null,
        document_number || null,
        current_step ?? 1,
        status != null ? normalizeDocStatus(status) : null,
        sent_time || null,
        reviewed_time || null,
        escalation_level ?? null,
        needs_admin_intervention ?? null,
      ]
    );

    const doc = result.rows[0];

    // Log initial creation in history
    await pool.query(
      `INSERT INTO docutracker_document_history
       (document_id, action, actor_id, to_status, remarks)
       VALUES ($1, $2, $3, $4, $5)`,
      [doc.id, 'created', req.user.id, doc.status, description || null]
    );

    res.status(201).json(mapDocumentRow(doc));
  } catch (err) {
    console.error('[docutracker POST /documents]', err);
    res.status(500).json({ error: 'Failed to create document' });
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
         AND d.status NOT IN ('approved', 'rejected', 'cancelled')
       ORDER BY d.deadline_time ASC`
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
 * POST /api/docutracker/notifications
 */
router.post('/notifications', protect, async (req, res) => {
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
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Notification not found' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('[docutracker PATCH /notifications/:id/read]', err);
    res.status(500).json({ error: 'Failed to mark notification read' });
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
      `SELECT * FROM docutracker_escalation_configs ${whereSql} ORDER BY document_type, department_id NULLS LAST LIMIT 20`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    console.error('[docutracker GET /escalation-configs]', err);
    res.status(500).json({ error: 'Failed to fetch escalation configs' });
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
      `SELECT * FROM docutracker_document_history
       WHERE document_id = $1
       ORDER BY created_at DESC`,
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
        b.actor_id || req.user.id,
        b.actor_name || null,
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
        `SELECT *
         FROM docutracker_routing_records
         WHERE document_id = $1
         ORDER BY step_order ASC`,
        [id]
      ),
      pool.query(
        `SELECT *
         FROM docutracker_document_history
         WHERE document_id = $1
         ORDER BY created_at ASC`,
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
 * PATCH /api/docutracker/documents/:id
 * Allows updating status, current_holder_id, current_step and optional remarks.
 * Body: { status?, current_holder_id?, current_step?, remarks?, needs_admin_intervention? }
 */
router.patch('/documents/:id', protect, async (req, res) => {
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
      where = 'WHERE document_type = $1';
      params.push(document_type);
    }
    const result = await pool.query(
      `SELECT *
       FROM docutracker_routing_configs
       ${where}
       ORDER BY document_type`,
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

    const result = await pool.query(
      `INSERT INTO docutracker_routing_configs
       (document_type, steps, review_deadline_hours)
       VALUES ($1, $2::jsonb, COALESCE($3, 1))
       ON CONFLICT (document_type)
       DO UPDATE SET steps = EXCLUDED.steps,
                     review_deadline_hours = COALESCE(EXCLUDED.review_deadline_hours, docutracker_routing_configs.review_deadline_hours),
                     updated_at = now()
       RETURNING *`,
      [document_type, JSON.stringify(steps), review_deadline_hours ?? null]
    );

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[docutracker POST /routing-configs]', err);
    res.status(500).json({ error: 'Failed to save routing config' });
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
    if (!document_type) {
      return res.status(400).json({ error: 'document_type is required' });
    }

    const params = [document_type, action];
    const where = [];
    let i = 3;

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
         COALESCE(p.granted, false) AS granted
       FROM users u
       LEFT JOIN docutracker_permissions p
         ON p.user_id = u.id
        AND p.document_type = $1
        AND p.action = $2
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

    const grantedBool = !!granted;

    const existing = await pool.query(
      user_id
        ? `SELECT id FROM docutracker_permissions
           WHERE user_id = $1 AND document_type = $2 AND action = $3`
        : `SELECT id FROM docutracker_permissions
           WHERE role_id = $1 AND user_id IS NULL AND document_type = $2 AND action = $3`,
      user_id ? [user_id, document_type, action] : [role_id, document_type, action]
    );

    let row;
    if (existing.rowCount > 0) {
      const permId = existing.rows[0].id;
      const update = await pool.query(
        `UPDATE docutracker_permissions
         SET granted = $1,
             updated_at = now()
         WHERE id = $2
         RETURNING *`,
        [grantedBool, permId]
      );
      row = update.rows[0];
    } else {
      const insert = await pool.query(
        `INSERT INTO docutracker_permissions
           (user_id, role_id, document_type, action, granted)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [user_id || null, role_id || null, document_type, action, grantedBool]
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

module.exports = router;

