/**
 * Dummy recruitment_applications rows created by Mayor Endorsement Intake.
 * They are not real RSP applicants and must stay out of HR recruitment views.
 */

function mayorIntakeStubSql(alias = '') {
  const email = alias ? `${alias}.email` : 'email';
  return `(
    lower(COALESCE(${email}, '')) LIKE '%@local.intake'
    OR lower(COALESCE(${email}, '')) LIKE 'mayor-intake-%'
  )`;
}

function excludeMayorIntakeStubSql(alias = '') {
  return `NOT ${mayorIntakeStubSql(alias)}`;
}

module.exports = {
  mayorIntakeStubSql,
  excludeMayorIntakeStubSql,
};
