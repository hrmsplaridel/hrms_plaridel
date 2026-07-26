-- Keep account access consistent with the employment status selected by HR.
-- New records are handled by POST /api/employees; this repairs older records
-- created while that endpoint always set is_active = true.
UPDATE users
SET is_active = false,
    leave_credit_eligible = false,
    updated_at = now()
WHERE employment_status IN ('inactive', 'resigned', 'retired', 'terminated')
  AND (is_active = true OR leave_credit_eligible = true);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'users_nonactive_access_leave_check'
      AND conrelid = 'users'::regclass
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT users_nonactive_access_leave_check
      CHECK (
        COALESCE(employment_status, 'active') = 'active'
        OR (is_active = false AND leave_credit_eligible = false)
      );
  END IF;
END
$$;
