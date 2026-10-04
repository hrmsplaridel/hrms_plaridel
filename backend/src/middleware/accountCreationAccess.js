const { pool } = require('../config/db');

async function requireAccountCreationAccess(req, res, next) {
  if (req.user?.role === 'super_admin') return next();
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ error: 'Administrator access required' });
  }

  try {
    const result = await pool.query(
      `SELECT COALESCE((SELECT allowed FROM account_creation_access
                        WHERE admin_user_id = $1::uuid), false) AS allowed`,
      [req.user.id]
    );
    if (!result.rows[0].allowed) {
      return res.status(403).json({ error: 'Account creation access is disabled for your account' });
    }
    next();
  } catch (error) {
    console.error('[account creation access]', error);
    res.status(503).json({ error: 'Account creation access could not be verified' });
  }
}

module.exports = { requireAccountCreationAccess };
