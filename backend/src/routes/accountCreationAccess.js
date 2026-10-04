const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireSuperAdmin } = require('../middleware/rbac');

const router = express.Router();
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

router.get('/me', authMiddleware, async (req, res) => {
  if (req.user?.role === 'super_admin') return res.json({ allowed: true });
  if (req.user?.role !== 'admin') return res.json({ allowed: false });
  try {
    const result = await pool.query(
      `SELECT COALESCE((SELECT allowed FROM account_creation_access
                        WHERE admin_user_id = $1::uuid), false) AS allowed`,
      [req.user.id]
    );
    res.json({ allowed: result.rows[0].allowed });
  } catch (error) {
    console.error('[account creation access GET /me]', error);
    res.status(503).json({ error: 'Account creation access could not be verified' });
  }
});

router.get('/', authMiddleware, requireSuperAdmin, async (_req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.full_name, u.email, u.is_active,
              COALESCE(a.allowed, false) AS allowed
         FROM users u
         LEFT JOIN account_creation_access a ON a.admin_user_id = u.id
        WHERE u.role = 'admin'
        ORDER BY u.is_active DESC, u.full_name NULLS LAST, u.email`
    );
    res.json({ admins: result.rows });
  } catch (error) {
    console.error('[account creation access GET]', error);
    res.status(500).json({ error: 'Failed to load administrators' });
  }
});

router.put('/:adminId', authMiddleware, requireSuperAdmin, async (req, res) => {
  const { adminId } = req.params;
  const { allowed } = req.body || {};
  if (!uuid.test(adminId) || typeof allowed !== 'boolean') {
    return res.status(400).json({ error: 'Valid admin ID and allowed value are required' });
  }

  let client;
  let releaseError;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    const target = await client.query(
      `SELECT id, role FROM users WHERE id = $1::uuid FOR UPDATE`,
      [adminId]
    );
    if (target.rows[0]?.role !== 'admin') {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Administrator not found' });
    }
    const previous = await client.query(
      `SELECT COALESCE((SELECT allowed FROM account_creation_access
                        WHERE admin_user_id = $1::uuid), false) AS allowed`,
      [adminId]
    );
    await client.query(
      `INSERT INTO account_creation_access (admin_user_id, allowed, updated_by)
       VALUES ($1::uuid, $2, $3::uuid)
       ON CONFLICT (admin_user_id) DO UPDATE SET
         allowed = EXCLUDED.allowed,
         updated_by = EXCLUDED.updated_by,
         updated_at = NOW()`,
      [adminId, allowed, req.user.id]
    );
    if (previous.rows[0].allowed !== allowed) {
      await client.query(
        `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
         VALUES ($1::uuid, 'account_creation_access_changed', 'user', $2::uuid, $3)`,
        [req.user.id, adminId, JSON.stringify({ previous_allowed: previous.rows[0].allowed, allowed })]
      );
    }
    await client.query('COMMIT');
    res.json({ admin_id: adminId, allowed });
  } catch (error) {
    if (client) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        releaseError = rollbackError;
        console.error('[account creation access PUT rollback]', rollbackError);
      }
    }
    console.error('[account creation access PUT]', error);
    res.status(client ? 500 : 503).json({
      error: client ? 'Failed to update account creation access' : 'Database temporarily unavailable. Please try again.',
    });
  } finally {
    if (client) client.release(releaseError);
  }
});

module.exports = router;
