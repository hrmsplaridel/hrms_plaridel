const { normalizeLocatorPrintLayout } = require('./locatorPrintLayout');

const FIELDS = new Set([
  'title',
  'document_number',
  'description',
  'document_type',
  'status',
  'created_by_name',
  'created_at',
  'department_name',
  'date',
  'subject',
]);

const SIGNATURES = new Set([
  'prepared_by',
  'approved_by',
  'reviewer',
  'department_head',
  'mayor',
  'applicant',
]);

function normalizeDocuTrackerPrintLayout(value) {
  return normalizeLocatorPrintLayout(value, {
    fields: FIELDS,
    signatures: SIGNATURES,
  });
}

module.exports = {
  normalizeDocuTrackerPrintLayout,
  DOCUTRACKER_PRINT_FIELDS: FIELDS,
  DOCUTRACKER_PRINT_SIGNATURES: SIGNATURES,
};
