-- DocuTracker: widen "one active routing record" enforcement
-- Date: 2026-04-16
--
-- Goal:
-- Ensure that a document cannot have multiple simultaneously-active routing records,
-- including cases where escalation marks a routing record as 'escalated'.
--
-- Notes:
-- - This is safe to run after migrate-docutracker-production-hardening-apply-once.sql
-- - If it fails, you have existing data with multiple active routing rows per document.
--   Fix the data (keep only one active row per document) then re-run.

DO $$
BEGIN
  -- Drop the older partial unique index if present so we can replace it.
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i'
      AND c.relname = 'idx_docutracker_routing_records_one_active_per_doc'
  ) THEN
    EXECUTE 'DROP INDEX idx_docutracker_routing_records_one_active_per_doc';
  END IF;

  BEGIN
    CREATE UNIQUE INDEX idx_docutracker_routing_records_one_active_per_doc
      ON docutracker_routing_records(document_id)
      WHERE status IN ('pending', 'in_review', 'escalated', 'overdue');
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION
      'Cannot enforce one-active-step constraint (v1): existing data has multiple active routing_records per document. Fix data then re-run.';
  END;
END $$;

