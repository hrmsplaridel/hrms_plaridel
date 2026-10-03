const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = authMiddleware;

router.get('/', protect, requireSuperAdmin, async (req, res) => {
  const page = Number(req.query.page || 1);
  const limit = Number(req.query.limit || 50);
  if (!Number.isInteger(page) || page < 1 || page > 200 ||
      !Number.isInteger(limit) || limit < 1 || limit > 100) {
    return res.status(400).json({ error: 'Invalid pagination' });
  }

  const action = String(req.query.action || '').trim();
  const entityType = String(req.query.entity_type || '').trim();
  const actor = String(req.query.actor || '').trim();
  if ([action, entityType, actor].some(value => value.length > 100)) {
    return res.status(400).json({ error: 'Filter is too long' });
  }

  const where = [];
  const params = [];
  if (action) {
    params.push(action);
    where.push(`a.action ILIKE '%' || $${params.length} || '%'`);
  }
  if (entityType) {
    params.push(entityType);
    where.push(`a.entity_type ILIKE '%' || $${params.length} || '%'`);
  }
  if (actor) {
    params.push(actor);
    where.push(`(u.full_name ILIKE '%' || $${params.length} || '%' OR u.email ILIKE '%' || $${params.length} || '%')`);
  }
  const filter = where.length ? `WHERE ${where.join(' AND ')}` : '';

  try {
    await pool.query(
      `INSERT INTO audit_logs (user_id, action, entity_type, details)
       VALUES ($1::uuid, 'audit_log_viewed', 'audit_logs', $2)`,
      [req.user.id, JSON.stringify({ page, limit, action, entity_type: entityType, actor })]
    );
    const [count, rows] = await Promise.all([
      pool.query(
        `SELECT COUNT(*)::int AS total FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id ${filter}`,
        params
      ),
      pool.query(
        `SELECT a.id, a.user_id, u.full_name AS actor_name, u.email AS actor_email,
                a.action, a.entity_type, a.entity_id, a.details, a.created_at
           FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id ${filter}
          ORDER BY a.created_at DESC, a.id DESC
          LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
        [...params, limit, (page - 1) * limit]
      ),
    ]);
    res.json({ entries: rows.rows, total: count.rows[0].total, page, limit });
  } catch (err) {
    console.error('[system-audit GET]', err);
    res.status(500).json({ error: 'Failed to fetch audit log' });
  }
});

module.exports = router;
