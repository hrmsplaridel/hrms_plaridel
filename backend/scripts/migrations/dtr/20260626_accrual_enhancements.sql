-- ============================================================
-- Migration: Monthly Accrual Enhancements
-- Date:      2026-06-26
-- Purpose:   Adds DB-driven accrual config columns to leave_types,
--            adds separation_date to users.
-- Run with:  psql -d <db> -f this_file.sql
--            or apply via your migration runner.
-- ============================================================

-- ── 1. users: add separation_date ──────────────────────────────────────────
-- Tracks the official last day of employment. Used to prorate the final
-- month's accrual when an employee separates mid-month.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS separation_date DATE;

-- ── 2. leave_types: add accrual config columns ──────────────────────────────
-- accrues_monthly       — true for VL/SL; accrual engine reads this list
-- accrual_monthly_rate  — days credited per month (NULL → defaults to 1.25)
-- accrual_annual_cap    — max remaining balance (earned - used + adjusted)
--                         allowed for this leave type (NULL → no cap)
ALTER TABLE leave_types
  ADD COLUMN IF NOT EXISTS accrues_monthly     BOOLEAN     NOT NULL DEFAULT false;

ALTER TABLE leave_types
  ADD COLUMN IF NOT EXISTS accrual_monthly_rate NUMERIC(5,2);

ALTER TABLE leave_types
  ADD COLUMN IF NOT EXISTS accrual_annual_cap   NUMERIC(8,2);

-- ── 3. Seed VL and SL with accrual config ───────────────────────────────────
UPDATE leave_types
SET accrues_monthly      = true,
    accrual_monthly_rate = 1.25,
    accrual_annual_cap   = NULL       -- NULL = no cap (HR can set a limit later)
WHERE name IN ('vacationLeave', 'sickLeave');

-- ── 4. Index for accrual engine query ────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_leave_types_accrues_monthly
  ON leave_types (accrues_monthly)
  WHERE accrues_monthly = true;

-- ── 5. Index on users.separation_date for accrual filtering ──────────────────
CREATE INDEX IF NOT EXISTS idx_users_separation_date
  ON users (separation_date)
  WHERE separation_date IS NOT NULL;

-- ── 6. Index on users.employment_status for accrual filtering ────────────────
CREATE INDEX IF NOT EXISTS idx_users_employment_status
  ON users (employment_status)
  WHERE employment_status IS NOT NULL;
