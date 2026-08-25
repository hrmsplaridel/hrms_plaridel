const test = require('node:test');
const assert = require('node:assert/strict');

const {
  isValidIsoDate,
  isStrongTemporaryPassword,
  validateEmployeeSeparationDates,
  validateCreateEmployeePayload,
} = require('../src/utils/employeeAccountValidation');

const validPayload = {
  email: 'employee@example.gov.ph',
  password: 'StrongPass12!',
  first_name: 'Juan',
  last_name: 'Dela Cruz',
  full_name: 'Juan Dela Cruz',
  date_hired: '2026-07-27',
  date_of_birth: '1995-02-10',
};

test('accepts a complete employee creation payload', () => {
  assert.equal(validateCreateEmployeePayload(validPayload), null);
});

test('rejects missing and malformed email addresses', () => {
  assert.equal(
    validateCreateEmployeePayload({ ...validPayload, email: '' }),
    'A valid email is required'
  );
  assert.equal(
    validateCreateEmployeePayload({ ...validPayload, email: 'invalid' }),
    'A valid email is required'
  );
});

test('requires first, last, and full names', () => {
  for (const [field, label] of [
    ['first_name', 'First name'],
    ['last_name', 'Last name'],
    ['full_name', 'Full name'],
  ]) {
    assert.equal(
      validateCreateEmployeePayload({ ...validPayload, [field]: '   ' }),
      `${label} is required`
    );
  }
});

test('validates supplied passwords while allowing server generation', () => {
  assert.equal(isStrongTemporaryPassword('StrongPass12!'), true);
  assert.equal(isStrongTemporaryPassword('weak'), false);
  assert.match(
    validateCreateEmployeePayload({ ...validPayload, password: 'weak' }),
    /^Password must/
  );

  const withoutPassword = { ...validPayload };
  delete withoutPassword.password;
  assert.equal(validateCreateEmployeePayload(withoutPassword), null);
});

test('requires a real ISO hire date and validates optional birth date', () => {
  assert.equal(isValidIsoDate('2026-02-28'), true);
  assert.equal(isValidIsoDate('2026-02-30'), false);
  assert.match(
    validateCreateEmployeePayload({ ...validPayload, date_hired: null }),
    /^Date hired/
  );
  assert.match(
    validateCreateEmployeePayload({
      ...validPayload,
      date_of_birth: '1995-02-30',
    }),
    /^Date of birth/
  );
});

test('requires a separation date for terminal employment statuses', () => {
  assert.equal(
    validateEmployeeSeparationDates({
      dateHired: '2026-01-10',
      employmentStatus: 'resigned',
      separationDate: null,
      today: '2026-08-25',
    }),
    'Separation date is required for resigned, retired, or terminated employees'
  );
});

test('accepts a valid final service date for a separated employee', () => {
  assert.equal(
    validateEmployeeSeparationDates({
      dateHired: '2026-01-10',
      employmentStatus: 'retired',
      separationDate: '2026-08-20',
      today: '2026-08-25',
    }),
    null
  );
});

test('rejects separation before hire or after the current Manila date', () => {
  assert.equal(
    validateEmployeeSeparationDates({
      dateHired: '2026-08-10',
      employmentStatus: 'terminated',
      separationDate: '2026-08-09',
      today: '2026-08-25',
    }),
    'Separation date cannot be before date hired'
  );
  assert.equal(
    validateEmployeeSeparationDates({
      dateHired: '2026-08-10',
      employmentStatus: 'terminated',
      separationDate: '2026-08-26',
      today: '2026-08-25',
    }),
    'Separation date cannot be in the future'
  );
});

test('does not retain a separation date for active or inactive status', () => {
  assert.equal(
    validateEmployeeSeparationDates({
      dateHired: '2026-01-10',
      employmentStatus: 'active',
      separationDate: '2026-08-20',
      today: '2026-08-25',
    }),
    'Separation date is allowed only for resigned, retired, or terminated employees'
  );
});
