const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = authMiddleware;
// Never substitute a current name into a captured identity with missing fields.
const actorName = "CASE WHEN a.actor_snapshot IS NOT NULL THEN a.actor_snapshot->>'name' ELSE u.full_name END";
const actorEmail = "CASE WHEN a.actor_snapshot IS NOT NULL THEN a.actor_snapshot->>'email' ELSE u.email END";

router.get('/', protect, requireSuperAdmin, async (req, res) => {
  const cursorMode = req.query.pagination === 'cursor';
  let cursor;
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  if (req.query.cursor !== undefined) {
    try {
      if (!cursorMode || typeof req.query.cursor !== 'string' || req.query.cursor.length > 1000) throw new Error();
      cursor = JSON.parse(Buffer.from(req.query.cursor, 'base64url').toString());
      const instant = value => typeof value === 'string' &&
        /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(value) &&
        Number.isFinite(Date.parse(value)) &&
        new Date(value).toISOString() === value.replace(/(\.\d{3})\d{3}Z$/, '$1Z');
      if (!instant(cursor.snapshot) || (cursor.after &&
          (!instant(cursor.after.time) || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(cursor.after.id)))) throw new Error();
    } catch (_) {
      return res.status(400).json({ error: 'Invalid audit cursor' });
    }
  }
  const page = Number(req.query.page || 1);
  const limit = Number(req.query.limit || 50);
  if (!Number.isSafeInteger(page) || page < 1 || (!cursorMode && page > 200) ||
      !Number.isInteger(limit) || limit < 1 || limit > 100) {
    return res.status(400).json({ error: 'Invalid pagination' });
  }

  const action = String(req.query.action || '').trim();
  const entityType = String(req.query.entity_type || '').trim();
  const actor = String(req.query.actor || '').trim();
  const hideViews = req.query.hide_views === '1';
  const dateFrom = req.query.date_from;
  const dateBefore = req.query.date_before;
  if ([action, entityType, actor].some(value => value.length > 100)) {
    return res.status(400).json({ error: 'Filter is too long' });
  }
  const validInstant = value => typeof value === 'string' &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) &&
    !Number.isNaN(Date.parse(value)) && new Date(value).toISOString() === value;
  if ((dateFrom !== undefined && !validInstant(dateFrom)) ||
      (dateBefore !== undefined && !validInstant(dateBefore)) ||
      (dateFrom && dateBefore && dateFrom >= dateBefore)) {
    return res.status(400).json({ error: 'Invalid date range' });
  }

  const where = [];
  const params = [];
  if (hideViews) where.push("a.action <> 'audit_log_viewed'");
  if (dateFrom) {
    params.push(dateFrom);
    where.push(`a.created_at >= $${params.length}::timestamptz`);
  }
  if (dateBefore) {
    params.push(dateBefore);
    where.push(`a.created_at < $${params.length}::timestamptz`);
  }
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
    where.push(`(${actorName} ILIKE '%' || $${params.length} || '%' OR ${actorEmail} ILIKE '%' || $${params.length} || '%')`);
  }
  try {
    if (cursorMode) {
      if (!cursor) {
        const result = await pool.query(`SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS snapshot`);
        cursor = { snapshot: result.rows[0].snapshot };
      }
      params.push(cursor.snapshot);
      where.push(`a.created_at < $${params.length}::timestamptz`);
    }
    const filter = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const rowParams = [...params];
    const rowWhere = [...where];
    if (cursorMode && cursor.after) {
      rowParams.push(cursor.after.time, cursor.after.id);
      rowWhere.push(`(a.created_at, a.id) < ($${rowParams.length - 1}::timestamptz, $${rowParams.length}::uuid)`);
    }
    const rowFilter = rowWhere.length ? `WHERE ${rowWhere.join(' AND ')}` : '';
    await pool.query(
      `INSERT INTO audit_logs (user_id, action, entity_type, details)
       VALUES ($1::uuid, 'audit_log_viewed', 'audit_logs', $2)`,
      [req.user.id, JSON.stringify({ page, limit, action, entity_type: entityType, actor, hide_views: hideViews, date_from: dateFrom, date_before: dateBefore })]
    );
    const [count, rows] = await Promise.all([
      pool.query(
        `SELECT COUNT(*)::int AS total FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id ${filter}`,
        params
      ),
      pool.query(
        `SELECT a.id, a.user_id, ${actorName} AS actor_name, ${actorEmail} AS actor_email,
                a.actor_snapshot, a.target_snapshot,
                CASE WHEN a.actor_snapshot IS NOT NULL THEN 'recorded'
                     WHEN u.id IS NOT NULL THEN 'current' ELSE 'unavailable' END AS actor_identity_source,
                CASE WHEN a.target_snapshot IS NOT NULL THEN 'recorded'
                     WHEN target.id IS NOT NULL THEN 'current' ELSE 'unavailable' END AS target_identity_source,
                a.action, a.entity_type, a.entity_id, a.details, a.created_at,
                to_char(a.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_time,
                CASE WHEN a.target_snapshot IS NOT NULL THEN a.target_snapshot->>'name' ELSE target.full_name END AS target_name,
                CASE WHEN a.target_snapshot IS NOT NULL THEN a.target_snapshot->>'email' ELSE target.email END AS target_email
           FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id
           LEFT JOIN users target ON target.id = a.entity_id AND a.entity_type IN ('user', 'system_account', 'employee_account', 'auth') ${rowFilter}
          ORDER BY a.created_at DESC, a.id DESC
          LIMIT $${rowParams.length + 1}${cursorMode ? '' : ` OFFSET $${rowParams.length + 2}`}`,
        cursorMode ? [...rowParams, limit + 1] : [...rowParams, limit, (page - 1) * limit]
      ),
    ]);
    const entries = rows.rows.slice(0, limit);
    const last = entries.at(-1);
    res.json({ entries, total: count.rows[0].total, page, limit,
      ...(cursorMode ? {
        first_cursor: encode({ snapshot: cursor.snapshot }),
        next_cursor: rows.rows.length > limit ? encode({ snapshot: cursor.snapshot,
          after: { time: last.cursor_time, id: last.id } }) : null,
      } : {}),
    });
  } catch (err) {
    console.error('[system-audit GET]', err);
    res.status(500).json({ error: 'Failed to fetch audit log' });
  }
});

module.exports = router;
