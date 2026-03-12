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
      where.push(`document_type = $${i++}`);
      params.push(type);
    }
    if (status && status !== 'All') {
      where.push(`status = $${i++}`);
      params.push(status);
    }
    if (holderId) {
      where.push(`current_holder_id = $${i++}`);
      params.push(holderId);
    }
    if (createdBy) {
      where.push(`created_by = $${i++}`);
      params.push(createdBy);
    }
    if (sourceModule) {
      where.push(`source_module = $${i++}`);
      params.push(sourceModule);
    }
    if (sourceTable) {
      where.push(`source_table = $${i++}`);
      params.push(sourceTable);
    }
    if (q) {
      where.push(`(title ILIKE $${i} OR description ILIKE $${i})`);
      params.push(`%${q}%`);
      i += 1;
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const limitVal = Number.isNaN(Number(limit)) ? 50 : Math.min(Number(limit), 200);
    const offsetVal = Number.isNaN(Number(offset)) ? 0 : Math.max(Number(offset), 0);

    params.push(limitVal, offsetVal);

    const result = await pool.query(
      `SELECT *
       FROM docutracker_documents
       ${whereSql}
       ORDER BY created_at DESC
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
    } = req.body || {};

    if (!document_type || !title) {
      return res.status(400).json({ error: 'document_type and title are required' });
    }

    const result = await pool.query(
      `INSERT INTO docutracker_documents
       (document_type, title, description,
        source_module, source_table, source_record_id, source_title,
        file_path, file_name,
        created_by, current_holder_id, deadline_time)
       VALUES ($1, $2, $3,
               $4, $5, $6, $7,
               $8, $9,
               $10, $11, $12)
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
 * GET /api/docutracker/documents/:id
 * Returns document + routing records + history.
 */
router.get('/documents/:id', protect, async (req, res) => {
  const { id } = req.params;
  try {
    const docResult = await pool.query(
      'SELECT * FROM docutracker_documents WHERE id = $1',
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
      values.push(status);
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
       VALUES ($1, $2::jsonb, COALESCE($3, review_deadline_hours))
       ON CONFLICT (document_type)
       DO UPDATE SET steps = EXCLUDED.steps,
                     review_deadline_hours = COALESCE(EXCLUDED.review_deadline_hours, docutracker_routing_configs.review_deadline_hours),
                     updated_at = now()
       RETURNING *`,
      [document_type, JSON.stringify(steps), review_deadline_hours || null]
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
    const { user_id, document_type, action, granted } = req.body || {};

    if (!user_id || !document_type || !action) {
      return res
        .status(400)
        .json({ error: 'user_id, document_type, and action are required' });
    }

    const grantedBool = !!granted;

    // Check if a permission record already exists
    const existing = await pool.query(
      `SELECT id
       FROM docutracker_permissions
       WHERE user_id = $1
         AND document_type = $2
         AND action = $3`,
      [user_id, document_type, action]
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
           (user_id, document_type, action, granted)
         VALUES ($1, $2, $3, $4)
         RETURNING *`,
        [user_id, document_type, action, grantedBool]
      );
      row = insert.rows[0];
    }

    res.status(201).json({
      id: row.id,
      user_id: row.user_id,
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

