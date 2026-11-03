'use strict';

/** Shared input validation for Landing apply, RSP, and L&D. */

/** Letters, Ñ/ñ, spaces, hyphen, apostrophe, period (Jr./Sr.). */
const PERSON_NAME_RE = /^[A-Za-zÑñ]+(?:[ \-'.][A-Za-zÑñ]+)*\.?$/;
const EMAIL_RE = /^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/;

const EMAIL_MAX = 254;
const PERSON_NAME_MAX = 80;
const PHONE_MIN_DIGITS = 10;
const PHONE_MAX_DIGITS = 15;

const TRAINING_DAILY_TITLE_MAX = 200;
const TRAINING_DAILY_DESCRIPTION_MAX = 4000;
const TRAINING_REQUIREMENT_TITLE_MAX = 300;

const SEX_ALLOWLIST = Object.freeze(['Male', 'Female']);
const CIVIL_STATUS_ALLOWLIST = Object.freeze([
  'Single',
  'Married',
  'Widowed',
  'Separated',
  'Legally Separated',
  'Annulled',
  'Divorced',
  'Live-in / Common-law',
]);

function optTrim(value) {
  return typeof value === 'string' && value.trim().length ? value.trim() : null;
}

function digitsOnly(raw) {
  return String(raw ?? '').replace(/\D/g, '');
}

function isValidPersonName(raw, { required = true } = {}) {
  const t = typeof raw === 'string' ? raw.trim() : '';
  if (!t) return !required;
  if (t.length > PERSON_NAME_MAX) return false;
  return PERSON_NAME_RE.test(t);
}

function isValidEmail(raw) {
  const e = typeof raw === 'string' ? raw.trim().toLowerCase() : '';
  if (!e || e.length > EMAIL_MAX) return false;
  return EMAIL_RE.test(e);
}

function normalizeEmail(raw) {
  return typeof raw === 'string' ? raw.trim().toLowerCase() : '';
}

function isValidPhone(raw) {
  const d = digitsOnly(raw);
  return d.length >= PHONE_MIN_DIGITS && d.length <= PHONE_MAX_DIGITS;
}

function isWholeNumberString(raw, { allowEmpty = false } = {}) {
  const t = typeof raw === 'string' ? raw.trim() : String(raw ?? '').trim();
  if (!t) return allowEmpty;
  return /^\d+$/.test(t);
}

/**
 * Parse score 0–100 (inclusive). Returns { ok, value, error }.
 * Allows decimals. Rejects non-finite / out of range.
 */
function parseScore0to100(raw) {
  if (raw === undefined || raw === null || raw === '') {
    return { ok: false, error: 'score_percent is required', code: 'SCORE_REQUIRED' };
  }
  const n = typeof raw === 'number' ? raw : Number(String(raw).trim().replace(',', '.'));
  if (!Number.isFinite(n)) {
    return { ok: false, error: 'score_percent must be a number', code: 'SCORE_INVALID' };
  }
  if (n < 0 || n > 100) {
    return {
      ok: false,
      error: 'score_percent must be between 0 and 100',
      code: 'SCORE_OUT_OF_RANGE',
    };
  }
  return { ok: true, value: n };
}

function clampScore0to100(raw) {
  const parsed = parseScore0to100(raw);
  if (!parsed.ok) return parsed;
  return parsed;
}

/**
 * Validate public RSP application create body.
 * Returns { ok: true, data } or { ok: false, status, error, code }.
 */
function validateRspApplicationCreate(body = {}) {
  const firstName = optTrim(body.firstName);
  const middleName = optTrim(body.middleName);
  const lastName = optTrim(body.lastName);
  const suffix = optTrim(body.suffix);
  const sex = optTrim(body.sex);
  const course = optTrim(body.course);
  const address = optTrim(body.address);
  const civilStatus = optTrim(body.civilStatus);
  const phoneRaw = body.phone;
  const emailRaw = body.email;

  if (!isValidPersonName(firstName, { required: true })) {
    return {
      ok: false,
      status: 400,
      error:
        'First name is required and may only contain letters, spaces, hyphens, apostrophes, and periods.',
      code: 'FIRST_NAME_INVALID',
    };
  }
  if (middleName && !isValidPersonName(middleName, { required: false })) {
    return {
      ok: false,
      status: 400,
      error:
        'Middle name may only contain letters, spaces, hyphens, apostrophes, and periods.',
      code: 'MIDDLE_NAME_INVALID',
    };
  }
  if (!isValidPersonName(lastName, { required: true })) {
    return {
      ok: false,
      status: 400,
      error:
        'Last name is required and may only contain letters, spaces, hyphens, apostrophes, and periods.',
      code: 'LAST_NAME_INVALID',
    };
  }

  if (!sex || !SEX_ALLOWLIST.includes(sex)) {
    return {
      ok: false,
      status: 400,
      error: 'Gender is required (Male or Female).',
      code: 'SEX_INVALID',
    };
  }

  if (!civilStatus || !CIVIL_STATUS_ALLOWLIST.includes(civilStatus)) {
    return {
      ok: false,
      status: 400,
      error: 'Civil status is required and must be a valid option.',
      code: 'CIVIL_STATUS_INVALID',
    };
  }

  if (!course) {
    return {
      ok: false,
      status: 400,
      error: 'Course / strand is required.',
      code: 'COURSE_REQUIRED',
    };
  }

  if (!address) {
    return {
      ok: false,
      status: 400,
      error: 'Address is required.',
      code: 'ADDRESS_REQUIRED',
    };
  }

  if (!isValidEmail(emailRaw)) {
    return {
      ok: false,
      status: 400,
      error: 'A valid email address is required (max 254 characters).',
      code: 'EMAIL_INVALID',
    };
  }

  if (phoneRaw == null || phoneRaw === '' || !isValidPhone(phoneRaw)) {
    return {
      ok: false,
      status: 400,
      error: 'Phone number is required (10–15 digits).',
      code: 'PHONE_INVALID',
    };
  }

  const phone = String(phoneRaw).trim();
  const email = normalizeEmail(emailRaw);

  const computedFull =
    [firstName, middleName, lastName].filter(Boolean).join(' ') +
    (suffix ? ` ${suffix}` : '');

  return {
    ok: true,
    data: {
      firstName,
      middleName,
      lastName,
      suffix,
      sex,
      course,
      address,
      civilStatus,
      email,
      phone,
      finalFullName: computedFull.trim(),
    },
  };
}

function cleanBoundedText(value, maxLen) {
  if (typeof value !== 'string') return '';
  return value.trim().slice(0, maxLen);
}

module.exports = {
  PERSON_NAME_RE,
  EMAIL_RE,
  EMAIL_MAX,
  PERSON_NAME_MAX,
  PHONE_MIN_DIGITS,
  PHONE_MAX_DIGITS,
  TRAINING_DAILY_TITLE_MAX,
  TRAINING_DAILY_DESCRIPTION_MAX,
  TRAINING_REQUIREMENT_TITLE_MAX,
  SEX_ALLOWLIST,
  CIVIL_STATUS_ALLOWLIST,
  optTrim,
  digitsOnly,
  isValidPersonName,
  isValidEmail,
  normalizeEmail,
  isValidPhone,
  isWholeNumberString,
  parseScore0to100,
  clampScore0to100,
  validateRspApplicationCreate,
  cleanBoundedText,
};
