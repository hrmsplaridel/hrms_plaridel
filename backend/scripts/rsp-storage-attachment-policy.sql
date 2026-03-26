-- =============================================================================
-- RSP recruitment attachments — access policy in PostgreSQL (HRMS database)
-- =============================================================================
-- Supabase Storage uses its own `storage.objects` RLS in the Supabase project.
-- The HRMS backend signs URLs with the **service role**, which bypasses RLS.
-- This function mirrors the intended rule: only paths tied to a real application
-- may receive a signed URL (admin-only API still required by Express).
--
-- Run after init-schema-rsp.sql, same database as DATABASE_URL:
--   psql "$DATABASE_URL" -f scripts/rsp-storage-attachment-policy.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rsp_storage_path_allowed(p_path text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.recruitment_applications ra
    WHERE p_path IS NOT NULL
      AND btrim(p_path) <> ''
      AND (
        -- Primary attachment stored on the application row
        btrim(p_path) = ra.attachment_path
        -- Any object under {application_id}/... (multiple files per applicant)
        OR btrim(p_path) LIKE ra.id::text || '/%'
      )
  );
$$;

COMMENT ON FUNCTION public.rsp_storage_path_allowed(text) IS
  'True if storage object path belongs to a recruitment application (preview/download via HRMS API).';
