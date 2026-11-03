-- Verified deployment balances: prevents reprocessing already-accounted periods.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TABLE IF NOT EXISTS leave_opening_balance_setups (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  cutoff_date DATE NOT NULL CHECK (EXTRACT(DAY FROM (cutoff_date + 1)) = 1),
  sick_leave_days NUMERIC(10,3) NOT NULL CHECK (sick_leave_days >= 0),
  vacation_leave_days NUMERIC(10,3) NOT NULL CHECK (vacation_leave_days >= 0),
  reason TEXT NOT NULL CHECK (btrim(reason) <> ''),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMIT;
