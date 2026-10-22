// Locator and leave forms share the same supported field types and limits.
const { normalizeEmployeeDetailSchema, customLeaveDetailValues } = require('./leaveRequestDetailsPolicy');

function normalizeLocatorFieldSchema(value, options = {}) {
  try { return normalizeEmployeeDetailSchema(value, options); }
  catch (error) { error.message = error.message.replace('A leave type', 'A locator type'); throw error; }
}

function locatorDetailValues(value, schema) {
  if (typeof value === 'string') {
    try { value = JSON.parse(value); }
    catch (_) { throw Object.assign(new Error('Additional details must be a JSON object.'), {statusCode:400}); }
  }
  if (value != null && (typeof value !== 'object' || Array.isArray(value))) {
    throw Object.assign(new Error('Additional details must be an object.'), {statusCode:400});
  }
  try { return customLeaveDetailValues(value || {}, schema, {validate:true}); }
  catch (error) { error.payload = {error:error.message}; throw error; }
}

module.exports = {normalizeLocatorFieldSchema,locatorDetailValues};
