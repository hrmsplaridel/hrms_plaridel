-- DocuTracker: status semantics v2 (remove 'forwarded' as a status)
-- Date: 2026-04-16
--
-- Goal:
-- - Standardize "active" workflow state to 'in_review'
-- - Keep 'forwarded' as a HISTORY action only (not a document/routing status)
--
-- This migration:
-- 1) Normalizes existing 'forwarded' rows to 'in_review'
-- 2) Tightens CHECK constraints to disallow 'forwarded' going forward

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
-- 2) CHECK CONSTRAINTS
-- ============================================================
DO $$
BEGIN
  -- Documents
  ALTER TABLE docutracker_documents
    DROP CONSTRAINT IF EXISTS docutracker_documents_status_check_prod_v1;
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
    DROP CONSTRAINT IF EXISTS docutracker_routing_records_status_check_prod_v1;
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

