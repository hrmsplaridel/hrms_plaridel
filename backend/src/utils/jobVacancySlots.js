const { pool } = require('../config/db');
const { todayInHrmsTimezone } = require('./dateRangeParser');
const { excludeMayorIntakeStubSql } = require('./mayorIntakeStub');

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

/** Job title posted by HR. Requirements-only rows are not an applyable vacancy. */
function vacancyListedHeadlineKey(v) {
  if (!v || typeof v !== 'object') return '';
  const h = typeof v.headline === 'string' ? v.headline.trim() : '';
  return h.length ? normalizePositionKey(h) : '';
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

/** Whole-number age from a request value. Blank is null. */
function parseOptionalWholeAge(raw) {
  if (raw == null || raw === '') return { ok: true, value: null };
  const s = typeof raw === 'number' ? String(raw) : String(raw).trim();
  if (!/^\d+$/.test(s)) {
    return { ok: false, error: 'Age must be a whole number.' };
  }
  const n = Number(s);
  if (!Number.isSafeInteger(n)) {
    return { ok: false, error: 'Age must be a whole number.' };
  }
  return { ok: true, value: n };
}

/**
 * @returns {{ ok: true, minimumAge: number, maximumAge: number|null } | { ok: false, error: string }}
 */
function parseVacancyAgeRequirements(rawMinimum, rawMaximum) {
  if (rawMinimum == null || rawMinimum === '') {
    return { ok: false, error: 'Minimum age is required.' };
  }
  const minimum = parseOptionalWholeAge(rawMinimum);
  if (!minimum.ok || minimum.value == null) {
    return { ok: false, error: 'Minimum age must be a whole number.' };
  }
  const maximum = parseOptionalWholeAge(rawMaximum);
  if (!maximum.ok) {
    return { ok: false, error: 'Maximum age must be a whole number.' };
  }
  if (maximum.value != null && maximum.value < minimum.value) {
    return {
      ok: false,
      error: 'Maximum age must be greater than or equal to minimum age.',
    };
  }
  return { ok: true, minimumAge: minimum.value, maximumAge: maximum.value };
}

/** Stored minimum, or 18 when an older vacancy has no age rule yet. */
function vacancyMinimumAge(v) {
  const parsed = parseOptionalWholeAge(v?.minimum_age);
  if (!parsed.ok || parsed.value == null) return 18;
  return parsed.value;
}

/** Stored maximum, or null when the vacancy has no maximum. */
function vacancyMaximumAge(v) {
  if (v == null || v.maximum_age == null || v.maximum_age === '') return null;
  const parsed = parseOptionalWholeAge(v.maximum_age);
  if (!parsed.ok) return null;
  return parsed.value;
}

/** Completed years on a calendar date. Both arguments are YYYY-MM-DD. */
function ageOnCalendarDate(dobIso, todayIso) {
  const [y, m, d] = String(dobIso).split('-').map(Number);
  const [ty, tm, td] = String(todayIso).split('-').map(Number);
  let age = ty - y;
  if (tm < m || (tm === m && td < d)) age -= 1;
  return age;
}

/**
 * @returns {{ ok: true, age: number } | { ok: false, status: number, error: string, code: string }}
 */
function assertApplicantAgeForVacancy(vacancy, dobIso, todayIso = todayInHrmsTimezone()) {
  const minimum = vacancyMinimumAge(vacancy);
  const maximum = vacancyMaximumAge(vacancy);
  const age = ageOnCalendarDate(dobIso, todayIso);
  if (age < minimum) {
    return {
      ok: false,
      status: 400,
      error: `This vacancy requires applicants to be at least ${minimum} years old.`,
      code: 'AGE_BELOW_MINIMUM',
    };
  }
  if (maximum != null && age > maximum) {
    return {
      ok: false,
      status: 400,
      error: `This vacancy accepts applicants up to ${maximum} years old.`,
      code: 'AGE_ABOVE_MAXIMUM',
    };
  }
  return { ok: true, age };
}

async function assertApplicantMeetsVacancyAge(positionTrimmed, dobIso) {
  const vacancies = await loadVacanciesFromDb();
  const vac = findListedVacancyForPosition(vacancies, positionTrimmed);
  if (!vac) {
    return {
      ok: false,
      status: 409,
      error: 'This position is not currently open for applications.',
      code: 'POSITION_NOT_OPEN',
    };
  }
  return assertApplicantAgeForVacancy(vac, dobIso);
}

/**
 * Loads the landing-page hiring toggle and vacancies JSON.
 * @returns {Promise<{ hasVacancies: boolean, vacancies: object[] }>}
 */
async function loadAnnouncementFromDb() {
  try {
    const r = await pool.query(
      `SELECT has_vacancies, vacancies FROM public.job_vacancy_announcement WHERE id = 'default' LIMIT 1`
    );
    const row = r.rows[0];
    if (!row) return { hasVacancies: false, vacancies: [] };
    return {
      hasVacancies: row.has_vacancies === true,
      vacancies: Array.isArray(row.vacancies) ? row.vacancies : [],
    };
  } catch {
    return { hasVacancies: false, vacancies: [] };
  }
}

/**
 * Loads vacancies JSON from the landing-page row (may be empty).
 * @returns {Promise<object[]>}
 */
async function loadVacanciesFromDb() {
  const announcement = await loadAnnouncementFromDb();
  return announcement.vacancies;
}

function findVacancyForPosition(vacancies, positionAppliedFor) {
  const p = normalizeStoredPositionKey(positionAppliedFor);
  if (!p) return null;
  for (const v of vacancies) {
    if (vacancyPositionKey(v) === p) return v;
  }
  return null;
}

function vacancyMinimumStandards(vacancy) {
  if (!vacancy || typeof vacancy !== 'object') return null;
  const pick = (value) => {
    const text = typeof value === 'string' ? value.trim() : '';
    return text || null;
  };
  const standards = {
    min_education: pick(vacancy.education),
    min_experience: pick(vacancy.experience),
    min_training: pick(vacancy.training),
    min_eligibility: pick(vacancy.eligibility),
  };
  if (
    !standards.min_education &&
    !standards.min_experience &&
    !standards.min_training &&
    !standards.min_eligibility
  ) {
    return null;
  }
  return standards;
}

function mergeBlankMinimumStandards(entry, standards) {
  const next = { ...(entry || {}) };
  let changed = false;
  for (const key of ['min_education', 'min_experience', 'min_training', 'min_eligibility']) {
    const current = typeof next[key] === 'string' ? next[key].trim() : '';
    const incoming = standards && standards[key] ? standards[key] : null;
    if (!current && incoming) {
      next[key] = incoming;
      changed = true;
    }
  }
  return { entry: next, changed };
}

function publishedDateOnly(value) {
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
    return value.trim();
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return todayInHrmsTimezone(value);
  }
  return null;
}

/** Keeps the first landing-page publish date for a job title. New titles use [fallbackDate]. */
function applyPublishedDates(vacancies, existing, fallbackDate) {
  const previous = new Map();
  for (const vacancy of existing || []) {
    const key = vacancyListedHeadlineKey(vacancy);
    const published = publishedDateOnly(vacancy && vacancy.published_at);
    if (key && published && !previous.has(key)) previous.set(key, published);
  }
  const fallback = publishedDateOnly(fallbackDate) || todayInHrmsTimezone();
  return (vacancies || []).map((vacancy) => {
    if (!vacancy || typeof vacancy !== 'object') return vacancy;
    const key = vacancyListedHeadlineKey(vacancy);
    const published =
      (key && previous.get(key)) ||
      publishedDateOnly(vacancy.published_at) ||
      fallback;
    return { ...vacancy, published_at: published };
  });
}

function findListedVacancyForPosition(vacancies, positionAppliedFor) {
  const p = normalizeStoredPositionKey(positionAppliedFor);
  if (!p) return null;
  for (const v of vacancies) {
    if (vacancyListedHeadlineKey(v) === p) return v;
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
      AND ${excludeMayorIntakeStubSql()}
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
      AND ${excludeMayorIntakeStubSql()}
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
        AND ${excludeMayorIntakeStubSql()}
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
        AND ${excludeMayorIntakeStubSql()}
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
  if (!pos) {
    return {
      ok: false,
      status: 409,
      error: 'No vacant position is listed. Applications cannot be submitted.',
      code: 'NO_POSITION',
    };
  }

  const { hasVacancies, vacancies } = await loadAnnouncementFromDb();
  if (!hasVacancies) {
    return {
      ok: false,
      status: 409,
      error: 'Hiring is currently closed.',
      code: 'HIRING_CLOSED',
    };
  }

  const vac = findListedVacancyForPosition(vacancies, pos);
  if (!vac) {
    return {
      ok: false,
      status: 409,
      error: 'This position is not currently open for applications.',
      code: 'POSITION_NOT_OPEN',
    };
  }

  if (isVacancyClosedByDate(vac)) {
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
  vacancyListedHeadlineKey,
  normalizePositionKey,
  normalizeStoredPositionKey,
  parseMaxApplicants,
  parseVacancyAgeRequirements,
  vacancyMinimumAge,
  vacancyMaximumAge,
  ageOnCalendarDate,
  assertApplicantAgeForVacancy,
  assertApplicantMeetsVacancyAge,
  loadAnnouncementFromDb,
  loadVacanciesFromDb,
  findVacancyForPosition,
  findListedVacancyForPosition,
  vacancyMinimumStandards,
  mergeBlankMinimumStandards,
  publishedDateOnly,
  applyPublishedDates,
  enrichVacanciesWithApplicationCounts,
  countTotalApplicationsForPositionKey,
  assertPositionApplicationSlotAvailable,
  assertPositionAcceptingApplications,
  parseClosingDateIso,
  isVacancyClosedByDate,
};
