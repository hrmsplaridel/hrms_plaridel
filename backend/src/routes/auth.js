const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();

const SALT_ROUNDS = 10;
const JWT_EXPIRY = process.env.JWT_EXPIRY || '7d';

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

    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    res.status(201).json({
      token,
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

    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    res.json({
      token,
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
 * GET /auth/me
 * Requires Authorization: Bearer <token>
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
