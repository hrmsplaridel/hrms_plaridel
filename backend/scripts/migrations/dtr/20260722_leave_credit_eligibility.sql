-- ============================================================
-- Migration: Leave Credit Eligibility Gate
-- Date:      2026-07-22
-- Purpose:   Adds an explicit user-level flag for monthly VL/SL accrual.
--            Monthly accrual also requires an active assignment in code.
-- Run with:  psql -d <db> -f this_file.sql
--            or apply via your migration runner.
-- ============================================================

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS leave_credit_eligible BOOLEAN NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_users_leave_credit_eligible
  ON users (leave_credit_eligible)
  WHERE leave_credit_eligible = true;
