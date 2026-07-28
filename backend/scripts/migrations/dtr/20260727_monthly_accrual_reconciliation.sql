-- ============================================================
-- Migration: Reconcilable monthly leave accrual postings
-- Date:      2026-07-27
-- Purpose:
--   Remember the credit posted for each service month so a later
--   hire, separation, assignment, eligibility, or rate correction
--   can adjust only the difference.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS leave_monthly_accrual_postings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service_month DATE NOT NULL,
  leave_type TEXT NOT NULL,
  credited_days NUMERIC(10,3) NOT NULL DEFAULT 0 CHECK (credited_days >= 0),
  accrual_rate NUMERIC(6,3) NOT NULL CHECK (accrual_rate >= 0),
  metadata_json JSONB,
  posted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_leave_monthly_accrual_posting
    UNIQUE (user_id, service_month, leave_type),
  CONSTRAINT chk_leave_monthly_accrual_service_month
    CHECK (EXTRACT(DAY FROM service_month) = 1),
  CONSTRAINT fk_leave_monthly_accrual_posting_leave_type
    FOREIGN KEY (leave_type) REFERENCES leave_types(name)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_leave_monthly_accrual_postings_month
  ON leave_monthly_accrual_postings(service_month, user_id);

-- Recognize legacy one-month accruals so the first reconciliation previews a
-- correction instead of treating an already-posted credit as new.
INSERT INTO leave_monthly_accrual_postings (
  user_id,
  service_month,
  leave_type,
  credited_days,
  accrual_rate,
  metadata_json,
  posted_at,
  created_at,
  updated_at
)
SELECT
  lbl.user_id,
  ((lbl.metadata_json->>'target_year_month') || '-01')::date,
  lbl.leave_type,
  GREATEST(0, ROUND(SUM(lbl.days_changed)::numeric, 3)),
  COALESCE(MAX(lt.accrual_monthly_rate), 1.250),
  jsonb_build_object('legacy_ledger_import', true),
  MAX(lbl.created_at),
  MIN(lbl.created_at),
  now()
FROM leave_balance_ledger lbl
LEFT JOIN leave_types lt ON lt.name = lbl.leave_type
WHERE lbl.action = 'monthly_accrual'
  AND lbl.metadata_json->>'target_year_month' ~ '^[0-9]{4}-[0-9]{2}$'
  AND COALESCE(lbl.metadata_json->>'months_credited', '1') = '1'
GROUP BY
  lbl.user_id,
  lbl.leave_type,
  lbl.metadata_json->>'target_year_month'
ON CONFLICT (user_id, service_month, leave_type) DO NOTHING;

COMMIT;
