let admin = null;
let initAttempted = false;

const pushEnabledCategories = new Set([
  'attendance',
  'dtr',
  'leave',
  'locator',
  'overtime',
]);

function parseServiceAccount(raw) {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (err) {
    console.error('[fcmPushService] Invalid FIREBASE_SERVICE_ACCOUNT_JSON', err);
    return null;
  }
}

function getFirebaseAdmin() {
  if (initAttempted) return admin;
  initAttempted = true;

  let firebaseAdmin;
  try {
    firebaseAdmin = require('firebase-admin');
  } catch (_) {
    console.warn('[fcmPushService] firebase-admin is not installed; push notifications disabled.');
    return null;
  }

  try {
    if (firebaseAdmin.apps.length > 0) {
      admin = firebaseAdmin;
      return admin;
    }

    const serviceAccount = parseServiceAccount(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    const credential = serviceAccount
      ? firebaseAdmin.credential.cert(serviceAccount)
      : process.env.GOOGLE_APPLICATION_CREDENTIALS
        ? firebaseAdmin.credential.applicationDefault()
        : null;

    if (!credential) {
      console.warn(
        '[fcmPushService] Firebase credentials missing; set FIREBASE_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS.'
      );
      return null;
    }

    firebaseAdmin.initializeApp({
      credential,
      projectId: process.env.FIREBASE_PROJECT_ID || serviceAccount?.project_id,
    });
    admin = firebaseAdmin;
    return admin;
  } catch (err) {
    console.error('[fcmPushService] Firebase Admin init failed', err);
    return null;
  }
}

function sanitizePlatform(platform) {
  const value = String(platform || '').trim().toLowerCase();
  if (['android', 'ios', 'web', 'macos', 'windows', 'linux'].includes(value)) {
    return value;
  }
  return 'unknown';
}

async function registerToken(db, { userId, token, platform, deviceId }) {
  const cleanToken = String(token || '').trim();
  if (!userId || !cleanToken) return null;

  const r = await db.query(
    `INSERT INTO user_push_tokens (user_id, token, platform, device_id, last_seen_at)
     VALUES ($1::uuid, $2, $3, $4, now())
     ON CONFLICT (token)
     DO UPDATE SET
       user_id = EXCLUDED.user_id,
       platform = EXCLUDED.platform,
       device_id = EXCLUDED.device_id,
       revoked_at = NULL,
       last_seen_at = now(),
       updated_at = now()
     RETURNING id, user_id, token, platform, device_id, last_seen_at`,
    [userId, cleanToken, sanitizePlatform(platform), deviceId || null]
  );
  return r.rows[0] || null;
}

async function unregisterToken(db, { userId, token }) {
  const cleanToken = String(token || '').trim();
  if (!userId || !cleanToken) return false;

  const r = await db.query(
    `UPDATE user_push_tokens
     SET revoked_at = now(), updated_at = now()
     WHERE user_id = $1::uuid AND token = $2 AND revoked_at IS NULL`,
    [userId, cleanToken]
  );
  return r.rowCount > 0;
}

async function listActiveTokens(db, userId) {
  if (!userId) return [];
  const r = await db.query(
    `SELECT token
     FROM user_push_tokens
     WHERE user_id = $1::uuid
       AND revoked_at IS NULL`,
    [userId]
  );
  return r.rows.map((row) => row.token).filter(Boolean);
}

async function revokeTokens(db, tokens) {
  if (!tokens || tokens.length === 0) return;
  await db.query(
    `UPDATE user_push_tokens
     SET revoked_at = now(), updated_at = now()
     WHERE token = ANY($1::text[])`,
    [tokens]
  );
}

function notificationData(row) {
  return {
    notification_id: String(row.id || ''),
    category: String(row.category || ''),
    type: String(row.type || ''),
    reference_type: String(row.reference_type || ''),
    reference_id: String(row.reference_id || ''),
  };
}

async function sendPushForNotification(db, row) {
  if (!pushEnabledCategories.has(String(row?.category || '').toLowerCase())) {
    return;
  }

  const firebaseAdmin = getFirebaseAdmin();
  if (!firebaseAdmin || !row?.user_id) return;

  const tokens = await listActiveTokens(db, row.user_id);
  if (tokens.length === 0) return;

  const message = {
    tokens,
    notification: {
      title: row.title || 'HRMS notification',
      body: row.body || '',
    },
    data: notificationData(row),
    android: {
      priority: 'high',
      notification: {
        channelId: 'hrms_notifications',
        sound: 'default',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
        },
      },
    },
  };

  try {
    const response = await firebaseAdmin.messaging().sendEachForMulticast(message);
    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = result.error?.code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        invalidTokens.push(tokens[index]);
      } else {
        console.error('[fcmPushService] Push send failed', code, result.error?.message);
      }
    });
    await revokeTokens(db, invalidTokens);
  } catch (err) {
    console.error('[fcmPushService] Push multicast failed', err);
  }
}

module.exports = {
  registerToken,
  unregisterToken,
  sendPushForNotification,
};
