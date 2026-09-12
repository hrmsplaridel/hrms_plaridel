'use strict';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

class PositionValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'PositionValidationError';
    this.statusCode = 400;
  }
}

function hasOwn(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function normalizeUuid(value, label) {
  if (value === null) return null;
  if (typeof value !== 'string' || !UUID_PATTERN.test(value.trim())) {
    throw new PositionValidationError(`${label} must be a valid UUID or null`);
  }
  return value.trim().toLowerCase();
}

function normalizeDate(value, label) {
  if (value === null) return null;
  if (typeof value !== 'string') {
    throw new PositionValidationError(`${label} must use YYYY-MM-DD or null`);
  }
  const text = value.trim();
  const match = DATE_PATTERN.exec(text);
  if (!match) {
    throw new PositionValidationError(`${label} must use YYYY-MM-DD or null`);
  }
  const parsed = new Date(Date.UTC(
    Number(match[1]),
    Number(match[2]) - 1,
    Number(match[3])
  ));
  if (
    parsed.getUTCFullYear() !== Number(match[1]) ||
    parsed.getUTCMonth() !== Number(match[2]) - 1 ||
    parsed.getUTCDate() !== Number(match[3])
  ) {
    throw new PositionValidationError(`${label} is invalid`);
  }
  return text;
}

function normalizePositionWrite(body, { creating = false } = {}) {
  const input = body && typeof body === 'object' && !Array.isArray(body)
    ? body
    : {};
  const normalized = {};

  if (creating || hasOwn(input, 'name')) {
    if (typeof input.name !== 'string') {
      throw new PositionValidationError('Position name must be a text value');
    }
    const name = input.name.trim();
    if (!name) {
      throw new PositionValidationError('Position name is required');
    }
    if (name.length > 200) {
      throw new PositionValidationError(
        'Position name must not exceed 200 characters'
      );
    }
    normalized.name = name;
  }

  if (hasOwn(input, 'description')) {
    if (input.description !== null && typeof input.description !== 'string') {
      throw new PositionValidationError('Description must be a text value or null');
    }
    const description = input.description?.trim() || null;
    if (description && description.length > 2000) {
      throw new PositionValidationError(
        'Description must not exceed 2000 characters'
      );
    }
    normalized.description = description;
  } else if (creating) {
    normalized.description = null;
  }

  if (hasOwn(input, 'department_id')) {
    normalized.department_id = normalizeUuid(
      input.department_id,
      'department_id'
    );
  } else if (creating) {
    normalized.department_id = null;
  }

  for (const field of ['is_department_head', 'is_active']) {
    if (hasOwn(input, field)) {
      if (typeof input[field] !== 'boolean') {
        throw new PositionValidationError(`${field} must be a Boolean value`);
      }
      normalized[field] = input[field];
    } else if (creating) {
      normalized[field] = field === 'is_active';
    }
  }

  if (hasOwn(input, 'department_head_period_id')) {
    normalized.department_head_period_id = normalizeUuid(
      input.department_head_period_id,
      'department_head_period_id'
    );
  }
  for (const field of [
    'department_head_effective_from',
    'department_head_effective_to',
  ]) {
    if (hasOwn(input, field)) {
      normalized[field] = normalizeDate(input[field], field);
    }
  }

  return normalized;
}

module.exports = {
  PositionValidationError,
  normalizePositionWrite,
};
