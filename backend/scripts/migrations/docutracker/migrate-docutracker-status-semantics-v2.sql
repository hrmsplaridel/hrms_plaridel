-- DocuTracker: status semantics v2 (remove 'forwarded' as a status)
-- Date: 2026-04-16
--
-- Goal:
-- - Standardize "active" workflow state to 'in_review'
-- - Keep 'forwarded' as a HISTORY action only (not a document/routing status)
--
-- This migration:
-- 1) Normalizes existing 'forwarded' rows to 'in_review'
-- 2) Replaces prior status CHECK constraints with a single prod_v2 rule (no 'forwarded')

-- ============================================================
-- 1) DATA NORMALIZATION
-- ============================================================
UPDATE docutracker_documents
SET status = 'in_review'
WHERE status = 'forwarded';

UPDATE docutracker_routing_records
SET status = 'in_review'
WHERE status = 'forwarded';

-- ============================================================
-- 2) CHECK CONSTRAINTS (idempotent across MVP / prod_v1 / re-runs)
-- ============================================================
-- Drop every known name so ADD CONSTRAINT ... prod_v2 never collides with an
-- older CHECK that still allows 'forwarded' (would make prod_v2 redundant or fail).
DO $$
BEGIN
  -- Documents — known historical names from init-schema, MVP, production hardening, and this migration
  ALTER TABLE docutracker_documents
    DROP CONSTRAINT IF EXISTS docutracker_documents_status_check;
  ALTER TABLE docutracker_documents
    DROP CONSTRAINT IF EXISTS docutracker_documents_status_check_v2;
  ALTER TABLE docutracker_documents
    DROP CONSTRAINT IF EXISTS docutracker_documents_status_check_prod_v1;
  ALTER TABLE docutracker_documents
    DROP CONSTRAINT IF EXISTS docutracker_documents_status_check_prod_v2;

  ALTER TABLE docutracker_documents
    ADD CONSTRAINT docutracker_documents_status_check_prod_v2
    CHECK (status IN (
      'pending',
      'in_review',
      'approved',
      'rejected',
      'returned',
      'overdue',
      'escalated',
      'cancelled'
    ));

  -- Routing records
  ALTER TABLE docutracker_routing_records
    DROP CONSTRAINT IF EXISTS docutracker_routing_records_status_check_v1;
  ALTER TABLE docutracker_routing_records
    DROP CONSTRAINT IF EXISTS docutracker_routing_records_status_check_prod_v1;
  ALTER TABLE docutracker_routing_records
    DROP CONSTRAINT IF EXISTS docutracker_routing_records_status_check_prod_v2;

  ALTER TABLE docutracker_routing_records
    ADD CONSTRAINT docutracker_routing_records_status_check_prod_v2
    CHECK (status IN (
      'pending',
      'in_review',
      'approved',
      'rejected',
      'returned',
      'overdue',
      'escalated',
      'cancelled'
    ));
END $$;
