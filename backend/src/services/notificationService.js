const { broadcastAppEvent } = require('../websockets/appEvents');
const { sendPushForNotification } = require('./fcmPushService');

/**
 * Global in-app notifications (header bell). DocuTracker uses docutracker_notifications
 * only — do not insert document workflow events here (Option B).
 *
 * @param {import('pg').Pool} db
 * @param {object} opts
 * @param {string} opts.userId
 * @param {string} [opts.category]
 * @param {string} opts.type
 * @param {string} opts.title
 * @param {string} [opts.body]
 * @param {string} [opts.referenceType]
 * @param {string} [opts.referenceId]
 * @param {object} [opts.metadata]
 */
async function insertNotification(db, opts) {
  const {
    userId,
    category = 'general',
    type,
    title,
    body = null,
    referenceType = null,
    referenceId = null,
    metadata = null,
  } = opts;
  const r = await db.query(
    `INSERT INTO user_notifications (user_id, category, type, title, body, reference_type, reference_id, metadata)
     VALUES ($1::uuid, $2, $3, $4, $5, $6, $7::uuid, $8::jsonb)
     RETURNING id, user_id, category, type, title, body, read_at, reference_type, reference_id, metadata, created_at`,
    [userId, category, type, title, body, referenceType, referenceId, metadata ? JSON.stringify(metadata) : null]
  );
  const row = r.rows[0];
  broadcastAppEvent(
    'notification_created',
    { notification: mapRowToApi(row) },
    { userIds: [row.user_id] }
  );
  sendPushForNotification(db, row).catch((err) => {
    console.error('[notificationService] sendPushForNotification', err);
  });
  return row;
}

/**
 * @param {import('pg').Pool} db
 * @param {string[]} userIds
 * @param {Omit<Parameters<typeof insertNotification>[1], 'userId'>} payload
 */
async function insertNotificationForUsers(db, userIds, payload) {
  if (!userIds || userIds.length === 0) return;
  const seen = new Set();
  for (const uid of userIds) {
    if (!uid || seen.has(uid)) continue;
    seen.add(uid);
    try {
      await insertNotification(db, { ...payload, userId: uid });
    } catch (err) {
      console.error('[notificationService] insertNotificationForUsers', err);
    }
  }
}

async function listNotifications(db, userId, { limit = 50, unreadOnly = false } = {}) {
  const safeLimit = Math.min(Math.max(parseInt(String(limit), 10) || 50, 1), 200);
  const r = await db.query(
    `SELECT id, user_id, category, type, title, body, read_at, reference_type, reference_id, metadata, created_at
     FROM user_notifications
     WHERE user_id = $1::uuid
       AND ($2::boolean = false OR read_at IS NULL)
     ORDER BY created_at DESC
     LIMIT $3`,
    [userId, unreadOnly, safeLimit]
  );
  return r.rows;
}

async function countUnread(db, userId) {
  const r = await db.query(
    `SELECT count(*)::int AS c FROM user_notifications WHERE user_id = $1::uuid AND read_at IS NULL`,
    [userId]
  );
  return r.rows[0]?.c ?? 0;
}

async function markRead(db, notificationId, userId) {
  const r = await db.query(
    `UPDATE user_notifications SET read_at = now() WHERE id = $1::uuid AND user_id = $2::uuid AND read_at IS NULL
     RETURNING id`,
    [notificationId, userId]
  );
  return r.rowCount > 0;
}

async function markAllRead(db, userId) {
  await db.query(
    `UPDATE user_notifications SET read_at = now() WHERE user_id = $1::uuid AND read_at IS NULL`,
    [userId]
  );
}

async function getHrAdminUserIds(db) {
  const r = await db.query(`SELECT id FROM users WHERE role IN ('admin', 'hr')`);
  return r.rows.map((row) => row.id);
}

function mapRowToApi(row) {
  return {
    id: row.id,
    user_id: row.user_id,
    category: row.category,
    type: row.type,
    title: row.title,
    body: row.body,
    read_at: row.read_at,
    reference_type: row.reference_type,
    reference_id: row.reference_id,
    metadata: row.metadata,
    created_at: row.created_at,
  };
}

module.exports = {
  insertNotification,
  insertNotificationForUsers,
  listNotifications,
  countUnread,
  markRead,
  markAllRead,
  getHrAdminUserIds,
  mapRowToApi,
};
