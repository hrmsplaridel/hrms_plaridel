/**
 * L&D training requirement attachment paths allowed for signed URLs / proxy.
 */
const { pool } = require('../config/db');

async function isLdTrainingRequirementPathAllowed(objectPath) {
  const p = String(objectPath ?? '').trim();
  if (!p) return false;

  try {
    const { rows } = await pool.query(
      `
      SELECT EXISTS (
        SELECT 1
        FROM public.ld_training_requirement_records r
        WHERE btrim($1::text) <> ''
          AND (
            btrim($1::text) = btrim(COALESCE(r.doc_invitation_letter_path, ''))
            OR btrim($1::text) = btrim(COALESCE(r.doc_lap_path, ''))
            OR btrim($1::text) = btrim(COALESCE(r.doc_training_certificate_path, ''))
            OR btrim($1::text) LIKE r.id::text || '/%'
          )
      ) AS ok
      `,
      [p],
    );
    return Boolean(rows?.[0]?.ok);
  } catch (err) {
    console.error('[ldTrainingRequirementPolicy]', err);
    return false;
  }
}

module.exports = { isLdTrainingRequirementPathAllowed };
