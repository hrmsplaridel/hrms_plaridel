'use strict';

class DepartmentValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'DepartmentValidationError';
    this.statusCode = 400;
  }
}

function hasOwn(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function normalizeDepartmentWrite(body, { creating = false } = {}) {
  const input = body && typeof body === 'object' ? body : {};
  const normalized = {};

  if (creating || hasOwn(input, 'name')) {
    if (typeof input.name !== 'string') {
      throw new DepartmentValidationError('Department name must be a text value');
    }
    const name = input.name.trim();
    if (!name) {
      throw new DepartmentValidationError('Department name is required');
    }
    normalized.name = name;
  }

  if (hasOwn(input, 'description')) {
    if (input.description !== null && typeof input.description !== 'string') {
      throw new DepartmentValidationError('Description must be a text value');
    }
    normalized.description = input.description?.trim() || null;
  } else if (creating) {
    normalized.description = null;
  }

  if (hasOwn(input, 'is_active')) {
    if (typeof input.is_active !== 'boolean') {
      throw new DepartmentValidationError('is_active must be a Boolean value');
    }
    normalized.is_active = input.is_active;
  } else if (creating) {
    normalized.is_active = true;
  }

  return normalized;
}

module.exports = {
  DepartmentValidationError,
  normalizeDepartmentWrite,
};
