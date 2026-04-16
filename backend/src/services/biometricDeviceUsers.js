'use strict';

const { execFile } = require('child_process');
const { promisify } = require('util');
const path = require('path');
const { pool } = require('../config/db');

const execFileAsync = promisify(execFile);

/** Avoid re-querying the ZKTeco on every paged /search request from the roster UI. */
const CACHE_TTL_MS = 60 * 1000;
const cache = new Map();

function isUuid(s) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(s);
}

/**
 * PIN / user_id values currently enrolled on the device (for filtering HRMS employees).
 * Results are cached briefly per device id.
 */
async function getDeviceUserBiometricIds(deviceId) {
  if (!isUuid(deviceId)) {
    return { ok: false, statusCode: 400, message: 'Invalid biometric_device_id' };
  }

  const now = Date.now();
  const hit = cache.get(deviceId);
  if (hit && now - hit.at < CACHE_TTL_MS) {
    return { ok: true, ids: hit.ids };
  }

  const result = await pool.query(
    'SELECT ip_address FROM biometric_devices WHERE id = $1::uuid',
    [deviceId]
  );
  if (result.rowCount === 0) {
    return { ok: false, statusCode: 404, message: 'Biometric device not found' };
  }
  const ip = result.rows[0].ip_address;
  if (!ip || !String(ip).trim()) {
    return { ok: false, statusCode: 400, message: 'Device has no IP address configured' };
  }

  const pyScript = path.join(__dirname, '../../scripts/zk_actions.py');
  const pythonExec = process.platform === 'win32' ? 'python' : 'python3';

  let stdout;
  try {
    ({ stdout } = await execFileAsync(
      pythonExec,
      [pyScript, '--action', 'get_users', '--ip', String(ip).trim()],
      { maxBuffer: 10 * 1024 * 1024, timeout: 120000 }
    ));
  } catch (err) {
    return {
      ok: false,
      statusCode: 502,
      message: err.message || 'Failed to read users from biometric device',
    };
  }

  let parsed;
  try {
    const cleanStdout = stdout.replace(/\0/g, '').trim();
    parsed = JSON.parse(cleanStdout);
  } catch (e) {
    return { ok: false, statusCode: 502, message: 'Invalid response from device script' };
  }

  if (!parsed.success) {
    return {
      ok: false,
      statusCode: 502,
      message: parsed.error || 'Device returned an error',
    };
  }

  const users = parsed.users || [];
  const ids = [
    ...new Set(
      users
        .map((u) => (u.biometric_user_id != null ? String(u.biometric_user_id).trim() : ''))
        .filter(Boolean)
    ),
  ];

  cache.set(deviceId, { at: now, ids });
  return { ok: true, ids };
}

module.exports = { getDeviceUserBiometricIds };
