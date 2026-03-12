const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/biometric-devices - list (?status=Active|Inactive|All)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    let where = '';
    if (status === 'Active') where = 'WHERE (is_active IS NULL OR is_active = true)';
    else if (status === 'Inactive') where = 'WHERE is_active = false';

    const result = await pool.query(
      `SELECT id, name, device_id, location, ip_address, last_sync_at, is_active, created_at
       FROM biometric_devices ${where}
       ORDER BY name`
    );
    res.json(result.rows.map((r) => ({
      id: r.id,
      name: r.name,
      device_id: r.device_id,
      location: r.location,
      ip_address: r.ip_address,
      last_sync_at: r.last_sync_at,
      is_active: r.is_active ?? true,
      created_at: r.created_at,
    })));
  } catch (err) {
    console.error('[biometric-devices GET]', err);
    res.status(500).json({ error: 'Failed to fetch biometric devices' });
  }
});

// POST /api/biometric-devices - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { name, device_id, location, ip_address, is_active = true } = req.body;
    if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required' });

    const result = await pool.query(
      `INSERT INTO biometric_devices (name, device_id, location, ip_address, is_active)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, name, device_id, location, ip_address, last_sync_at, is_active, created_at`,
      [name.trim(), device_id?.trim() || null, location?.trim() || null, ip_address?.trim() || null, !!is_active]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'A device with this device_id already exists.' });
    console.error('[biometric-devices POST]', err);
    res.status(500).json({ error: 'Failed to create biometric device' });
  }
});

// PUT /api/biometric-devices/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, device_id, location, ip_address, is_active } = req.body;

    const updates = [];
    const values = [];
    let i = 1;
    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name.trim()); }
    if (device_id !== undefined) { updates.push(`device_id = $${i++}`); values.push(device_id?.trim() || null); }
    if (location !== undefined) { updates.push(`location = $${i++}`); values.push(location?.trim() || null); }
    if (ip_address !== undefined) { updates.push(`ip_address = $${i++}`); values.push(ip_address?.trim() || null); }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }
    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE biometric_devices SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, name, device_id, location, ip_address, last_sync_at, is_active, created_at`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Biometric device not found' });
    res.json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'A device with this device_id already exists.' });
    console.error('[biometric-devices PUT]', err);
    res.status(500).json({ error: 'Failed to update biometric device' });
  }
});

// DELETE /api/biometric-devices/:id (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM biometric_devices WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Biometric device not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[biometric-devices DELETE]', err);
    res.status(500).json({ error: 'Failed to delete biometric device' });
  }
});

module.exports = router;
