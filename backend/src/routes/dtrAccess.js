const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');
const { loadDtrAccess } = require('../middleware/dtrAccess');
const { activeReviewerFeatures } = require('../services/dtrFeatureReviewerAccess');

const router = express.Router();
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const featureFields = ['employees_allowed', 'leave_allowed', 'approvals_allowed', 'locator_allowed'];

router.get('/me', authMiddleware, async (req, res) => {
  if (req.user?.role !== 'admin') {
    return res.json({ reports_allowed: false, manage_allowed: false,
      ...Object.fromEntries(featureFields.map((field) => [field, false])) });
  }
  try {
    res.json(await loadDtrAccess(req.user.id));
  } catch (error) {
    console.error('[DTR access GET /me]', error);
    res.status(503).json({ error: 'DTR access could not be verified' });
  }
});

router.get('/', authMiddleware, requireSuperAdmin, async (_req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.full_name, u.email, u.is_active,
              COALESCE(a.reports_allowed, false) AS reports_allowed,
              COALESCE(a.manage_allowed, false) AS manage_allowed,
              COALESCE(a.updated_at::text, 'none') AS revision,
              ${featureFields.map((field) => `COALESCE(a.${field}, false) AS ${field}`).join(', ')}
         FROM users u
         LEFT JOIN dtr_admin_access a ON a.admin_user_id = u.id
        WHERE u.role = 'admin'
        ORDER BY u.is_active DESC, u.full_name NULLS LAST, u.email`
    );
    res.json({ admins: result.rows });
  } catch (error) {
    console.error('[DTR access GET]', error);
    res.status(500).json({ error: 'Failed to load DTR access' });
  }
});

router.put('/:adminId', authMiddleware, requireSuperAdmin, async (req, res) => {
  const { adminId } = req.params;
  const { reports_allowed: reportsAllowed, manage_allowed: manageAllowed } = req.body || {};
  const expectedRevision = req.body?.expected_revision;
  if (!uuid.test(adminId) || typeof reportsAllowed !== 'boolean' || typeof manageAllowed !== 'boolean') {
    return res.status(400).json({ error: 'Valid admin ID and DTR permissions are required' });
  }
  if (typeof expectedRevision !== 'string' || !expectedRevision || expectedRevision.length > 100) {
    return res.status(400).json({ error: 'Refresh Manage Access before saving permissions.' });
  }
  let client;
  let releaseError;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    const target = await client.query('SELECT role FROM users WHERE id = $1::uuid FOR UPDATE', [adminId]);
    if (target.rows[0]?.role !== 'admin') {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Administrator not found' });
    }
    const previous = await client.query(
      `SELECT reports_allowed, manage_allowed, ${featureFields.join(', ')}, updated_at::text AS revision
         FROM dtr_admin_access WHERE admin_user_id = $1::uuid`, [adminId]
    );
    if (expectedRevision !== (previous.rows[0]?.revision ?? 'none')) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        code: 'DTR_ACCESS_CONFLICT',
        error: 'Permissions have changed since you opened this page. Refresh and review them before saving.',
      });
    }
    const before = {
      reports_allowed: false, manage_allowed: false,
      ...Object.fromEntries(featureFields.map((field) => [field, false])),
      ...previous.rows[0],
    };
    delete before.revision;
    const after = { reports_allowed: reportsAllowed, manage_allowed: manageAllowed };
    for (const field of featureFields) {
      if (req.body?.[field] !== undefined && typeof req.body[field] !== 'boolean') {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: `Invalid ${field} value` });
      }
      after[field] = req.body?.[field] ?? before[field];
    }
    if (['leave_allowed', 'locator_allowed'].some((field) => before[field] && !after[field])) {
      const assigned = await activeReviewerFeatures(client, adminId);
      const blocked = Object.keys(assigned).find((field) => before[field] && !after[field] && assigned[field]);
      if (blocked) {
        await client.query('ROLLBACK');
        return res.status(409).json({ error: `Reassign this active reviewer before disabling ${blocked.replace('_allowed', '').replace('_', ' ')} access.` });
      }
    }
    const updated = await client.query(
      `INSERT INTO dtr_admin_access (admin_user_id, reports_allowed, manage_allowed,
         ${featureFields.join(', ')}, updated_by)
       VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8::uuid)
       ON CONFLICT (admin_user_id) DO UPDATE SET
         reports_allowed = EXCLUDED.reports_allowed,
         manage_allowed = EXCLUDED.manage_allowed,
         ${featureFields.map((field) => `${field} = EXCLUDED.${field}`).join(',\n         ')},
         updated_by = EXCLUDED.updated_by,
         updated_at = GREATEST(clock_timestamp(), dtr_admin_access.updated_at + interval '1 microsecond')
       RETURNING updated_at::text AS revision`,
      [adminId, reportsAllowed, manageAllowed, ...featureFields.map((field) => after[field]), req.user.id]
    );
    if (Object.keys(after).some((field) => before[field] !== after[field])) {
      await client.query(
        `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
         VALUES ($1::uuid, 'dtr_admin_access_changed', 'user', $2::uuid, $3)`,
        [req.user.id, adminId, JSON.stringify({ before, after })]
      );
    }
    await client.query('COMMIT');
    res.json({ admin_id: adminId, ...after, revision: updated.rows[0].revision });
  } catch (error) {
    if (client) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        releaseError = rollbackError;
        console.error('[DTR access PUT rollback]', rollbackError);
      }
    }
    console.error('[DTR access PUT]', error);
    res.status(client ? 500 : 503).json({
      error: client ? 'Failed to update DTR access' : 'Database temporarily unavailable. Please try again.',
    });
  } finally {
    if (client) client.release(releaseError);
  }
});

module.exports = router;
