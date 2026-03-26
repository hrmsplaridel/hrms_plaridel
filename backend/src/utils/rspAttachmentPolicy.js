/**
 * Recruitment attachment paths allowed for signed URLs / proxy (Postgres).
 * See scripts/rsp-storage-attachment-policy.sql
 */
const { pool } = require('../config/db');

async function isAttachmentPathAllowedInDb(objectPath) {
  const p = String(objectPath ?? '').trim();
  if (!p) return false;

  try {
    const { rows } = await pool.query(
      'SELECT public.rsp_storage_path_allowed($1::text) AS ok',
      [p],
    );
    return Boolean(rows?.[0]?.ok);
  } catch (err) {
    if (err.code !== '42883') throw err;
    const { rows } = await pool.query(
      `SELECT EXISTS (
        SELECT 1
        FROM public.recruitment_applications ra
        WHERE btrim($1::text) <> ''
          AND (
            btrim($1::text) = ra.attachment_path
            OR btrim($1::text) LIKE ra.id::text || '/%'
          )
      ) AS ok`,
      [p],
    );
    return Boolean(rows?.[0]?.ok);
  }
}

module.exports = { isAttachmentPathAllowedInDb };
