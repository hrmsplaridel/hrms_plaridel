'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  DepartmentValidationError,
  normalizeDepartmentWrite,
} = require('../src/services/departmentValidation');

test('department creation trims values and supplies safe defaults', () => {
  assert.deepEqual(
    normalizeDepartmentWrite(
      {
        name: '  Human Resources  ',
        description: '  Employee services  ',
      },
      { creating: true }
    ),
    {
      name: 'Human Resources',
      description: 'Employee services',
      is_active: true,
    }
  );
});

test('department updates preserve valid explicit values', () => {
  assert.deepEqual(
    normalizeDepartmentWrite({ description: null, is_active: false }),
    { description: null, is_active: false }
  );
});

test('department name must be nonblank text', () => {
  for (const name of ['', '   ', null, 42, false]) {
    assert.throws(
      () => normalizeDepartmentWrite({ name }),
      DepartmentValidationError
    );
  }
});

test('department creation requires a name', () => {
  assert.throws(
    () => normalizeDepartmentWrite({}, { creating: true }),
    DepartmentValidationError
  );
});

test('department active status accepts only a real Boolean', () => {
  for (const isActive of ['false', 'true', 0, 1, null]) {
    assert.throws(
      () => normalizeDepartmentWrite({ is_active: isActive }),
      /is_active must be a Boolean value/
    );
  }
});

test('department description accepts only text or null', () => {
  assert.throws(
    () => normalizeDepartmentWrite({ description: 123 }),
    /Description must be a text value/
  );
});
