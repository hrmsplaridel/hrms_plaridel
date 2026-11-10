const { normalizeEmploymentStatus } = require('./employeeStatus');

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const EMPLOYMENT_TYPES = Object.freeze([
  'permanent', 'temporary', 'casual', 'contractual', 'coterminous',
  'job_order', 'contract_of_service',
]);

function validateEmploymentType(value, currentValue = null) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value === 'string' &&
      (EMPLOYMENT_TYPES.includes(value.trim()) ||
       (value.trim() === 'regular' && currentValue === 'regular'))) return null;
  return 'Select a valid employment type';
}
const SEPARATION_EMPLOYMENT_STATUSES = new Set([
  'resigned',
  'retired',
  'terminated',
]);

function isValidIsoDate(value) {
  if (typeof value !== 'string') return false;
  const match = DATE_PATTERN.exec(value);
  if (!match) return false;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

function isStrongTemporaryPassword(value) {
  return (
    typeof value === 'string' &&
    value.length >= 12 &&
    /[a-z]/.test(value) &&
    /[A-Z]/.test(value) &&
    /\d/.test(value) &&
    /[^A-Za-z0-9]/.test(value)
  );
}

function manilaTodayDate() {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}

function validateEmployeeSeparationDates({
  dateHired,
  employmentStatus,
  separationDate,
  today = manilaTodayDate(),
} = {}) {
  const status = String(employmentStatus || 'active').trim().toLowerCase();
  const requiresSeparationDate = SEPARATION_EMPLOYMENT_STATUSES.has(status);
  const separation = separationDate == null ? '' : String(separationDate).trim();

  if (requiresSeparationDate && !separation) {
    return 'Separation date is required for resigned, retired, or terminated employees';
  }
  if (!requiresSeparationDate && separation) {
    return 'Separation date is allowed only for resigned, retired, or terminated employees';
  }
  if (!separation) return null;
  if (!isValidIsoDate(separation)) {
    return 'Separation date must use YYYY-MM-DD';
  }
  if (dateHired && isValidIsoDate(String(dateHired)) && separation < dateHired) {
    return 'Separation date cannot be before date hired';
  }
  if (today && isValidIsoDate(today) && separation > today) {
    return 'Separation date cannot be in the future';
  }
  return null;
}

class EmployeeProfileValidationError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'EmployeeProfileValidationError';
    this.statusCode = statusCode;
  }
}

function validateEmployeeProfilePayload(payload, {
  partial = false, existing = {}, today = manilaTodayDate(),
} = {}) {
  if (!partial || payload.email !== undefined) {
    const email = typeof payload.email === 'string' ? payload.email.trim() : '';
    if (!email || email.length > 254 || !EMAIL_PATTERN.test(email)) return 'A valid email is required';
  }
  for (const [field, label] of [
    ['first_name', 'First name'], ['last_name', 'Last name'], ['full_name', 'Full name'],
  ]) {
    if ((!partial || payload[field] !== undefined) &&
        (typeof payload[field] !== 'string' || !payload[field].trim())) return `${label} is required`;
  }
  for (const field of ['middle_name', 'suffix', 'sex', 'contact_number', 'address', 'civil_status', 'nationality', 'avatar_path']) {
    if (payload[field] != null && typeof payload[field] !== 'string') return `${field} must be text or null`;
  }
  for (const [field, label] of [['date_of_birth', 'Date of birth'], ['date_hired', 'Date hired']]) {
    if (payload[field] != null && payload[field] !== '' && !isValidIsoDate(payload[field])) {
      return `${label} must use YYYY-MM-DD`;
    }
  }
  if (!partial || payload.date_of_birth !== undefined || payload.date_hired !== undefined) {
    const storedDate = value => value instanceof Date ? value.toISOString().slice(0, 10) : value;
    const birth = payload.date_of_birth === undefined ? storedDate(existing.date_of_birth) : payload.date_of_birth;
    const hired = payload.date_hired === undefined ? storedDate(existing.date_hired) : payload.date_hired;
    if (birth && isValidIsoDate(birth)) {
      if (birth > today) return 'Date of birth cannot be in the future';
      if (hired && isValidIsoDate(hired) && birth >= hired) return 'Date of birth must be before date hired';
    }
  }
  return null;
}

function validateUpdateEmployeePayload(payload = {}, existing = {}, options = {}) {
  return validateEmployeeProfilePayload(payload, { ...options, partial: true, existing });
}

function validateCreateEmployeePayload(payload = {}) {
  if (payload.employment_status !== undefined && (
    typeof payload.employment_status !== 'string' ||
    normalizeEmploymentStatus(payload.employment_status) !== payload.employment_status
  )) {
    return 'Employment status must be active, inactive, resigned, retired, or terminated';
  }
  const employmentTypeError = validateEmploymentType(payload.employment_type);
  if (employmentTypeError) return employmentTypeError;
  const profileError = validateEmployeeProfilePayload(payload);
  if (profileError) return profileError;

  if (
    typeof payload.password === 'string' &&
    payload.password.trim().length > 0 &&
    !isStrongTemporaryPassword(payload.password.trim())
  ) {
    return 'Password must be at least 12 characters and include uppercase, lowercase, number, and special characters';
  }

  if (!isValidIsoDate(payload.date_hired)) {
    return 'Date hired is required and must use YYYY-MM-DD';
  }

  const separationError = validateEmployeeSeparationDates({
    dateHired: payload.date_hired,
    employmentStatus: payload.employment_status,
    separationDate: payload.separation_date,
  });
  if (separationError) return separationError;

  return null;
}

module.exports = {
  EMPLOYMENT_TYPES,
  validateEmploymentType,
  isValidIsoDate,
  isStrongTemporaryPassword,
  validateEmployeeSeparationDates,
  validateCreateEmployeePayload,
  validateUpdateEmployeePayload,
  EmployeeProfileValidationError,
  SEPARATION_EMPLOYMENT_STATUSES,
};
