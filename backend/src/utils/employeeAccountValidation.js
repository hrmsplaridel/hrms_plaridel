const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

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

function validateCreateEmployeePayload(payload = {}) {
  const email = typeof payload.email === 'string' ? payload.email.trim() : '';
  if (!email || email.length > 254 || !EMAIL_PATTERN.test(email)) {
    return 'A valid email is required';
  }

  for (const [field, label] of [
    ['first_name', 'First name'],
    ['last_name', 'Last name'],
    ['full_name', 'Full name'],
  ]) {
    if (
      typeof payload[field] !== 'string' ||
      payload[field].trim().length === 0
    ) {
      return `${label} is required`;
    }
  }

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

  if (
    payload.date_of_birth != null &&
    payload.date_of_birth !== '' &&
    !isValidIsoDate(payload.date_of_birth)
  ) {
    return 'Date of birth must use YYYY-MM-DD';
  }

  return null;
}

module.exports = {
  isValidIsoDate,
  isStrongTemporaryPassword,
  validateCreateEmployeePayload,
};
