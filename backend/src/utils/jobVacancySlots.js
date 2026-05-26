const { pool } = require('../config/db');

/** Lowercase, trimmed, without common HR prefixes — used to match applications to vacancies. */
function normalizePositionKey(raw) {
  let t = String(raw || '').trim().toLowerCase();
  t = t.replace(/^now hiring:\s*/i, '');
  t = t.replace(/\s+/g, ' ');
  return t;
}

/** Same "position key" as the Flutter client stores in `position_applied_for` (headline, else body, else first E/E/T). */
function vacancyPositionKey(v) {
  if (!v || typeof v !== 'object') return '';
  const h = typeof v.headline === 'string' ? v.headline.trim() : '';
  if (h.length) return normalizePositionKey(h);
  const b = typeof v.body === 'string' ? v.body.trim() : '';
  if (b.length) return normalizePositionKey(b);
  for (const k of ['education', 'experience', 'training']) {
    const s = typeof v[k] === 'string' ? v[k].trim() : '';
    if (s.length) return normalizePositionKey(s);
  }
  return '';
}

function normalizeStoredPositionKey(raw) {
  return normalizePositionKey(raw);
}

function parseClosingDateIso(v) {
  if (v == null) return null;
  const s = String(v).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  // Interpret the date as end-of-day in UTC to keep it consistent across hosts.
  const d = new Date(`${s}T23:59:59.999Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

function isVacancyClosedByDate(v, now = new Date()) {
  if (!v || typeof v !== 'object') return false;
  const d = parseClosingDateIso(v.closing_date);
  if (!d) return false;
  return now.getTime() > d.getTime();
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
  const p = normalizeStoredPositionKey(positionAppliedFor);
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
  const key = normalizeStoredPositionKey(positionKeyLower);
  if (!key) return 0;
  const r = await pool.query(
    `
    SELECT COUNT(*)::int AS c
    FROM public.recruitment_applications
    WHERE position_applied_for IS NOT NULL
      AND btrim(position_applied_for::text) <> ''
      AND lower(regexp_replace(regexp_replace(trim(position_applied_for::text), '^now hiring:\\s*', '', 'i'), '\\s+', ' ', 'g')) = $1
      AND (${ACTIVE_APPLICANT_SLOT_SQL})
    `,
    [key]
  );
  return r.rows[0]?.c ?? 0;
}

async function countTotalApplicationsForPositionKey(positionKeyLower) {
  const key = normalizeStoredPositionKey(positionKeyLower);
  if (!key) return 0;
  const r = await pool.query(
    `
    SELECT COUNT(*)::int AS c
    FROM public.recruitment_applications
    WHERE position_applied_for IS NOT NULL
      AND btrim(position_applied_for::text) <> ''
      AND lower(regexp_replace(regexp_replace(trim(position_applied_for::text), '^now hiring:\\s*', '', 'i'), '\\s+', ' ', 'g')) = $1
    `,
    [key]
  );
  return r.rows[0]?.c ?? 0;
}

/**
 * Appends `application_count` per vacancy (by position key).
 * @param {object[]} vacancies
 */
const POSITION_KEY_SQL = `
  lower(
    regexp_replace(
      regexp_replace(trim(position_applied_for::text), '^now hiring:\\s*', '', 'i'),
      '\\s+',
      ' ',
      'g'
    )
  )
`;

async function enrichVacanciesWithApplicationCounts(vacancies) {
  if (!Array.isArray(vacancies) || vacancies.length === 0) return vacancies;
  let activeRows = [];
  let totalRows = [];
  try {
    const activeQ = await pool.query(
      `
      SELECT ${POSITION_KEY_SQL} AS k, COUNT(*)::int AS c
      FROM public.recruitment_applications
      WHERE position_applied_for IS NOT NULL
        AND btrim(position_applied_for::text) <> ''
        AND (${ACTIVE_APPLICANT_SLOT_SQL})
      GROUP BY ${POSITION_KEY_SQL}
      `
    );
    activeRows = activeQ.rows;
    const totalQ = await pool.query(
      `
      SELECT ${POSITION_KEY_SQL} AS k, COUNT(*)::int AS c
      FROM public.recruitment_applications
      WHERE position_applied_for IS NOT NULL
        AND btrim(position_applied_for::text) <> ''
      GROUP BY ${POSITION_KEY_SQL}
      `
    );
    totalRows = totalQ.rows;
  } catch {
    activeRows = [];
    totalRows = [];
  }
  const activeMap = new Map(activeRows.map((x) => [x.k, x.c]));
  const totalMap = new Map(totalRows.map((x) => [x.k, x.c]));
  return vacancies.map((v) => {
    const key = vacancyPositionKey(v);
    const application_count = key ? activeMap.get(key) ?? 0 : 0;
    const total_application_count = key ? totalMap.get(key) ?? 0 : 0;
    return {
      ...v,
      application_count,
      total_application_count,
      is_closed: isVacancyClosedByDate(v),
    };
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

/**
 * Checks both: deadline (closing_date) and max applicants.
 * @returns {{ ok: true } | { ok: false, status: number, error: string, code?: string }}
 */
async function assertPositionAcceptingApplications(positionTrimmed) {
  const pos = String(positionTrimmed || '').trim();
  if (!pos) return { ok: true };

  const vacancies = await loadVacanciesFromDb();
  const vac = findVacancyForPosition(vacancies, pos);
  if (vac && isVacancyClosedByDate(vac)) {
    return {
      ok: false,
      status: 409,
      error: 'This hiring is already closed. The due date has passed.',
      code: 'DEADLINE_PASSED',
    };
  }
  return await assertPositionApplicationSlotAvailable(pos);
}

module.exports = {
  vacancyPositionKey,
  normalizePositionKey,
  normalizeStoredPositionKey,
  parseMaxApplicants,
  loadVacanciesFromDb,
  findVacancyForPosition,
  enrichVacanciesWithApplicationCounts,
  countTotalApplicationsForPositionKey,
  assertPositionApplicationSlotAvailable,
  assertPositionAcceptingApplications,
  parseClosingDateIso,
  isVacancyClosedByDate,
};
