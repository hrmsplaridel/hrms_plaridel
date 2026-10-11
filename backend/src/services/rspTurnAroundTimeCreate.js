/**
 * Required Position and Office apply only when creating a Turn-Around Time row.
 * Updates stay unrestricted so historical rows with NULL values can still be saved.
 */

function requiredTatText(value, message) {
  if (typeof value !== 'string') return { error: message };
  const trimmed = value.trim();
  if (!trimmed) return { error: message };
  return { value: trimmed };
}

function validateTurnAroundTimeCreate(payload) {
  const source = payload != null && typeof payload === 'object' ? payload : {};
  const position = requiredTatText(source.position, 'Position is required.');
  const office = requiredTatText(source.office, 'Office is required.');
  const fields = {};
  if (position.error) fields.position = position.error;
  if (office.error) fields.office = office.error;
  if (Object.keys(fields).length > 0) {
    return {
      ok: false,
      status: 400,
      error: Object.values(fields).join(' '),
      code: 'TAT_CREATE_FIELDS_REQUIRED',
      fields,
    };
  }
  return { ok: true, position: position.value, office: office.value };
}

module.exports = {
  validateTurnAroundTimeCreate,
};
