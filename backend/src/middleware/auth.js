const jwt = require('jsonwebtoken');
const { pool } = require('../config/db');

/**
 * Verify JWT and attach req.user = { id, email, role }.
 * Call next() on success; respond 401 on failure.
 */
function createAuthMiddleware(db = pool) {
  return async function authMiddleware(req, res, next) {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing or invalid Authorization header' });
    }
    const token = authHeader.replace('Bearer ', '').trim();
    try {
      const payload = jwt.verify(token, process.env.JWT_SECRET);
      // Reject refresh tokens used as Bearer (access tokens use typ: 'access' or omit typ for legacy).
      if (payload.typ === 'refresh') {
        return res.status(401).json({ error: 'Invalid token type' });
      }
      const accountResult = await db.query(
        `SELECT id, email, role, is_active, employment_status
           FROM users
          WHERE id = $1::uuid`,
        [payload.id]
      );
      const account = accountResult.rows[0];
      if (!account) {
        return res.status(401).json({ error: 'Account no longer exists' });
      }
      if (
        account.is_active !== true ||
        String(account.employment_status || 'active').toLowerCase() !== 'active'
      ) {
        return res.status(403).json({ error: 'Account is deactivated' });
      }
      req.user = {
        id: account.id,
        email: account.email,
        role: String(account.role || 'employee').toLowerCase(),
      };
      return next();
    } catch (err) {
      if (!['JsonWebTokenError', 'TokenExpiredError', 'NotBeforeError'].includes(err?.name)) {
        console.error('[auth middleware]', err);
        return res.status(503).json({ error: 'Unable to verify account status' });
      }
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
  };
}

const authMiddleware = createAuthMiddleware();

module.exports = { authMiddleware, createAuthMiddleware };
