#!/usr/bin/env node
/**
 * ZKTeco diagnostic script - isolate which step fails.
 * Run: node scripts/zkteco-diagnose.js
 *
 * Environment: ZK_DEVICE_IP, ZK_DEVICE_PORT, ZK_TIMEOUT_MS (from .env)
 */
const fs = require('fs');
const path = require('path');
const envPath = path.join(__dirname, '..', '.env');
if (fs.existsSync(envPath)) {
  require('dotenv').config({ path: envPath });
}

const DEVICE_IP = process.env.ZK_DEVICE_IP || '192.168.254.201';
const DEVICE_PORT = parseInt(process.env.ZK_DEVICE_PORT || '4370', 10);
const DEVICE_TIMEOUT_MS = parseInt(process.env.ZK_TIMEOUT_MS || '60000', 10);

function log(step, msg, ok = true) {
  const prefix = ok ? '[OK]' : '[FAIL]';
  console.log(`${prefix} ${step}: ${msg}`);
}

async function run() {
  const ZKLib = require('node-zklib');
  const zk = new ZKLib(DEVICE_IP, DEVICE_PORT, DEVICE_TIMEOUT_MS, 4000);

  console.log('--- ZKTeco diagnostic ---');
  console.log(`Device: ${DEVICE_IP}:${DEVICE_PORT}, timeout: ${DEVICE_TIMEOUT_MS}ms`);
  console.log('');

  try {
    log('1. connect', 'createSocket()');
    await zk.createSocket();
    log('1. connect', 'TCP connected');

    log('2. getInfo', 'getInfo() - device capacity');
    const info = await zk.getInfo();
    console.log('   userCounts:', info.userCounts, 'logCounts:', info.logCounts, 'logCapacity:', info.logCapacity);
    log('2. getInfo', 'done');

    log('3. getUsers', 'getUsers()');
    const usersResult = await zk.getUsers();
    const users = usersResult?.data || [];
    log('3. getUsers', `done, ${users.length} users`);

    log('4. disableDevice', 'disable_device (required by some models before data fetch)');
    await zk.disableDevice();
    log('4. disableDevice', 'done');

    log('5. getAttendances', 'getAttendances() - this often times out on K20');
    const attResult = await zk.getAttendances(() => {});
    const records = attResult?.data || [];
    const attErr = attResult?.err;
    if (attErr) {
      log('5. getAttendances', attErr.message || attErr, false);
    } else {
      log('5. getAttendances', `done, ${records.length} records`);
    }

    log('6. enableDevice', 'enable_device');
    await zk.enableDevice();
    log('6. enableDevice', 'done');

    log('7. disconnect', 'disconnect()');
    await zk.disconnect();
    log('7. disconnect', 'done');

    console.log('');
    console.log('--- All steps completed ---');
  } catch (err) {
    const msg =
      (typeof err?.toast === 'function' && err.toast()) ||
      err?.err?.message ||
      err?.message ||
      String(err);
    console.error('');
    console.error('[FAIL] Error:', msg);
    console.error('Stack:', err?.stack);
    try {
      await zk.enableDevice();
      await zk.disconnect();
    } catch (e) {}
    process.exit(1);
  }
}

run();
