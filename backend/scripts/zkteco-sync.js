#!/usr/bin/env node
/**
 * ZKTeco Biometric Sync Service
 *
 * Connects to a ZKTeco K20 (or compatible) device via TCP, fetches attendance
 * logs periodically, and pushes them to the HRMS backend.
 *
 * Usage:
 *   node scripts/zkteco-sync.js
 *
 * Environment:
 *   ZK_DEVICE_IP      - Device IP (default: 192.168.1.201)
 *   ZK_DEVICE_PORT    - Device port (default: 4370)
 *   ZK_TIMEOUT_MS     - Device request timeout in ms (default: 30000; increase if many logs)
 *   ZK_POLL_INTERVAL  - Poll interval in seconds (default: 10)
 *   HRMS_API_URL      - Backend base URL (e.g. http://localhost:3000)
 *   BIO_SYNC_API_KEY  - API key for push endpoint (required)
 *   ZK_SYNC_STATE_FILE - Path to persist last sync time (default: .zkteco-sync-state.json)
 */

const fs = require('fs');
const path = require('path');

// Load .env from backend root
const envPath = path.join(__dirname, '..', '.env');
if (fs.existsSync(envPath)) {
  require('dotenv').config({ path: envPath });
}

const DEVICE_IP = process.env.ZK_DEVICE_IP || '192.168.254.201';
const DEVICE_PORT = parseInt(process.env.ZK_DEVICE_PORT || '4370', 10);
const DEVICE_TIMEOUT_MS = parseInt(process.env.ZK_TIMEOUT_MS || '30000', 10);
const POLL_INTERVAL_SEC = parseInt(process.env.ZK_POLL_INTERVAL || '10', 10);
const API_URL = (process.env.HRMS_API_URL || 'http://localhost:3000').replace(/\/$/, '');
const API_KEY = process.env.BIO_SYNC_API_KEY;
const STATE_FILE = process.env.ZK_SYNC_STATE_FILE ||
  path.join(__dirname, '..', '.zkteco-sync-state.json');

if (!API_KEY) {
  console.error('[zkteco-sync] ERROR: BIO_SYNC_API_KEY is required. Set it in .env or environment.');
  process.exit(1);
}

/** Load last synced timestamp from state file. */
function loadLastSyncTime() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
      const t = data.lastRecordTime;
      return t ? new Date(t) : null;
    }
  } catch (e) {
    console.warn('[zkteco-sync] Could not load state file:', e.message);
  }
  return null;
}

/** Save last synced timestamp to state file. */
function saveLastSyncTime(date) {
  try {
    fs.writeFileSync(STATE_FILE, JSON.stringify({
      lastRecordTime: date.toISOString(),
      updatedAt: new Date().toISOString(),
    }), 'utf8');
  } catch (e) {
    console.warn('[zkteco-sync] Could not save state file:', e.message);
  }
}

/** Normalize device user ID (trim nulls/spaces from fixed-width field). */
function normalizeBiometricUserId(val) {
  if (val == null) return '';
  return String(val).replace(/\0/g, '').trim();
}

/** Fetch attendances from device and push new ones to backend. */
async function syncOnce(ZKLib) {
  const zkInstance = new ZKLib(DEVICE_IP, DEVICE_PORT, DEVICE_TIMEOUT_MS, 4000);
  let lastRecordTime = loadLastSyncTime();

  try {
    await zkInstance.createSocket();
  } catch (err) {
    const msg =
      (typeof err?.toast === 'function' && err.toast()) ||
      err?.err?.message ||
      err?.message ||
      (err?.err && JSON.stringify(err.err)) ||
      String(err);
    console.error('[zkteco-sync] Device connection failed:', msg);
    throw err;
  }

  try {
    // Some ZKTeco models (e.g. K20) require device disabled during data fetch
    try {
      await zkInstance.disableDevice();
    } catch (e) {
      // Ignore if unsupported
    }
    const result = await zkInstance.getAttendances(() => {});
    try {
      await zkInstance.enableDevice();
    } catch (e) {
      // Ignore
    }
    const records = result?.data || [];
    const err = result?.err;

    if (err) {
      console.warn('[zkteco-sync] getAttendances reported error:', err);
    }

    // Filter to only new records (after last sync)
    const newRecords = records.filter((r) => {
      const t = r.recordTime instanceof Date ? r.recordTime : new Date(r.recordTime);
      if (!lastRecordTime) return true;
      return t > lastRecordTime;
    });

    if (newRecords.length === 0) {
      return { pushed: 0, latest: lastRecordTime };
    }

    const punches = newRecords.map((r) => {
      const t = r.recordTime instanceof Date ? r.recordTime : new Date(r.recordTime);
      const biometricUserId = normalizeBiometricUserId(r.deviceUserId);
      return {
        biometric_user_id: biometricUserId || String(r.userSn ?? ''),
        logged_at: t.toISOString(),
      };
    }).filter((p) => p.biometric_user_id);

    const payload = {
      punches,
      source_name: `zkteco-sync-${DEVICE_IP}`,
    };

    const res = await fetch(`${API_URL}/api/biometric-attendance-logs/push`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Api-Key': API_KEY,
      },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Push failed ${res.status}: ${text}`);
    }

    const body = await res.json();
    const latestInBatch = newRecords.reduce((max, r) => {
      const t = r.recordTime instanceof Date ? r.recordTime : new Date(r.recordTime);
      return !max || t > max ? t : max;
    }, null);

    if (latestInBatch) {
      saveLastSyncTime(latestInBatch);
    }

    return {
      pushed: body.inserted ?? 0,
      duplicates: body.duplicates_skipped ?? 0,
      unmatched: body.skipped_unmatched ?? 0,
      latest: latestInBatch,
    };
  } finally {
    try {
      await zkInstance.disconnect();
    } catch (e) {
      // ignore
    }
  }
}

/** Main loop: poll device every POLL_INTERVAL_SEC seconds. */
async function main() {
  let ZKLib;
  try {
    ZKLib = require('node-zklib');
  } catch (e) {
    console.error('[zkteco-sync] node-zklib not installed. Run: npm install node-zklib');
    process.exit(1);
  }

  console.log('[zkteco-sync] Starting sync service');
  console.log('[zkteco-sync] Device:', `${DEVICE_IP}:${DEVICE_PORT} (timeout: ${DEVICE_TIMEOUT_MS}ms)`);
  console.log('[zkteco-sync] API:', API_URL);
  console.log('[zkteco-sync] Poll interval:', POLL_INTERVAL_SEC, 'seconds');
  console.log('---');

  const run = async () => {
    try {
      const result = await syncOnce(ZKLib);
      if (result.pushed > 0 || result.duplicates > 0 || result.unmatched > 0) {
        console.log(
          `[zkteco-sync] Pushed: ${result.pushed}, duplicates: ${result.duplicates}, unmatched: ${result.unmatched}`
        );
      }
    } catch (err) {
      const msg =
        (typeof err?.toast === 'function' && err.toast()) ||
        err?.err?.message ||
        err?.message ||
        (err?.err && JSON.stringify(err.err)) ||
        String(err);
      console.error('[zkteco-sync] Sync error:', msg);
    }
  };

  await run();
  setInterval(run, POLL_INTERVAL_SEC * 1000);
}

main().catch((err) => {
  console.error('[zkteco-sync] Fatal:', err);
  process.exit(1);
});
