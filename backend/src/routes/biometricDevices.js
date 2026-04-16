const express = require('express');
const net = require('net');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { execFile } = require('child_process');
const path = require('path');
const bcrypt = require('bcrypt');

/** ZKTeco default TCP port; quick reachability probe from the API server (not full pyzk). */
function probeZkTcpPort(ipRaw, timeoutMs = 2500) {
  return new Promise((resolve) => {
    const ip = ipRaw && String(ipRaw).trim();
    if (!ip) {
      resolve(null);
      return;
    }
    const socket = net.createConnection({ host: ip, port: 4370 });
    let settled = false;
    const done = (reachable) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try {
        socket.destroy();
      } catch (_) {
        /* ignore */
      }
      resolve(reachable);
    };
    const timer = setTimeout(() => done(false), timeoutMs);
    socket.setTimeout(timeoutMs);
    socket.once('connect', () => done(true));
    socket.once('error', () => done(false));
    socket.once('timeout', () => done(false));
  });
}

const router = express.Router();
const protect = [authMiddleware];

const PUSH_USER_SCRIPT_OPTS = { maxBuffer: 1024 * 1024, timeout: 120000 };

/** Parse stdout JSON from zk_actions.py; fall back to stderr / generic hint. */
function pushUserScriptFailure(res, err, stdout, stderr) {
  const cleanOut = String(stdout || '').replace(/\0/g, '').trim();
  const cleanErr = String(stderr || '').replace(/\0/g, '').trim();
  console.error(
    '[biometric-devices POST push-user] script error:',
    err && err.message ? err.message : err,
    cleanErr ? `stderr: ${cleanErr}` : ''
  );
  try {
    if (cleanOut) {
      const parsed = JSON.parse(cleanOut);
      const msg = parsed.error || parsed.message;
      if (msg) {
        return res.status(500).json({ error: String(msg) });
      }
    }
  } catch (parseErr) {
    /* use fallback below */
  }
  if (cleanErr) {
    return res.status(500).json({
      error: `Device script: ${cleanErr.length > 400 ? `${cleanErr.slice(0, 400)}…` : cleanErr}`,
    });
  }
  if (err && err.killed) {
    return res.status(500).json({
      error: 'Connection to the biometric device timed out. Check IP, cable, and firewall.',
    });
  }
  return res.status(500).json({
    error:
      'Could not run push against the device. Check device IP, network, Python/pyzk, and server logs.',
  });
}

// GET /api/biometric-devices - list (?status=Active|Inactive|All)
// Optional: ?probe_online=0 — skip TCP probe (faster; no `online` field)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    let where = '';
    if (status === 'Active') where = 'WHERE (is_active IS NULL OR is_active = true)';
    else if (status === 'Inactive') where = 'WHERE is_active = false';

    const probeOnline =
      req.query.probe_online !== '0' && req.query.probe_online !== 'false';

    const result = await pool.query(
      `SELECT id, name, device_id, location, ip_address, last_sync_at, is_active, created_at
       FROM biometric_devices ${where}
       ORDER BY name`
    );

    const baseMap = (r) => ({
      id: r.id,
      name: r.name,
      device_id: r.device_id,
      location: r.location,
      ip_address: r.ip_address,
      last_sync_at: r.last_sync_at,
      is_active: r.is_active ?? true,
      created_at: r.created_at,
    });

    if (!probeOnline) {
      return res.json(result.rows.map(baseMap));
    }

    const rows = await Promise.all(
      result.rows.map(async (r) => {
        const row = baseMap(r);
        if (r.ip_address && String(r.ip_address).trim()) {
          row.online = await probeZkTcpPort(r.ip_address);
        } else {
          row.online = null;
        }
        return row;
      })
    );
    res.json(rows);
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

// GET /api/biometric-devices/:id/users - Fetch users from biometric device
router.get('/:id/users', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query('SELECT ip_address FROM biometric_devices WHERE id = $1', [id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Device not found' });
    
    const ip = result.rows[0].ip_address;
    if (!ip) return res.status(400).json({ error: 'Device has no IP address configured' });

    const pyScript = path.join(__dirname, '../../scripts/zk_actions.py');
    const pythonExec = process.platform === 'win32' ? 'python' : 'python3';

    execFile(pythonExec, [pyScript, '--action', 'get_users', '--ip', ip], (error, stdout, stderr) => {
      if (error) {
        console.error('[biometric-devices GET users] script error:', error, stderr);
        // Try parsing JSON error from stdout if present
        try {
          const cleanStdout = stdout.replace(/\0/g, '').trim();
          const parsed = JSON.parse(cleanStdout);
          return res.status(500).json({ error: parsed.error || 'Failed to fetch device users' });
        } catch (e) {
          return res.status(500).json({ error: 'Failed to execute device connection script' });
        }
      }

      try {
        const cleanStdout = stdout.replace(/\0/g, '').trim();
        const parsed = JSON.parse(cleanStdout);
        if (!parsed.success) {
          return res.status(500).json({ error: parsed.error || 'Unknown device error' });
        }
        res.json(parsed.users);
      } catch (parseErr) {
        console.error('[biometric-devices GET users] JSON parse err:', parseErr, stdout);
        res.status(500).json({ error: 'Invalid response from device script' });
      }
    });
  } catch (err) {
    console.error('[biometric-devices GET users]', err);
    res.status(500).json({ error: 'Internal server error while fetching device users' });
  }
});

// POST /api/biometric-devices/:id/push-user — Create/update user on the device from HRMS (pyzk set_user)
router.post('/:id/push-user', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { employee_id, device_pin } = req.body || {};
    if (!employee_id) {
      return res.status(400).json({ error: 'employee_id is required' });
    }

    const devRes = await pool.query(
      'SELECT ip_address FROM biometric_devices WHERE id = $1',
      [id]
    );
    if (devRes.rowCount === 0) return res.status(404).json({ error: 'Device not found' });
    const ip = devRes.rows[0].ip_address;
    if (!ip) return res.status(400).json({ error: 'Device has no IP address configured' });

    const userRes = await pool.query(
      `SELECT id, full_name, biometric_user_id FROM users WHERE id = $1::uuid`,
      [employee_id]
    );
    if (userRes.rowCount === 0) return res.status(404).json({ error: 'Employee not found' });

    const row = userRes.rows[0];
    const bioId = row.biometric_user_id != null ? String(row.biometric_user_id).trim() : '';
    if (!bioId) {
      return res.status(400).json({
        error: 'Employee has no Biometric User ID. Set and save it before pushing to the device.',
      });
    }

    const fullName = (row.full_name || 'User').trim() || 'User';

    const pyScript = path.join(__dirname, '../../scripts/zk_actions.py');
    const pythonExec = process.platform === 'win32' ? 'python' : 'python3';

    const scriptArgs = [
      pyScript,
      '--action',
      'set_user',
      '--ip',
      ip,
      '--user-id',
      bioId,
      '--name',
      fullName,
    ];
    const pinStr = device_pin != null ? String(device_pin).trim() : '';
    if (pinStr !== '') {
      scriptArgs.push('--pin', pinStr);
    }

    execFile(pythonExec, scriptArgs, PUSH_USER_SCRIPT_OPTS, (error, stdout, stderr) => {
      if (error) {
        return pushUserScriptFailure(res, error, stdout, stderr);
      }

      try {
        const cleanStdout = stdout.replace(/\0/g, '').trim();
        const parsed = JSON.parse(cleanStdout);
        if (!parsed.success) {
          return res.status(500).json({ error: parsed.error || 'Device rejected user update' });
        }
        res.json({
          message: 'User pushed to device successfully',
          uid: parsed.uid,
          biometric_user_id: parsed.biometric_user_id,
          name: parsed.name,
        });
      } catch (parseErr) {
        console.error('[biometric-devices POST push-user] JSON parse err:', parseErr, stdout);
        res.status(500).json({ error: 'Invalid response from device script' });
      }
    });
  } catch (err) {
    console.error('[biometric-devices POST push-user]', err);
    res.status(500).json({ error: 'Failed to push user to device' });
  }
});

// POST /api/biometric-devices/:id/import-user - Import single user securely
router.post('/:id/import-user', protect, requireAdmin, async (req, res) => {
  try {
    const { biometric_user_id, full_name, email, password, role } = req.body;
    
    if (!biometric_user_id || !email || !password) {
      return res.status(400).json({ error: 'Biometric ID, email, and password are required' });
    }

    const bioId = String(biometric_user_id).trim();
    const mail = String(email).trim().toLowerCase();

    // Check duplicate bio_id
    const bioExist = await pool.query('SELECT id FROM users WHERE biometric_user_id = $1', [bioId]);
    if (bioExist.rowCount > 0) {
      return res.status(409).json({ error: 'This Biometric ID is already associated with an employee.' });
    }

    // Check duplicate email
    const mailExist = await pool.query('SELECT id FROM users WHERE email = $1', [mail]);
    if (mailExist.rowCount > 0) {
      return res.status(409).json({ error: 'This email is already in use.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const userRole = role === 'admin' ? 'admin' : 'employee';
    const name = (full_name || 'Imported User').trim();
    
    const result = await pool.query(
      `INSERT INTO users (
        email, password_hash, role, full_name, is_active, 
        employee_number, biometric_user_id, employment_status
      ) VALUES (
        $1, $2, $3, $4, false, 
        nextval('users_employee_number_seq'), $5, 'active'
      ) RETURNING id`,
      [mail, passwordHash, userRole, name, bioId]
    );

    res.status(201).json({ message: 'User imported successfully', id: result.rows[0].id });
  } catch (err) {
    console.error('[biometric-devices POST import user]', err);
    res.status(500).json({ error: 'Failed to import user' });
  }
});

module.exports = router;
