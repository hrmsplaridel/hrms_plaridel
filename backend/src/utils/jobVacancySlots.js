const { pool } = require('../config/db');

/** Same "position key" as the Flutter client stores in `position_applied_for` (headline, else body). */
function vacancyPositionKey(v) {
  if (!v || typeof v !== 'object') return '';
  const h = typeof v.headline === 'string' ? v.headline.trim() : '';
  if (h.length) return h.toLowerCase();
  const b = typeof v.body === 'string' ? v.body.trim() : '';
  return b.length ? b.toLowerCase() : '';
}

function parseMaxApplicants(v) {
  if (v == null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n < 1) return null;
  return Math.min(100000, Math.floor(n));
}

/**
 * Loads vacancies JSON from the landing-page row (may be empty).
 * @returns {Promise<object[]>}
 */
async function loadVacanciesFromDb() {
  try {
    const r = await pool.query(
      `SELECT vacancies FROM public.job_vacancy_announcement WHERE id = 'default' LIMIT 1`
    );
    const raw = r.rows[0]?.vacancies;
    return Array.isArray(raw) ? raw : [];
  } catch {
    return [];
  }
}

function findVacancyForPosition(vacancies, positionAppliedFor) {
  const p = String(positionAppliedFor || '').trim().toLowerCase();
  if (!p) return null;
  for (const v of vacancies) {
    if (vacancyPositionKey(v) === p) return v;
  }
  return null;
}

/**
 * Still consuming a vacancy slot: in the pipeline, not eliminated, not hired.
 * Declined docs, failed exam, failed final interview, and registered (hired) free a slot.
 */
const ACTIVE_APPLICANT_SLOT_SQL = `
  status NOT IN ('document_declined', 'failed', 'registered')
  AND (final_interview_passed IS NOT FALSE)
`;

async function countApplicationsForPositionKey(positionKeyLower) {
  const r = await pool.query(
    `
    SELECT COUNT(*)::int AS c
    FROM public.recruitment_applications
    WHERE position_applied_for IS NOT NULL
      AND btrim(position_applied_for::text) <> ''
      AND lower(trim(position_applied_for::text)) = $1
      AND (${ACTIVE_APPLICANT_SLOT_SQL})
    `,
    [positionKeyLower]
  );
  return r.rows[0]?.c ?? 0;
}

/**
 * Appends `application_count` per vacancy (by position key).
 * @param {object[]} vacancies
 */
async function enrichVacanciesWithApplicationCounts(vacancies) {
  if (!Array.isArray(vacancies) || vacancies.length === 0) return vacancies;
  let rows;
  try {
    const r = await pool.query(
      `
      SELECT lower(trim(position_applied_for::text)) AS k, COUNT(*)::int AS c
      FROM public.recruitment_applications
      WHERE position_applied_for IS NOT NULL
        AND btrim(position_applied_for::text) <> ''
        AND (${ACTIVE_APPLICANT_SLOT_SQL})
      GROUP BY lower(trim(position_applied_for::text))
      `
    );
    rows = r.rows;
  } catch {
    rows = [];
  }
  const map = new Map(rows.map((x) => [x.k, x.c]));
  return vacancies.map((v) => {
    const key = vacancyPositionKey(v);
    const application_count = key ? map.get(key) ?? 0 : 0;
    return { ...v, application_count };
  });
}

/**
 * @returns {{ ok: true } | { ok: false, status: number, error: string, code?: string }}
 */
async function assertPositionApplicationSlotAvailable(positionTrimmed) {
  const pos = String(positionTrimmed || '').trim();
  if (!pos) return { ok: true };

  const vacancies = await loadVacanciesFromDb();
  const vac = findVacancyForPosition(vacancies, pos);
  if (!vac) return { ok: true };

  const max = parseMaxApplicants(vac.max_applicants);
  if (max == null) return { ok: true };

  const key = pos.toLowerCase();
  const c = await countApplicationsForPositionKey(key);
  if (c >= max) {
    return {
      ok: false,
      status: 409,
      error: 'The application limit for this position has been reached.',
      code: 'POSITION_FULL',
    };
  }
  return { ok: true };
}

module.exports = {
  vacancyPositionKey,
  parseMaxApplicants,
  loadVacanciesFromDb,
  findVacancyForPosition,
  enrichVacanciesWithApplicationCounts,
  assertPositionApplicationSlotAvailable,
};
