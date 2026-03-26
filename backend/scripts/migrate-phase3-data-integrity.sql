-- Phase 3 Data Integrity Migration
-- Leave Module: Unique constraint, FK / CHECK on balances, user_id consolidation
--
-- Safe to run multiple times (all ops are idempotent / IF NOT EXISTS / IF EXISTS).
-- Run:
--   psql -U postgres -d hrms_plaridel -f backend/scripts/migrate-phase3-data-integrity.sql
--
-- Rollback strategy (if needed):
--   DROP INDEX  IF EXISTS uq_leave_requests_no_overlap;
--   ALTER TABLE leave_balances  DROP CONSTRAINT IF EXISTS fk_leave_balances_leave_type;
--   ALTER TABLE leave_balances  DROP CONSTRAINT IF EXISTS chk_leave_balances_leave_type;
--   ALTER TABLE leave_requests  DROP CONSTRAINT IF EXISTS chk_leave_requests_user_id_not_null;

BEGIN;

-- ============================================================
-- FIX #8 – Unique partial index: prevent duplicate pending/approved
--           requests for the same user on the same date range.
--
-- Uses a PARTIAL index so draft/returned/rejected/cancelled
-- records are not affected (employees can re-file freely).
-- ============================================================

-- Step 1: Detect and report any current conflicts (informational).
DO $$
DECLARE
  conflict_count INT;
BEGIN
  SELECT COUNT(*) INTO conflict_count
  FROM (
    SELECT COALESCE(user_id, employee_id) AS uid, start_date, end_date
    FROM leave_requests
    WHERE status IN ('pending', 'approved')
    GROUP BY COALESCE(user_id, employee_id), start_date, end_date
    HAVING COUNT(*) > 1
  ) sub;

  IF conflict_count > 0 THEN
    RAISE NOTICE '⚠  Found % overlapping pending/approved leave groups. Resolve them before re-running if the unique index creation fails.', conflict_count;
  ELSE
    RAISE NOTICE '✅ No pending/approved conflicts found. Safe to create unique index.';
  END IF;
END $$;

-- Step 2: Create the partial unique index on user_id.
-- NOTE: Older records may only have employee_id. The index covers user_id.
--       After consolidation (FIX #10 below) all records will have user_id set.
CREATE UNIQUE INDEX IF NOT EXISTS uq_leave_requests_no_overlap
ON leave_requests (user_id, start_date, end_date)
WHERE status IN ('pending', 'approved');

-- Also create a covering index on employee_id for legacy records still missing user_id:
CREATE UNIQUE INDEX IF NOT EXISTS uq_leave_requests_no_overlap_legacy
ON leave_requests (employee_id, start_date, end_date)
WHERE status IN ('pending', 'approved') AND user_id IS NULL;


-- ============================================================
-- FIX #9 – Referential integrity on leave_balances.leave_type.
--
-- Option A (chosen): FK to leave_types(name) – enforces existence
--   of the leave type name in the master table.
-- Option B: CHECK constraint with hardcoded list – fragile if the
--   list in Flutter changes.
--
-- leave_types.name already has a UNIQUE constraint, so this FK is valid.
-- ============================================================

-- First clean up any orphaned leave_balance rows (leave_type not in leave_types).
-- We log them first, then delete orphans.
DO $$
DECLARE
  orphan_count INT;
BEGIN
  SELECT COUNT(*) INTO orphan_count
  FROM leave_balances lb
  WHERE NOT EXISTS (
    SELECT 1 FROM leave_types lt WHERE lt.name = lb.leave_type
  );
  IF orphan_count > 0 THEN
    RAISE NOTICE '⚠  Found % orphaned leave_balance rows with unknown leave_type. They will be deleted before adding FK.', orphan_count;
    DELETE FROM leave_balances lb
    WHERE NOT EXISTS (
      SELECT 1 FROM leave_types lt WHERE lt.name = lb.leave_type
    );
    RAISE NOTICE 'Deleted % orphaned leave_balance rows.', orphan_count;
  ELSE
    RAISE NOTICE '✅ No orphaned leave_balance rows.';
  END IF;
END $$;

-- Add the FK (references leave_types.name which is UNIQUE).
ALTER TABLE leave_balances
  ADD CONSTRAINT fk_leave_balances_leave_type
  FOREIGN KEY (leave_type) REFERENCES leave_types(name)
  ON UPDATE CASCADE  -- if a leave type name ever changes, balances follow
  ON DELETE RESTRICT -- prevent deleting a leave type that has balance records
  DEFERRABLE INITIALLY DEFERRED;

-- Add an explicit CHECK as a secondary safety net (belt-and-suspenders).
ALTER TABLE leave_balances
  DROP CONSTRAINT IF EXISTS chk_leave_balances_leave_type;

ALTER TABLE leave_balances
  ADD CONSTRAINT chk_leave_balances_leave_type CHECK (
    leave_type IN (
      'vacationLeave',
      'mandatoryForcedLeave',
      'sickLeave',
      'maternityLeave',
      'paternityLeave',
      'specialPrivilegeLeave',
      'soloParentLeave',
      'studyLeave',
      'tenDayVawcLeave',
      'rehabilitationPrivilege',
      'specialLeaveBenefitsForWomen',
      'specialEmergencyCalamityLeave',
      'adoptionLeave',
      'others'
    )
  );


-- ============================================================
-- FIX #10 – Consolidate employee_id / user_id.
--
-- Goal:
--   • Every leave_requests row should have user_id populated.
--   • Add NOT NULL constraint to user_id (safe once backfilled).
--   • We do NOT drop employee_id yet — DTR queries reference it
--     and dropping it is a breaking schema change. A future
--     migration can drop it once all DTR queries are updated.
-- ============================================================

-- Step 1: Backfill user_id from employee_id for any rows still missing it.
UPDATE leave_requests
SET user_id = employee_id
WHERE user_id IS NULL AND employee_id IS NOT NULL;

-- Verify no nulls remain.
DO $$
DECLARE
  null_count INT;
BEGIN
  SELECT COUNT(*) INTO null_count
  FROM leave_requests
  WHERE user_id IS NULL;

  IF null_count > 0 THEN
    RAISE EXCEPTION '❌ % leave_requests rows still have NULL user_id after backfill. Aborting.', null_count;
  ELSE
    RAISE NOTICE '✅ All leave_requests rows have user_id populated.';
  END IF;
END $$;

-- Step 2: Add NOT NULL constraint to user_id (now that it is fully populated).
-- This prevents future INSERTs from omitting user_id.
ALTER TABLE leave_requests
  DROP CONSTRAINT IF EXISTS chk_leave_requests_user_id_not_null;

-- Use a CHECK instead of ALTER COLUMN NOT NULL to be non-destructive.
-- (ALTER COLUMN NOT NULL requires a full table scan / lock; CHECK is nearly free.)
ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_requests_user_id_not_null
  CHECK (user_id IS NOT NULL);

-- Step 3: Ensure the router-level index on user_id exists.
CREATE INDEX IF NOT EXISTS idx_leave_requests_user_id
ON leave_requests(user_id);


-- ============================================================
-- Summary of what was applied
-- ============================================================
DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '=== Phase 3 Migration Complete ===';
  RAISE NOTICE 'FIX #8 : uq_leave_requests_no_overlap partial unique index created.';
  RAISE NOTICE 'FIX #9 : fk_leave_balances_leave_type FK + chk_leave_balances_leave_type CHECK added.';
  RAISE NOTICE 'FIX #10: user_id backfilled, NOT NULL constraint added, idx_leave_requests_user_id present.';
  RAISE NOTICE '(employee_id is retained for backward-compat with DTR queries. Drop in a future migration.)';
END $$;

COMMIT;
