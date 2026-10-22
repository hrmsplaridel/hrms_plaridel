-- M2 — Mayor hard isolation (historical backfill)
-- DO NOT RUN until M1 has been applied and approved.
-- Additive only: fills new columns from intake_form / existing timestamps.
-- Never overwrites non-empty applicant_full_name or reference_number.
-- Does NOT fabricate meeting approvals for legacy rows (meeting_request_status stays 'none').

BEGIN;

-- Cached display name from intake JSON (fallback to concatenated parts).
UPDATE public.mayor_endorsement_requests mer
SET applicant_full_name = NULLIF(
  TRIM(
    CONCAT_WS(
      ' ',
      NULLIF(TRIM(COALESCE(mer.intake_form->>'first_name', '')), ''),
      NULLIF(TRIM(COALESCE(mer.intake_form->>'middle_name_or_initial', '')), ''),
      NULLIF(TRIM(COALESCE(mer.intake_form->>'last_name', '')), '')
    )
  ),
  ''
)
WHERE COALESCE(TRIM(mer.applicant_full_name), '') = ''
  AND (
    COALESCE(TRIM(mer.intake_form->>'first_name'), '') <> ''
    OR COALESCE(TRIM(mer.intake_form->>'last_name'), '') <> ''
  );

-- Fallback: copy full_name from linked recruitment row when intake name is empty.
UPDATE public.mayor_endorsement_requests mer
SET applicant_full_name = NULLIF(TRIM(ra.full_name), '')
FROM public.recruitment_applications ra
WHERE ra.id = mer.application_id
  AND COALESCE(TRIM(mer.applicant_full_name), '') = ''
  AND COALESCE(TRIM(ra.full_name), '') <> '';

-- Human-readable reference: MER-YYYYMMDD-<first 8 of uuid> using Asia/Manila calendar date.
UPDATE public.mayor_endorsement_requests mer
SET reference_number = CONCAT(
  'MER-',
  TO_CHAR((mer.submitted_at AT TIME ZONE 'Asia/Manila'), 'YYYYMMDD'),
  '-',
  UPPER(SUBSTR(REPLACE(mer.id::text, '-', ''), 1, 8))
)
WHERE COALESCE(TRIM(mer.reference_number), '') = '';

-- Unique after backfill (safe if all rows filled).
CREATE UNIQUE INDEX IF NOT EXISTS uq_mayor_endorsement_requests_reference_number
  ON public.mayor_endorsement_requests (reference_number)
  WHERE reference_number IS NOT NULL;

-- Final endorsement decision timestamp for endorsed rows (legacy used office_form_approved_at).
UPDATE public.mayor_endorsement_requests
SET endorsed_at = COALESCE(office_form_approved_at, approved_at, updated_at)
WHERE status = 'endorsed'
  AND endorsed_at IS NULL;

COMMIT;
