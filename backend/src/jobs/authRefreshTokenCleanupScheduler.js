/**
 * Deletes refresh-token rows that can no longer be used.
 *
 * Active tokens are kept so users can stay logged in on multiple devices.
 * Expired tokens are removed immediately; revoked tokens are retained briefly
 * for audit/debugging, then removed.
 */

const cron = require('node-cron');

const CLEANUP_LOCK_KEY = 57190421;
const CRON_EXPRESSION = process.env.AUTH_REFRESH_TOKEN_CLEANUP_CRON || '0 3 * * *';
const CRON_TIMEZONE = process.env.AUTH_REFRESH_TOKEN_CLEANUP_TZ || 'Asia/Manila';
const DEFAULT_REVOKED_RETENTION_DAYS = 30;

function revokedRetentionDays() {
  const parsed = Number.parseInt(
    process.env.AUTH_REFRESH_TOKEN_REVOKED_RETENTION_DAYS || '',
    10,
  );
  if (!Number.isFinite(parsed) || parsed < 0) {
    return DEFAULT_REVOKED_RETENTION_DAYS;
  }
  return parsed;
}

async function cleanupAuthRefreshTokens(pool) {
  const retentionDays = revokedRetentionDays();
  const result = await pool.query(
    `DELETE FROM auth_refresh_tokens
     WHERE expires_at < now()
        OR (
          revoked_at IS NOT NULL
          AND revoked_at < now() - make_interval(days => $1::int)
        )`,
    [retentionDays],
  );
  return {
    deleted: result.rowCount || 0,
    revokedRetentionDays: retentionDays,
  };
}

async function runCleanupWithLock(pool) {
  const client = await pool.connect();
  try {
    const lock = await client.query(
      'SELECT pg_try_advisory_lock($1::bigint) AS got',
      [CLEANUP_LOCK_KEY],
    );
    if (!lock.rows[0]?.got) {
      return { ran: false, reason: 'advisory_lock_not_acquired' };
    }

    try {
      const result = await cleanupAuthRefreshTokens(client);
      return { ran: true, ...result };
    } finally {
      await client.query('SELECT pg_advisory_unlock($1::bigint)', [
        CLEANUP_LOCK_KEY,
      ]);
    }
  } finally {
    client.release();
  }
}

function logCleanupResult(prefix, result) {
  if (!result?.ran) {
    console.log(
      `[authRefreshTokenCleanup] ${prefix} skipped (${result?.reason || 'unknown'})`,
    );
    return;
  }
  console.log(
    `[authRefreshTokenCleanup] ${prefix} deleted=${result.deleted} revokedRetentionDays=${result.revokedRetentionDays}`,
  );
}

function scheduleAuthRefreshTokenCleanupCron(pool) {
  if (process.env.AUTH_REFRESH_TOKEN_CLEANUP_ENABLED === 'false') {
    console.log(
      '[authRefreshTokenCleanup] disabled (AUTH_REFRESH_TOKEN_CLEANUP_ENABLED=false)',
    );
    return null;
  }

  setTimeout(() => {
    runCleanupWithLock(pool)
      .then((result) => logCleanupResult('startup', result))
      .catch((err) => console.error('[authRefreshTokenCleanup] startup error', err));
  }, 10 * 1000);

  const task = cron.schedule(
    CRON_EXPRESSION,
    async () => {
      try {
        const result = await runCleanupWithLock(pool);
        logCleanupResult('cron', result);
      } catch (err) {
        console.error('[authRefreshTokenCleanup] cron error', err);
      }
    },
    { timezone: CRON_TIMEZONE },
  );

  console.log(
    `[authRefreshTokenCleanup] scheduled expr="${CRON_EXPRESSION}" timezone=${CRON_TIMEZONE}`,
  );
  return task;
}

module.exports = {
  scheduleAuthRefreshTokenCleanupCron,
  cleanupAuthRefreshTokens,
  runCleanupWithLock,
};
