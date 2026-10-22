/**
 * Mayor endorsement ↔ RSP hard-isolation helpers.
 *
 * Compatibility rule:
 * - While application_id is still NOT NULL (pre-M3), intake may create a stub
 *   recruitment row so inserts succeed.
 * - After M3 (nullable application_id, no FK), intake must not create stubs
 *   and must not write recruitment application statuses.
 */

'use strict';

const MANILA_TZ = 'Asia/Manila';

function isMayorIntakeStubEmail(email) {
  const e = String(email || '').trim().toLowerCase();
  return e.endsWith('@local.intake') || e.includes('mayor-intake-');
}

function buildApplicantFullName(intakeForm = {}) {
  return [intakeForm.first_name, intakeForm.middle_name_or_initial, intakeForm.last_name]
    .map((s) => String(s || '').trim())
    .filter(Boolean)
    .join(' ')
    .trim();
}

function buildReferenceNumber(requestId, submittedAt = new Date()) {
  const id = String(requestId || '').replace(/-/g, '');
  const suffix = id.slice(0, 8).toUpperCase() || 'UNKNOWN';
  const d = submittedAt instanceof Date ? submittedAt : new Date(submittedAt);
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: MANILA_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(Number.isNaN(d.getTime()) ? new Date() : d);
  const year = parts.find((p) => p.type === 'year')?.value || '0000';
  const month = parts.find((p) => p.type === 'month')?.value || '00';
  const day = parts.find((p) => p.type === 'day')?.value || '00';
  return `MER-${year}${month}${day}-${suffix}`;
}

/** SQL fragment: calendar date in Asia/Manila for a timestamptz expression. */
function manilaDateSql(expression) {
  return `((${expression}) AT TIME ZONE '${MANILA_TZ}')::date`;
}

async function getMayorIsolationCapabilities(queryable) {
  const colRes = await queryable.query(
    `SELECT column_name, is_nullable
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'mayor_endorsement_requests'
       AND column_name IN (
         'application_id',
         'reference_number',
         'applicant_full_name',
         'endorsed_at',
         'meeting_request_status'
       )`,
  );
  const byName = new Map(
    colRes.rows.map((r) => [r.column_name, String(r.is_nullable).toUpperCase() === 'YES']),
  );

  const fkRes = await queryable.query(
    `SELECT 1
     FROM pg_constraint con
     JOIN pg_class rel ON rel.oid = con.conrelid
     JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
     WHERE nsp.nspname = 'public'
       AND rel.relname = 'mayor_endorsement_requests'
       AND con.contype = 'f'
       AND con.conname = 'mayor_endorsement_requests_application_id_fkey'
     LIMIT 1`,
  );

  const applicationIdNullable = byName.has('application_id')
    ? byName.get('application_id') === true
    : false;
  const hasCascadeFk = fkRes.rowCount > 0;

  return {
    hasReferenceNumber: byName.has('reference_number'),
    hasApplicantFullName: byName.has('applicant_full_name'),
    hasEndorsedAt: byName.has('endorsed_at'),
    hasMeetingRequestStatus: byName.has('meeting_request_status'),
    applicationIdNullable,
    hasCascadeFk,
    /** Independent creates are only safe after M3 (nullable + no CASCADE FK). */
    independentIntakeEnabled: applicationIdNullable && !hasCascadeFk,
  };
}

module.exports = {
  MANILA_TZ,
  isMayorIntakeStubEmail,
  buildApplicantFullName,
  buildReferenceNumber,
  manilaDateSql,
  getMayorIsolationCapabilities,
};
