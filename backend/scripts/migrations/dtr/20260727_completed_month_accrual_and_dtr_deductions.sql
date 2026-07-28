-- ============================================================
-- Migration: Completed-month accrual and DTR leave deductions
-- Date:      2026-07-27
-- Purpose:
--   1. Store leave movements to three decimal places.
--   2. Add an idempotent monthly DTR-to-Vacation-Leave posting.
--   3. Preserve 1.250 as the configured monthly VL/SL rate.
-- ============================================================

BEGIN;

ALTER TABLE leave_balances
  ALTER COLUMN earned_days TYPE NUMERIC(10,3)
    USING ROUND(earned_days::numeric, 3),
  ALTER COLUMN used_days TYPE NUMERIC(10,3)
    USING ROUND(used_days::numeric, 3),
  ALTER COLUMN pending_days TYPE NUMERIC(10,3)
    USING ROUND(pending_days::numeric, 3),
  ALTER COLUMN adjusted_days TYPE NUMERIC(10,3)
    USING ROUND(adjusted_days::numeric, 3);

ALTER TABLE leave_types
  ALTER COLUMN accrual_monthly_rate TYPE NUMERIC(6,3)
    USING ROUND(accrual_monthly_rate::numeric, 3),
  ALTER COLUMN accrual_annual_cap TYPE NUMERIC(10,3)
    USING ROUND(accrual_annual_cap::numeric, 3);

UPDATE leave_types
SET accrual_monthly_rate = 1.250
WHERE name IN ('vacationLeave', 'sickLeave')
  AND accrues_monthly = true;

CREATE TABLE IF NOT EXISTS leave_attendance_deductions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service_month DATE NOT NULL,
  leave_type TEXT NOT NULL DEFAULT 'vacationLeave',
  late_minutes INT NOT NULL DEFAULT 0 CHECK (late_minutes >= 0),
  undertime_minutes INT NOT NULL DEFAULT 0 CHECK (undertime_minutes >= 0),
  absence_minutes INT NOT NULL DEFAULT 0 CHECK (absence_minutes >= 0),
  computed_days NUMERIC(10,3) NOT NULL DEFAULT 0 CHECK (computed_days >= 0),
  deducted_days NUMERIC(10,3) NOT NULL DEFAULT 0 CHECK (deducted_days >= 0),
  without_pay_days NUMERIC(10,3) NOT NULL DEFAULT 0 CHECK (without_pay_days >= 0),
  source_record_count INT NOT NULL DEFAULT 0 CHECK (source_record_count >= 0),
  metadata_json JSONB,
  posted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_leave_attendance_deduction_month
    UNIQUE (user_id, service_month, leave_type),
  CONSTRAINT chk_leave_attendance_service_month
    CHECK (EXTRACT(DAY FROM service_month) = 1),
  CONSTRAINT chk_leave_attendance_vacation_only
    CHECK (leave_type = 'vacationLeave'),
  CONSTRAINT fk_leave_attendance_deduction_leave_type
    FOREIGN KEY (leave_type) REFERENCES leave_types(name)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_leave_attendance_deduction_leave_type'
  ) THEN
    ALTER TABLE leave_attendance_deductions
      ADD CONSTRAINT fk_leave_attendance_deduction_leave_type
      FOREIGN KEY (leave_type) REFERENCES leave_types(name)
      ON UPDATE CASCADE ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_leave_attendance_vacation_only'
  ) THEN
    ALTER TABLE leave_attendance_deductions
      ADD CONSTRAINT chk_leave_attendance_vacation_only
      CHECK (leave_type = 'vacationLeave');
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_leave_attendance_deductions_month
  ON leave_attendance_deductions(service_month, user_id);

COMMIT;
