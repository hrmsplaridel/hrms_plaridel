const jwt = require('jsonwebtoken');

/**
 * Verify JWT and attach req.user = { id, email, role }.
 * Call next() on success; respond 401 on failure.
 */
function authMiddleware(req, res, next) {
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
    req.user = { id: payload.id, email: payload.email, role: payload.role };
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = { authMiddleware };
