const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();

const SALT_ROUNDS = 10;
// Support JWT_EXPIRATION or legacy JWT_EXPIRY from .env
const JWT_EXPIRATION = process.env.JWT_EXPIRATION || process.env.JWT_EXPIRY || '15m';
const JWT_REFRESH_EXPIRATION = process.env.JWT_REFRESH_EXPIRATION || '30d';

function hashRefreshToken(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

/**
 * Issue access + refresh JWTs and persist refresh token hash.
 */
async function issueTokensForUser(user, req) {
  const accessPayload = {
    id: user.id,
    email: user.email,
    role: user.role,
    typ: 'access',
  };
  const accessToken = jwt.sign(accessPayload, process.env.JWT_SECRET, {
    expiresIn: JWT_EXPIRATION,
  });

  if (!process.env.JWT_REFRESH_SECRET) {
    throw new Error('JWT_REFRESH_SECRET is not configured');
  }

  const refreshToken = jwt.sign(
    { id: user.id, typ: 'refresh' },
    process.env.JWT_REFRESH_SECRET,
    { expiresIn: JWT_REFRESH_EXPIRATION }
  );

  const decodedRefresh = jwt.decode(refreshToken);
  const expiresAt = new Date(decodedRefresh.exp * 1000);
  const tokenHash = hashRefreshToken(refreshToken);

  const ua = req.get('user-agent');
  const rawIp = req.ip || req.socket?.remoteAddress;
  const ipForDb = rawIp && String(rawIp).trim() !== '' ? String(rawIp) : null;

  await pool.query(
    `INSERT INTO auth_refresh_tokens (user_id, token_hash, expires_at, device_info, ip_address)
     VALUES ($1, $2, $3, $4, $5::inet)`,
    [user.id, tokenHash, expiresAt, ua || null, ipForDb]
  );

  return { accessToken, refreshToken };
}

/**
 * POST /auth/register
 * Body: { email, password, fullName?, role? }
 */
router.post('/register', async (req, res) => {
  try {
    const { email, password, fullName, role = 'employee' } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }
    if (!['admin', 'employee'].includes(role)) {
      return res.status(400).json({ error: 'Role must be admin or employee' });
    }

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    const result = await pool.query(
      `INSERT INTO users (email, password_hash, role, full_name, is_active)
       VALUES ($1, $2, $3, $4, true)
       RETURNING id, email, role, full_name, avatar_path, is_active, created_at`,
      [email.trim().toLowerCase(), passwordHash, role, fullName || null]
    );
    const user = result.rows[0];

    try {
      await pool.query(
        `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days)
         VALUES ($1::uuid, 'vacationLeave', 15, 0, 0, 0), ($1::uuid, 'sickLeave', 15, 0, 0, 0)
         ON CONFLICT (user_id, leave_type) DO NOTHING`,
        [user.id]
      );
    } catch (lbErr) {
      console.warn('[auth/register] Could not create default leave balances:', lbErr.message);
    }

    const { accessToken, refreshToken } = await issueTokensForUser(user, req);

    res.status(201).json({
      token: accessToken,
      refreshToken,
      user: {
        id: user.id,
        email: user.email,
        role: user.role,
        full_name: user.full_name,
        avatar_path: user.avatar_path,
        is_active: user.is_active,
      },
    });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Email already registered' });
    }
    console.error('[auth/register]', err);
    res.status(500).json({ error: 'Registration failed' });
  }
});

/**
 * POST /auth/login
 * Body: { email, password }
 */
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    const result = await pool.query(
      `SELECT id, email, password_hash, role, full_name, avatar_path, is_active
       FROM users WHERE LOWER(email) = $1`,
      [email.trim().toLowerCase()]
    );
    const user = result.rows[0];

    if (!user) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }
    if (!user.is_active) {
      return res.status(403).json({ error: 'Account is deactivated' });
    }

    const match = await bcrypt.compare(password, user.password_hash);
    if (!match) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    const { accessToken, refreshToken } = await issueTokensForUser(user, req);

    res.json({
      token: accessToken,
      refreshToken,
      user: {
        id: user.id,
        email: user.email,
        role: user.role,
        full_name: user.full_name,
        avatar_path: user.avatar_path,
        is_active: user.is_active,
      },
    });
  } catch (err) {
    console.error('[auth/login]', err);
    res.status(500).json({ error: 'Login failed' });
  }
});

/**
 * POST /auth/refresh
 * Body: { refreshToken: string }
 * Returns new { token, refreshToken } (rotates refresh token).
 */
router.post('/refresh', async (req, res) => {
  const raw = req.body?.refreshToken;
  if (!raw || typeof raw !== 'string') {
    return res.status(400).json({ error: 'refreshToken is required' });
  }
  if (!process.env.JWT_REFRESH_SECRET) {
    return res.status(503).json({ error: 'Refresh tokens not configured' });
  }

  try {
    const decoded = jwt.verify(raw, process.env.JWT_REFRESH_SECRET);
    if (decoded.typ !== 'refresh') {
      return res.status(401).json({ error: 'Invalid refresh token' });
    }

    const tokenHash = hashRefreshToken(raw);
    const rowResult = await pool.query(
      `SELECT id, user_id, expires_at, revoked_at
       FROM auth_refresh_tokens
       WHERE token_hash = $1`,
      [tokenHash]
    );
    const rec = rowResult.rows[0];
    if (!rec || rec.revoked_at) {
      return res.status(401).json({ error: 'Invalid or revoked refresh token' });
    }
    if (new Date(rec.expires_at) < new Date()) {
      return res.status(401).json({ error: 'Refresh token expired' });
    }

    const userResult = await pool.query(
      `SELECT id, email, role, full_name, avatar_path, is_active
       FROM users WHERE id = $1`,
      [decoded.id]
    );
    const user = userResult.rows[0];
    if (!user || !user.is_active) {
      return res.status(403).json({ error: 'Account is deactivated' });
    }

    await pool.query(
      `UPDATE auth_refresh_tokens SET revoked_at = now() WHERE id = $1`,
      [rec.id]
    );

    const { accessToken, refreshToken } = await issueTokensForUser(user, req);

    return res.json({
      token: accessToken,
      refreshToken,
    });
  } catch (e) {
    if (e.name === 'JsonWebTokenError' || e.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Invalid or expired refresh token' });
    }
    console.error('[auth/refresh]', e);
    return res.status(500).json({ error: 'Token refresh failed' });
  }
});

/**
 * POST /auth/logout
 * Body: { refreshToken: string }
 * Revokes the refresh token row (optional client cleanup).
 */
router.post('/logout', async (req, res) => {
  const raw = req.body?.refreshToken;
  if (!raw || typeof raw !== 'string') {
    return res.status(400).json({ error: 'refreshToken is required' });
  }

  const tokenHash = hashRefreshToken(raw);
  await pool.query(
    `UPDATE auth_refresh_tokens
     SET revoked_at = now()
     WHERE token_hash = $1 AND revoked_at IS NULL`,
    [tokenHash]
  );

  return res.json({ ok: true });
});

/**
 * GET /auth/me
 * Requires Authorization: Bearer <access token>
 */
router.get('/me', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, email, role, full_name, avatar_path, is_active,
              middle_name, suffix, sex, date_of_birth, contact_number, address, created_at
       FROM users WHERE id = $1`,
      [req.user.id]
    );
    const row = result.rows[0];
    if (!row) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.json({
      id: row.id,
      email: row.email,
      role: row.role,
      full_name: row.full_name,
      avatar_path: row.avatar_path,
      is_active: row.is_active,
      middle_name: row.middle_name,
      suffix: row.suffix,
      sex: row.sex,
      date_of_birth: row.date_of_birth,
      contact_number: row.contact_number,
      address: row.address,
      user_metadata: {
        full_name: row.full_name,
        avatar_path: row.avatar_path,
        phone: row.contact_number,
      },
    });
  } catch (err) {
    console.error('[auth/me]', err);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

/**
 * PATCH /auth/me - Update profile (name, contact, avatar_path)
 * Body: { full_name?, contact_number?, avatar_path? }
 */
router.patch('/me', authMiddleware, async (req, res) => {
  try {
    const { full_name, contact_number, avatar_path } = req.body;
    const updates = [];
    const values = [];
    let i = 1;

    if (full_name !== undefined) {
      updates.push(`full_name = $${i++}`);
      values.push(full_name);
    }
    if (contact_number !== undefined) {
      updates.push(`contact_number = $${i++}`);
      values.push(contact_number);
    }
    if (avatar_path !== undefined) {
      updates.push(`avatar_path = $${i++}`);
      values.push(avatar_path);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }
    updates.push(`updated_at = now()`);
    values.push(req.user.id);

    await pool.query(
      `UPDATE users SET ${updates.join(', ')} WHERE id = $${i}`,
      values
    );

    const result = await pool.query(
      `SELECT id, email, role, full_name, avatar_path, is_active, contact_number
       FROM users WHERE id = $1`,
      [req.user.id]
    );
    const row = result.rows[0];
    res.json({
      id: row.id,
      email: row.email,
      role: row.role,
      full_name: row.full_name,
      avatar_path: row.avatar_path,
      is_active: row.is_active,
      user_metadata: { full_name: row.full_name, avatar_path: row.avatar_path, phone: row.contact_number },
    });
  } catch (err) {
    console.error('[auth/me PATCH]', err);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

/**
 * POST /auth/change-password
 * Body: { current_password, new_password }
 */
router.post('/change-password', authMiddleware, async (req, res) => {
  try {
    const { current_password, new_password } = req.body;
    if (!current_password || !new_password) {
      return res.status(400).json({ error: 'Current and new password required' });
    }

    const result = await pool.query(
      'SELECT password_hash FROM users WHERE id = $1',
      [req.user.id]
    );
    const user = result.rows[0];
    if (!user) return res.status(404).json({ error: 'User not found' });

    const match = await bcrypt.compare(current_password, user.password_hash);
    if (!match) {
      return res.status(401).json({ error: 'Current password is incorrect' });
    }

    const hash = await bcrypt.hash(new_password, SALT_ROUNDS);
    await pool.query(
      'UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2',
      [hash, req.user.id]
    );
    res.json({ message: 'Password updated' });
  } catch (err) {
    console.error('[auth/change-password]', err);
    res.status(500).json({ error: 'Failed to change password' });
  }
});

/**
 * POST /auth/forgot-password
 * Body: { email }
 * Stub: returns 200 with message. Implement email service (nodemailer, SendGrid, etc.) later.
 */
router.post('/forgot-password', async (req, res) => {
  const { email } = req.body;
  if (!email) {
    return res.status(400).json({ error: 'Email is required' });
  }
  // TODO: Look up user, generate reset token, send email
  res.json({ message: 'If that email exists, a reset link will be sent' });
});

module.exports = router;
